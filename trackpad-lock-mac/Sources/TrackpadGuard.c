#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>

#include <unistd.h>

// The only private API used by the app. A failed lookup leaves input untouched.
typedef struct {
    void *library;
    void *device;
    void (*release)(void *);
    int (*get)(void *, Boolean *);
    int (*set)(void *, Boolean);
} Trackpad;

static int open_trackpad(Trackpad *pad) {
    pad->library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LOCAL | RTLD_NOW);
    if (!pad->library) return -1;
    void *(*create)(io_service_t) = dlsym(pad->library, "MTDeviceCreateFromService");
    pad->release = dlsym(pad->library, "MTDeviceRelease");
    pad->get = dlsym(pad->library, "MTDeviceGetParserEnabled");
    pad->set = dlsym(pad->library, "MTDeviceSetParserEnabled");
    if (!create || !pad->release || !pad->get || !pad->set) return -1;

    io_iterator_t iter = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iter) != KERN_SUCCESS) return -1;
    io_service_t service, match = IO_OBJECT_NULL;
    int count = 0;
    while ((service = IOIteratorNext(iter))) {
        CFTypeRef built_in = IORegistryEntryCreateCFProperty(service, CFSTR("MT Built-In"), kCFAllocatorDefault, 0);
        if (built_in && CFEqual(built_in, kCFBooleanTrue) && ++count == 1) {
            match = service;
            IOObjectRetain(match);
        }
        if (built_in) CFRelease(built_in);
        IOObjectRelease(service);
    }
    IOObjectRelease(iter);
    if (count == 1) pad->device = create(match);
    if (match) IOObjectRelease(match);
    return pad->device ? 0 : -1;
}

static void close_trackpad(Trackpad *pad) {
    if (pad->device) pad->release(pad->device);
    if (pad->library) dlclose(pad->library);
}

static int set_and_check(Trackpad *pad, Boolean target) {
    Boolean actual = !target;
    return pad->set(pad->device, target) == 0 && pad->get(pad->device, &actual) == 0 && actual == target;
}

static int restore(Trackpad *pad) {
    for (int i = 0; i < 3; i++) {
        Boolean actual = false;
        if ((pad->get(pad->device, &actual) == 0 && actual) || set_and_check(pad, true)) return 1;
        usleep(100000);
    }
    return 0;
}

static volatile sig_atomic_t stopping = 0;
static void stop(int signal_number) {
    (void)signal_number;
    stopping = 1;
    close(STDIN_FILENO); // Wake the blocking read so normal recovery can run.
}

static int run(Trackpad *pad, const char *mode, const char *marker) {
    Boolean enabled = false;
    if (!strcmp(mode, "probe")) {
        if (pad->get(pad->device, &enabled) != 0) return 2;
        puts(enabled ? "enabled" : "disabled");
        return 0;
    }

    int lock = open(marker, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (lock < 0) return 3;
    if (flock(lock, LOCK_EX | LOCK_NB) != 0) { close(lock); return 4; }
    int result = 0;
    char pending;
    ssize_t marker_status = pread(lock, &pending, 1, 0);
    if (marker_status < 0) { result = 3; goto finish; }
    if (marker_status == 1) {
        if (!restore(pad)) { result = 7; goto finish; }
        if (ftruncate(lock, 0) != 0) { result = 3; goto finish; }
    }
    if (!strcmp(mode, "recover")) goto finish;

    if (pad->get(pad->device, &enabled) != 0 || !enabled) { result = 5; goto finish; }
    if (pwrite(lock, "1", 1, 0) != 1 || fsync(lock) != 0) { result = 3; goto finish; }

    struct pollfd input = { .fd = STDIN_FILENO, .events = POLLIN };
    if (!stopping && poll(&input, 1, 0) == 0) {
        if (set_and_check(pad, false)) {
            // Ignore broken stdout: closing the parent's input pipe still unlocks.
            puts("locked");
            fflush(stdout);
            char unused;
            while (!stopping) {
                ssize_t bytes = read(STDIN_FILENO, &unused, 1);
                if (bytes <= 0 && !(bytes < 0 && errno == EINTR)) break;
            }
        } else {
            result = 6;
        }
    }
    if (!restore(pad)) result = 7;
    else if (ftruncate(lock, 0) != 0) result = 3;
finish:
    close(lock);
    return result;
}

int main(int argc, char **argv) {
    if (!((argc == 2 && !strcmp(argv[1], "probe")) ||
          (argc == 3 && (!strcmp(argv[1], "hold") || !strcmp(argv[1], "recover"))))) return 1;
    // A guard started without a live app pipe must never lock a terminal session.
    if (!strcmp(argv[1], "hold")) {
        struct stat info;
        if (fstat(STDIN_FILENO, &info) != 0 || !S_ISFIFO(info.st_mode)) return 1;
    }
    struct sigaction action = { .sa_handler = stop };
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGHUP, &action, NULL);
    signal(SIGPIPE, SIG_IGN);
    Trackpad pad = {0};
    int result = open_trackpad(&pad) == 0 ? run(&pad, argv[1], argc == 3 ? argv[2] : NULL) : 2;
    close_trackpad(&pad);
    return result;
}

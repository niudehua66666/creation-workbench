import Foundation
import Darwin

// The workbench and menu bar use this one controller. The socket and its
// instance lock live in the user's private application support directory.
final class TrackpadControl {
    private let queue = DispatchQueue(label: "local.jackson.trackpad-lock.control")
    private let path: String
    private let lock: Int32
    private let listener: Int32
    private var source: DispatchSourceRead?

    init?(directory: URL) throws {
        path = directory.appendingPathComponent("control.sock").path
        lock = open(directory.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw POSIXError(.EACCES) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            let reason = errno
            close(lock)
            if reason == EWOULDBLOCK { return nil }
            throw POSIXError(.EIO)
        }
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { close(lock); throw POSIXError(.EIO) }
        var address = sockaddr_un()
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(listener); close(lock); throw POSIXError(.ENAMETOOLONG)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
        unlink(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(listener, 8) == 0,
              fcntl(listener, F_SETFD, FD_CLOEXEC) != -1,
              fcntl(listener, F_SETFL, O_NONBLOCK) != -1 else {
            unlink(path); close(listener); close(lock); throw POSIXError(.EIO)
        }
    }

    func start(handler: @escaping (String) -> [String: Any]) {
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        self.source = source
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let connection = accept(self.listener, nil, nil)
            guard connection >= 0 else { return }
            _ = fcntl(connection, F_SETFD, FD_CLOEXEC)
            _ = fcntl(connection, F_SETFL, 0)
            var noSignal: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
            var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
            setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(connection, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var peer: uid_t = 0
            var group: gid_t = 0
            guard getpeereid(connection, &peer, &group) == 0, peer == geteuid() else { close(connection); return }
            var buffer = [UInt8](repeating: 0, count: 32)
            var length = 0
            while length < buffer.count {
                let count = buffer.withUnsafeMutableBytes {
                    read(connection, $0.baseAddress!.advanced(by: length), $0.count - length)
                }
                guard count > 0 else { close(connection); return }
                length += count
                if let newline = buffer[..<length].firstIndex(of: 10) {
                    let command = String(decoding: buffer[..<newline], as: UTF8.self)
                    DispatchQueue.main.async {
                        let result = handler(command)
                        self.queue.async {
                            defer { close(connection) }
                            guard var data = try? JSONSerialization.data(withJSONObject: result) else { return }
                            data.append(10)
                            data.withUnsafeBytes { bytes in
                                var sent = 0
                                while sent < bytes.count {
                                    let count = write(connection, bytes.baseAddress!.advanced(by: sent), bytes.count - sent)
                                    guard count > 0 else { break }
                                    sent += count
                                }
                            }
                        }
                    }
                    return
                }
            }
            close(connection)
        }
        source.resume()
    }

    deinit {
        source?.cancel()
        unlink(path)
        close(listener)
        close(lock)
    }
}

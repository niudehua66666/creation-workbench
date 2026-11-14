import Foundation
import Network
import Darwin

@MainActor
final class WorkbenchControl {
    enum Command { case status, record, screenshot, shelf, settings }

    private let listener: NWListener
    private let socket: URL
    private let lock: Int32

    init(directory: URL = .applicationSupportDirectory.appending(path: "LightRecorder")) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        socket = directory.appendingPathComponent("workbench.sock")
        guard socket.path.utf8CString.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: socket.path)
        listener = try NWListener(using: parameters)
        let descriptor = open(directory.appendingPathComponent("workbench.lock").path,
                              O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw POSIXError(.EBUSY)
        }
        lock = descriptor
        unlink(socket.path)
    }

    func start(handle: @escaping @MainActor (Command) -> String) {
        listener.newConnectionHandler = { connection in
            let queue = DispatchQueue.main
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) { connection.cancel() }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, _ in
                let command: Command? = switch data?.first {
                case UInt8(ascii: "s"): .status
                case UInt8(ascii: "r"): .record
                case UInt8(ascii: "c"): .screenshot
                case UInt8(ascii: "p"): .shelf
                case UInt8(ascii: "t"): .settings
                default: nil
                }
                Task { @MainActor in
                    let reply = command.map(handle) ?? "invalid"
                    connection.send(content: Data((reply + "\n").utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        listener.start(queue: .main)
    }

    deinit {
        listener.cancel()
        unlink(socket.path)
        close(lock)
    }
}

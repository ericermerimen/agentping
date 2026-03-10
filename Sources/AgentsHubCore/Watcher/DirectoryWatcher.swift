import Foundation

public final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let path: String
    private let onChange: () -> Void

    public init(path: String? = nil, onChange: @escaping () -> Void) {
        self.path = path ?? NSHomeDirectory() + "/.agentshub/sessions"
        self.onChange = onChange
    }

    public func start() {
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.onChange()
        }

        source?.setCancelHandler {
            close(fd)
        }

        source?.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
    }
}

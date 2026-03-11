import Foundation

import Foundation

public final class Logger {
    private var cleared = false
    private let lock = NSLock()

    public init() {}

    public func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let logURL = URL(fileURLWithPath: "ui-debug.log", isDirectory: false)
        if !cleared {
            // Clear the log at the start of the program
            try? "".write(to: logURL, atomically: true, encoding: .utf8)
            cleared = true
        }
        print(message)
        let logMessage = message + "\n"
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}

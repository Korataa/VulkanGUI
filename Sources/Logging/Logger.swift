import Foundation

public enum LogLevel: Int, Comparable {
    case trace = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

public enum LogCategory: String, CaseIterable {
    case app = "APP"
    case ui = "UI"
    case graphics = "GFX"
    case vulkan = "VK"
    case input = "INPUT"
    case assets = "ASSET"
    case platform = "PLATFORM"
}

public final class EngineLog: @unchecked Sendable {
    public static let shared = EngineLog()

    public static func executableDirectoryURL() -> URL {
        let executablePath = CommandLine.arguments.first ?? FileManager.default.currentDirectoryPath
        let executableURL = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath()
        if executableURL.hasDirectoryPath {
            return executableURL
        }
        return executableURL.deletingLastPathComponent()
    }

    public static func defaultLogDirectoryURL() -> URL {
        executableDirectoryURL().appendingPathComponent("Logs", isDirectory: true)
    }

    public static func defaultLogFileURL(fileName: String = "engine.log") -> URL {
        defaultLogDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    public var consoleMinimumLevel: LogLevel = .info
    public var fileMinimumLevel: LogLevel = .trace
    public var enabledCategories: Set<LogCategory> = Set(LogCategory.allCases)
    public var writeToConsole: Bool = true
    public var writeToFile: Bool = false
    public var logFilePath: String = EngineLog.defaultLogFileURL().path

    private let lock = NSLock()
    private var didInitFile = false
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private init() {}

    public func configure(consoleMinimumLevel: LogLevel? = nil,
                          fileMinimumLevel: LogLevel? = nil,
                          enabledCategories: Set<LogCategory>? = nil,
                          writeToConsole: Bool? = nil,
                          writeToFile: Bool? = nil,
                          logFilePath: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        if let consoleMinimumLevel { self.consoleMinimumLevel = consoleMinimumLevel }
        if let fileMinimumLevel { self.fileMinimumLevel = fileMinimumLevel }
        if let enabledCategories { self.enabledCategories = enabledCategories }
        if let writeToConsole { self.writeToConsole = writeToConsole }
        if let writeToFile {
            self.writeToFile = writeToFile
            if !writeToFile {
                didInitFile = false
            }
        }
        if let logFilePath {
            self.logFilePath = logFilePath
            self.didInitFile = false
        }
    }

    public func log(_ level: LogLevel,
                    _ category: LogCategory,
                    source: String? = nil,
                    _ message: @autoclosure () -> String) {
        lock.lock()
        defer { lock.unlock() }

        guard enabledCategories.contains(category) else { return }

        let timestamp = dateFormatter.string(from: Date())
        let sourceLabel = source.map { "[\($0)]" } ?? ""
        let formatted = "\(timestamp) [\(level.label)][\(category.rawValue)]\(sourceLabel) \(message())"
        if writeToConsole && level >= consoleMinimumLevel {
            print(formatted)
        }

        guard writeToFile && level >= fileMinimumLevel else { return }
        let logURL = URL(fileURLWithPath: logFilePath, isDirectory: false)
        let logDirectoryURL = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        if !didInitFile {
            try? "".write(to: logURL, atomically: true, encoding: .utf8)
            didInitFile = true
        }
        let line = formatted + "\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}

public func logTrace(_ category: LogCategory, source: String? = nil, _ message: @autoclosure () -> String) {
    EngineLog.shared.log(.trace, category, source: source, message())
}

public func logDebug(_ category: LogCategory, source: String? = nil, _ message: @autoclosure () -> String) {
    EngineLog.shared.log(.debug, category, source: source, message())
}

public func logInfo(_ category: LogCategory, source: String? = nil, _ message: @autoclosure () -> String) {
    EngineLog.shared.log(.info, category, source: source, message())
}

public func logWarn(_ category: LogCategory, source: String? = nil, _ message: @autoclosure () -> String) {
    EngineLog.shared.log(.warning, category, source: source, message())
}

public func logError(_ category: LogCategory, source: String? = nil, _ message: @autoclosure () -> String) {
    EngineLog.shared.log(.error, category, source: source, message())
}

public func vkLog(_ message: String) {
    logDebug(.vulkan, source: "Vulkan", message)
}

// Compatibility wrapper for old call sites that expect a Logger object.
public final class Logger {
    public init() {}

    public func log(_ message: String) {
        logInfo(.ui, source: "Logger", message)
    }
}

import OSLog

/// Shared logging utility. Replaces synchronous `print` with async system `os_log`.
/// Categories map to OSLog's filtering for Console.app / log stream.
enum DuckLog {
    private static let subsystem = "com.duckreader.DuckReader"

    static func debug(_ message: String, category: String = "general") {
        Logger(subsystem: subsystem, category: category).debug("\(message)")
    }

    static func info(_ message: String, category: String = "general") {
        Logger(subsystem: subsystem, category: category).info("\(message)")
    }

    static func error(_ message: String, category: String = "general") {
        Logger(subsystem: subsystem, category: category).error("\(message)")
    }

    static func fault(_ message: String, category: String = "general") {
        Logger(subsystem: subsystem, category: category).fault("\(message)")
    }
}

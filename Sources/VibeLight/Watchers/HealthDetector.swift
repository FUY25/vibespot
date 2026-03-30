import Foundation

enum HealthDetector {
    struct Result: Sendable, Equatable {
        let status: String
        let detail: String

        static let ok = Result(status: "ok", detail: "")

        static func error(_ detail: String) -> Result {
            Result(status: "error", detail: detail)
        }

        static func stale(_ detail: String) -> Result {
            Result(status: "stale", detail: detail)
        }
    }

    private static let errorPatterns: [String] = [
        "API Error:",
        "\"type\":\"invalid_request_error\"",
        "\"type\":\"authentication_error\"",
        "\"type\":\"overloaded_error\"",
        "\"type\":\"rate_limit_error\"",
        "\"error\":{\"message\":",
        "status_code\":429",
        "status_code\":500",
        "status_code\":503",
    ]

    static func detectFromTail(fileURL: URL) -> Result {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return .ok
        }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let readSize = min(fileSize, UInt64(2048))
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readData(ofLength: Int(readSize))
        let text = String(decoding: data, as: UTF8.self)

        let lines = text.split(whereSeparator: \.isNewline).reversed()
        for line in lines.prefix(20) {
            let lineString = String(line)
            for pattern in errorPatterns where lineString.contains(pattern) {
                return .error(extractErrorDetail(from: lineString))
            }
        }

        return .ok
    }

    static func detectStale(
        activityStatus: SessionActivityStatus,
        lastActivityAt: Date,
        now: Date = Date()
    ) -> Result {
        guard activityStatus == .working else {
            return .ok
        }

        let elapsed = now.timeIntervalSince(lastActivityAt)
        guard elapsed > 300 else {
            return .ok
        }

        return .stale("No activity for \(Int(elapsed / 60))m")
    }

    static func resolveHealth(
        current: Result,
        stale: Result,
        tail: Result?
    ) -> Result {
        if let tail {
            return tail.status == "error" ? tail : stale
        }

        if current.status == "error" {
            return current
        }

        return stale
    }

    private static func extractErrorDetail(from line: String) -> String {
        if let range = line.range(of: "API Error: \\d{3}", options: .regularExpression) {
            let suffix = line[range.lowerBound...]
            return String(suffix.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let range = line.range(of: "\"type\":\"[^\"]+\"", options: .regularExpression) {
            return String(line[range]).replacingOccurrences(of: "\"", with: "")
        }

        if let range = line.range(of: "\"message\":\"[^\"]+\"", options: .regularExpression) {
            return String(line[range])
                .replacingOccurrences(of: "\"message\":\"", with: "")
                .replacingOccurrences(of: "\"", with: "")
        }

        return "Error detected"
    }
}

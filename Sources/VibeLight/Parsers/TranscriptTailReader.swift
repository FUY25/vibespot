// Sources/VibeLight/Parsers/TranscriptTailReader.swift
import Foundation

struct PreviewExchange: Sendable {
    let role: String     // "user" | "assistant"
    let text: String
    let isError: Bool
}

struct PreviewData: Sendable {
    let exchanges: [PreviewExchange]
    let files: [String]  // full paths, most recent first
}

enum TranscriptTailReader {
    static func read(fileURL: URL, exchangeCount: Int = 3) -> PreviewData {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return PreviewData(exchanges: [], files: [])
        }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 4096)
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readData(ofLength: Int(readSize))

        guard let text = String(data: data, encoding: .utf8) else {
            return PreviewData(exchanges: [], files: [])
        }

        var exchanges: [PreviewExchange] = []
        var files: [String] = []
        var seenFiles = Set<String>()

        let lines = text.split(whereSeparator: \.isNewline).reversed()
        for line in lines {
            guard let record = jsonObject(from: String(line)) else { continue }
            guard let type = record["type"] as? String else { continue }

            // Claude format: type == "user" | "assistant", message.content holds text
            if (type == "user" || type == "assistant") && exchanges.count < exchangeCount {
                let message = record["message"] as? [String: Any] ?? [:]
                let content = extractText(from: message["content"])
                if !content.isEmpty {
                    let isError = content.contains("API Error:") || content.contains("\"type\":\"invalid_request_error\"")
                    exchanges.append(PreviewExchange(role: type, text: String(content.prefix(200)), isError: isError))
                }
            }

            // Codex format: type == "response_item", payload.type == "message", payload.role + payload.content
            if type == "response_item", exchanges.count < exchangeCount,
               let payload = record["payload"] as? [String: Any],
               let payloadType = payload["type"] as? String, payloadType == "message",
               let role = payload["role"] as? String, role == "user" || role == "assistant" {
                let content = extractText(from: payload["content"])
                if !content.isEmpty {
                    let isError = content.contains("API Error:") || content.contains("\"type\":\"invalid_request_error\"")
                    exchanges.append(PreviewExchange(role: role, text: String(content.prefix(200)), isError: isError))
                }
            }

            // Extract file paths from tool_use (Claude format)
            if type == "assistant" {
                let message = record["message"] as? [String: Any] ?? [:]
                if let blocks = message["content"] as? [[String: Any]] {
                    for block in blocks {
                        if block["type"] as? String == "tool_use",
                           let input = block["input"] as? [String: Any] {
                            let path = (input["file_path"] as? String) ?? (input["path"] as? String) ?? ""
                            if !path.isEmpty && !seenFiles.contains(path) && files.count < 5 {
                                seenFiles.insert(path)
                                files.append(path)
                            }
                        }
                    }
                }
            }

            // Extract file paths from function_call (Codex format)
            if type == "response_item",
               let payload = record["payload"] as? [String: Any],
               let payloadType = payload["type"] as? String,
               (payloadType == "function_call" || payloadType == "custom_tool_call") {
                let args = payload["arguments"] as? [String: Any] ?? payload["input"] as? [String: Any] ?? [:]
                let path = (args["file_path"] as? String) ?? (args["path"] as? String) ?? ""
                if !path.isEmpty && !seenFiles.contains(path) && files.count < 5 {
                    seenFiles.insert(path)
                    files.append(path)
                }
            }
        }

        return PreviewData(exchanges: exchanges.reversed(), files: files)
    }

    static func previewToJSONString(_ preview: PreviewData) -> String {
        var exchangeArray: [[String: Any]] = []
        for ex in preview.exchanges {
            exchangeArray.append([
                "role": ex.role,
                "text": ex.text,
                "isError": ex.isError,
            ])
        }

        let dict: [String: Any] = [
            "exchanges": exchangeArray,
            "files": preview.files,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"exchanges\":[],\"files\":[]}"
        }
        return string
    }

    private static func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func extractText(from content: Any?) -> String {
        if let text = content as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { block -> String? in
            if block["type"] as? String == "text" { return block["text"] as? String }
            return nil
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

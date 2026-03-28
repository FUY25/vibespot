// Sources/VibeLight/UI/WebBridge.swift
import Foundation
import WebKit

@MainActor
protocol WebBridgeDelegate: AnyObject {
    func webBridge(_ bridge: WebBridge, didReceiveSearch query: String)
    func webBridge(_ bridge: WebBridge, didSelectSession sessionId: String, status: String, tool: String)
    func webBridgeDidRequestEscape(_ bridge: WebBridge)
    func webBridge(_ bridge: WebBridge, didRequestResize height: CGFloat)
    func webBridge(_ bridge: WebBridge, didRequestPreview sessionId: String)
}

@MainActor
final class WebBridge: NSObject, WKScriptMessageHandler {
    enum Message: Equatable {
        case search(query: String)
        case select(sessionId: String, status: String, tool: String)
        case escape
        case resize(height: CGFloat)
        case preview(sessionId: String)

        static func parse(_ body: [String: Any]) -> Message? {
            guard let type = body["type"] as? String else { return nil }
            switch type {
            case "search":
                guard let query = body["query"] as? String else { return nil }
                return .search(query: query)
            case "select":
                guard let sessionId = body["sessionId"] as? String, !sessionId.isEmpty else { return nil }
                guard let status = body["status"] as? String else { return nil }
                guard let tool = body["tool"] as? String else { return nil }
                return .select(sessionId: sessionId, status: status, tool: tool)
            case "escape":
                return .escape
            case "resize":
                guard let heightNumber = body["height"] as? NSNumber else { return nil }
                let height = heightNumber.doubleValue
                guard height >= 0 else { return nil }
                return .resize(height: CGFloat(height))
            case "preview":
                guard let sessionId = body["sessionId"] as? String, !sessionId.isEmpty else { return nil }
                return .preview(sessionId: sessionId)
            default:
                return nil
            }
        }
    }

    weak var delegate: WebBridgeDelegate?

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let body = message.body as? [String: Any] else { return }
            guard let parsed = Message.parse(body) else { return }
            switch parsed {
            case .search(let query):
                delegate?.webBridge(self, didReceiveSearch: query)
            case .select(let sessionId, let status, let tool):
                delegate?.webBridge(self, didSelectSession: sessionId, status: status, tool: tool)
            case .escape:
                delegate?.webBridgeDidRequestEscape(self)
            case .resize(let height):
                delegate?.webBridge(self, didRequestResize: height)
            case .preview(let sessionId):
                delegate?.webBridge(self, didRequestPreview: sessionId)
            }
        }
    }

    static func resultToJSON(_ result: SearchResult) -> [String: Any] {
        var dict: [String: Any] = [
            "sessionId": result.sessionId,
            "tool": result.tool,
            "title": result.title,
            "project": result.project,
            "projectName": result.projectName,
            "gitBranch": result.gitBranch,
            "status": result.status,
            "startedAt": ISO8601DateFormatter().string(from: result.startedAt),
            "tokenCount": result.tokenCount,
            "activityStatus": result.activityStatus.rawValue,
            "relativeTime": RelativeTimeFormatter.string(from: result.lastActivityAt),
            "healthStatus": result.healthStatus,
            "healthDetail": result.healthDetail,
        ]
        if let preview = result.activityPreview {
            dict["activityPreview"] = preview.text
            dict["activityPreviewKind"] = preview.kind.rawValue
        }
        return dict
    }

    static func resultsToJSONString(_ results: [SearchResult]) -> String {
        let array = results.map { resultToJSON($0) }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return string
    }
}

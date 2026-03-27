// Sources/VibeLight/UI/WebBridge.swift
import Foundation
import WebKit

@MainActor
protocol WebBridgeDelegate: AnyObject {
    func webBridge(_ bridge: WebBridge, didReceiveSearch query: String)
    func webBridge(_ bridge: WebBridge, didSelectSession sessionId: String, status: String, tool: String)
    func webBridgeDidRequestEscape(_ bridge: WebBridge)
    func webBridge(_ bridge: WebBridge, didRequestResize height: CGFloat)
}

@MainActor
final class WebBridge: NSObject, WKScriptMessageHandler {
    enum Message: Equatable {
        case search(query: String)
        case select(sessionId: String, status: String, tool: String)
        case escape
        case resize(height: CGFloat)

        static func parse(_ body: [String: Any]) -> Message? {
            guard let type = body["type"] as? String else { return nil }
            switch type {
            case "search":
                let query = body["query"] as? String ?? ""
                return .search(query: query)
            case "select":
                let sessionId = body["sessionId"] as? String ?? ""
                let status = body["status"] as? String ?? ""
                let tool = body["tool"] as? String ?? ""
                return .select(sessionId: sessionId, status: status, tool: tool)
            case "escape":
                return .escape
            case "resize":
                let height = body["height"] as? Double ?? 0
                return .resize(height: CGFloat(height))
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
        guard let body = message.body as? [String: Any] else { return }
        guard let parsed = Message.parse(body) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch parsed {
            case .search(let query):
                delegate?.webBridge(self, didReceiveSearch: query)
            case .select(let sessionId, let status, let tool):
                delegate?.webBridge(self, didSelectSession: sessionId, status: status, tool: tool)
            case .escape:
                delegate?.webBridgeDidRequestEscape(self)
            case .resize(let height):
                delegate?.webBridge(self, didRequestResize: height)
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
            "tokenCount": result.tokenCount,
            "activityStatus": result.activityStatus.rawValue,
            "relativeTime": RelativeTimeFormatter.string(from: result.lastActivityAt),
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

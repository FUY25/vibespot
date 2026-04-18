import Foundation
import WebKit

@MainActor
protocol OnboardingBridgeDelegate: AnyObject {
    func onboardingBridgeDidRequestContinue(_ bridge: OnboardingBridge)
    func onboardingBridgeDidRequestBack(_ bridge: OnboardingBridge)
    func onboardingBridgeDidRequestQuit(_ bridge: OnboardingBridge)
    func onboardingBridgeDidRequestFinish(_ bridge: OnboardingBridge)
    func onboardingBridgeDidRequestRunChecks(_ bridge: OnboardingBridge)
    func onboardingBridge(_ bridge: OnboardingBridge, didSetLaunchAtLogin enabled: Bool)
    func onboardingBridgeDidRequestShortcutChange(_ bridge: OnboardingBridge)
    func onboardingBridgeDidRequestShortcutReset(_ bridge: OnboardingBridge)
    func onboardingBridge(_ bridge: OnboardingBridge, didRequestResize height: CGFloat)
}

@MainActor
final class OnboardingBridge: NSObject, WKScriptMessageHandler {
    enum Message: Equatable {
        case `continue`
        case back
        case quit
        case finish
        case runChecks
        case setLaunchAtLogin(Bool)
        case changeShortcut
        case resetShortcut
        case resize(CGFloat)

        static func parse(_ body: [String: Any]) -> Message? {
            guard let type = body["type"] as? String else { return nil }
            switch type {
            case "continue":
                return .continue
            case "back":
                return .back
            case "quit":
                return .quit
            case "finish":
                return .finish
            case "runChecks":
                return .runChecks
            case "setLaunchAtLogin":
                guard let enabled = body["enabled"] as? Bool else { return nil }
                return .setLaunchAtLogin(enabled)
            case "changeShortcut":
                return .changeShortcut
            case "resetShortcut":
                return .resetShortcut
            case "resize":
                guard let height = body["height"] as? NSNumber else { return nil }
                return .resize(CGFloat(height.doubleValue))
            default:
                return nil
            }
        }
    }

    weak var delegate: OnboardingBridgeDelegate?

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let body = message.body as? [String: Any], let parsed = Message.parse(body) else { return }
            switch parsed {
            case .continue:
                delegate?.onboardingBridgeDidRequestContinue(self)
            case .back:
                delegate?.onboardingBridgeDidRequestBack(self)
            case .quit:
                delegate?.onboardingBridgeDidRequestQuit(self)
            case .finish:
                delegate?.onboardingBridgeDidRequestFinish(self)
            case .runChecks:
                delegate?.onboardingBridgeDidRequestRunChecks(self)
            case .setLaunchAtLogin(let enabled):
                delegate?.onboardingBridge(self, didSetLaunchAtLogin: enabled)
            case .changeShortcut:
                delegate?.onboardingBridgeDidRequestShortcutChange(self)
            case .resetShortcut:
                delegate?.onboardingBridgeDidRequestShortcutReset(self)
            case .resize(let height):
                delegate?.onboardingBridge(self, didRequestResize: height)
            }
        }
    }
}

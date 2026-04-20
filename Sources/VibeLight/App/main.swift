import AppKit
import Foundation

@MainActor
func configureApplication(_ app: NSApplication, delegate: AppDelegate) {
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
}

if CommandLine.arguments.contains("--print-launch-at-login-support") {
    let status = LaunchAtLoginManager().isSupportedRuntime ? "supported" : "unsupported"
    FileHandle.standardOutput.write(Data("\(status)\n".utf8))
    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = AppDelegate()
configureApplication(app, delegate: delegate)
app.run()

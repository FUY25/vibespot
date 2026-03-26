import AppKit

@MainActor
func configureApplication(_ app: NSApplication, delegate: AppDelegate) {
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
}

let app = NSApplication.shared
let delegate = AppDelegate()
configureApplication(app, delegate: delegate)
app.run()

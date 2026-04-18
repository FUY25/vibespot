import Foundation
import Testing
@testable import Flare

@Suite("Launch at login manager")
struct LaunchAtLoginManagerTests {
    @Test("treats non-app bundle runtimes as unsupported")
    func treatsNonAppBundleRuntimesAsUnsupported() {
        let runtimeURL = URL(fileURLWithPath: "/usr/local/bin/Flare")

        #expect(LaunchAtLoginManager.isSupportedRuntime(bundleURL: runtimeURL, bundleIdentifier: nil) == false)
        #expect(LaunchAtLoginManager.isSupportedRuntime(bundleURL: runtimeURL, bundleIdentifier: "com.example.Flare") == false)
    }

    @Test("treats app bundles with identifiers as supported")
    func treatsAppBundlesWithIdentifiersAsSupported() {
        let appURL = URL(fileURLWithPath: "/Applications/Flare.app")

        #expect(LaunchAtLoginManager.isSupportedRuntime(bundleURL: appURL, bundleIdentifier: "com.fuyuming.Flare"))
    }
}

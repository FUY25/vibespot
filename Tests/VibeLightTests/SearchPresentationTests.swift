import AppKit
import Foundation
import Testing
@testable import VibeLight

@MainActor
@Test
func searchPanelHidesOnDeactivate() {
    let controller = SearchPanelController()
    #expect(controller.hidesOnDeactivate == true)
}

@MainActor
@Test
func resultRowStatusTextIncludesTimestamp() {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "HH:mm"

    let text = ResultRowView.makeStatusText(
        status: "live",
        startedAt: Date(timeIntervalSince1970: 50_880),
        formatter: formatter
    )

    #expect(text == "Live 14:08")
}

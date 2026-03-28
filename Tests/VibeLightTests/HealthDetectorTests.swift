import Foundation
import Testing
@testable import VibeLight

@Test
func testHealthDetectorDetectsAPIErrorFromTail() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("health-detector-\(UUID().uuidString)")
        .appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let lines = [
        #"{"type":"assistant","message":"all good"}"#,
        #"{"type":"assistant","message":"API Error: 400 model unavailable"}"#,
    ]
    try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

    let result = HealthDetector.detectFromTail(fileURL: fileURL)

    #expect(result.status == "error")
    #expect(result.detail.contains("API Error: 400"))
}

@Test
func testHealthDetectorReturnsOkWhenTailHasNoError() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("health-detector-\(UUID().uuidString)")
        .appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let lines = [
        #"{"type":"assistant","message":"working normally"}"#,
        #"{"type":"user","message":"next prompt"}"#,
    ]
    try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

    let result = HealthDetector.detectFromTail(fileURL: fileURL)

    #expect(result == .ok)
}

@Test
func testHealthDetectorDetectsStaleWorkingSession() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    let result = HealthDetector.detectStale(
        activityStatus: .working,
        lastActivityAt: now.addingTimeInterval(-360),
        now: now
    )

    #expect(result.status == "stale")
    #expect(result.detail == "No activity for 6m")
}

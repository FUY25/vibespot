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
func testHealthDetectorDetectsAPIErrorFromTailWithLossyUTF8Boundary() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("health-detector-\(UUID().uuidString)")
        .appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let errorLine = "\nAPI Error: 400 model unavailable\n"
    let errorData = try #require(errorLine.data(using: .utf8))
    let fillerCount = 2045 - errorData.count
    let filler = String(repeating: "a", count: max(0, fillerCount))
    let data = Data("🙂".utf8) + Data(filler.utf8) + errorData
    try data.write(to: fileURL)

    let result = HealthDetector.detectFromTail(fileURL: fileURL)

    #expect(result.status == "error")
    #expect(result.detail.contains("API Error: 400"))
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

@Test
func testHealthDetectorResolveHealthPreservesExistingErrorWithoutNewTail() {
    let result = HealthDetector.resolveHealth(
        current: .error("API Error: 400 model unavailable"),
        stale: .stale("No activity for 6m"),
        tail: nil
    )

    #expect(result == .error("API Error: 400 model unavailable"))
}

@Test
func testHealthDetectorResolveHealthClearsErrorAfterCleanTail() {
    let result = HealthDetector.resolveHealth(
        current: .error("API Error: 400 model unavailable"),
        stale: .ok,
        tail: .ok
    )

    #expect(result == .ok)
}

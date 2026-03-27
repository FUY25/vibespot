import AppKit
import Foundation
import Testing
@testable import VibeLight

@Test
func debouncerCoalescesRapidCalls() async throws {
    let debouncer = Debouncer(delay: 0.05, queue: DispatchQueue(label: "DebouncerTests"))
    let counter = InvocationCounter()

    debouncer.schedule {
        Task {
            await counter.increment()
        }
    }
    debouncer.schedule {
        Task {
            await counter.increment()
        }
    }
    debouncer.schedule {
        Task {
            await counter.increment()
        }
    }

    try await Task.sleep(for: .milliseconds(120))

    #expect(await counter.value == 1)
}

@Test
func windowJumperRunProcessTimesOut() throws {
    do {
        _ = try WindowJumper.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 1"],
            timeout: 0.05
        )
        Issue.record("Expected subprocess to time out.")
    } catch let error as WindowJumper.ProcessExecutionError {
        #expect(error == .timedOut)
    }
}

@MainActor
@Test
func hotkeyManagerInitializesWithCallback() {
    _ = HotkeyManager(onToggle: {})
}

private actor InvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

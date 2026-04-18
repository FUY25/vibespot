import Foundation
import CoreServices

final class FileWatcher {
    static let defaultCallbackQueueLabel = "ai.vibelight.file-watcher"

    private final class CallbackContext {
        let onChange: @Sendable ([String]) -> Void

        init(onChange: @escaping @Sendable ([String]) -> Void) {
            self.onChange = onChange
        }
    }

    private var stream: FSEventStreamRef?
    private var callbackContext: Unmanaged<CallbackContext>?
    private let paths: [String]
    private let callbackQueue: DispatchQueue
    private let onChange: @Sendable ([String]) -> Void

    init(
        paths: [String],
        callbackQueue: DispatchQueue = DispatchQueue(label: FileWatcher.defaultCallbackQueueLabel, qos: .utility),
        onChange: @escaping @Sendable ([String]) -> Void
    ) {
        self.paths = paths
        self.callbackQueue = callbackQueue
        self.onChange = onChange
    }

    deinit {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if let callbackContext = callbackContext {
            callbackContext.release()
            self.callbackContext = nil
        }
    }

    func start() {
        // Ensure start() is idempotent and does not leak duplicate streams.
        stop()

        let pathsToWatch = paths as CFArray
        let callbackContext = Unmanaged.passRetained(CallbackContext(onChange: onChange))
        self.callbackContext = callbackContext

        var context = FSEventStreamContext()
        context.info = callbackContext.toOpaque()

        let callback: FSEventStreamCallback = { (stream, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let info = clientCallBackInfo else { return }
            let callbackContext = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            callbackContext.onChange(paths)
        }

        stream = FSEventStreamCreate(
            nil, callback, &context,
            pathsToWatch, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, callbackQueue)
            FSEventStreamStart(stream)
        } else {
            callbackContext.release()
            self.callbackContext = nil
        }
    }

    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if let callbackContext = callbackContext {
            callbackContext.release()
            self.callbackContext = nil
        }
    }
}

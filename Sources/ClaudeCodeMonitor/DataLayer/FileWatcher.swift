import CoreServices
import Foundation

@MainActor
final class FileWatcher {
    private let paths: [String]
    private let callback: @Sendable (Set<String>) -> Void
    private var stream: FSEventStreamRef?
    private var callbackBox: CallbackBox?
    private var callbackBoxPtr: UnsafeMutableRawPointer?

    init(paths: [String], callback: @escaping @Sendable (Set<String>) -> Void) {
        self.paths = paths
        self.callback = callback
    }

    func start() {
        assert(Thread.isMainThread)
        guard stream == nil else { return }

        let box = CallbackBox(callback)
        callbackBox = box
        let ptr = Unmanaged.passRetained(box).toOpaque()
        callbackBoxPtr = ptr

        var fsContext = FSEventStreamContext(
            version: 0,
            info: ptr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let cfPaths = paths as CFArray

        guard let newStream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &fsContext,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            Unmanaged<CallbackBox>.fromOpaque(ptr).release()
            callbackBox = nil
            callbackBoxPtr = nil
            return
        }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, DispatchQueue.main)
        FSEventStreamStart(newStream)
    }

    func stop() {
        assert(Thread.isMainThread)
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if let ptr = callbackBoxPtr {
            Unmanaged<CallbackBox>.fromOpaque(ptr).release()
            callbackBoxPtr = nil
        }
        callbackBox = nil
    }
}

private final class CallbackBox: @unchecked Sendable {
    let callback: @Sendable (Set<String>) -> Void
    init(_ callback: @escaping @Sendable (Set<String>) -> Void) {
        self.callback = callback
    }
}

private func fsEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()

    var changedPaths = Set<String>()
    let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    for i in 0..<numEvents {
        if let path = CFArrayGetValueAtIndex(cfArray, i) {
            let cfStr = Unmanaged<CFString>.fromOpaque(path).takeUnretainedValue()
            changedPaths.insert(cfStr as String)
        }
    }

    box.callback(changedPaths)
}

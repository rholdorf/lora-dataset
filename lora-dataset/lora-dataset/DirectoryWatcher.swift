//
//  DirectoryWatcher.swift
//  lora-dataset
//
//  Thin DispatchSource VNODE wrapper that watches a directory for filesystem
//  changes and fires a debounced callback. Used by DatasetViewModel (Plan 02)
//  to detect external file additions/deletions in the watched dataset folder.
//
//  Design notes:
//  - Uses O_EVTONLY so the file descriptor does not prevent unmounting.
//  - Watches the .write event mask, which fires for any directory content change
//    (file created, deleted, renamed) on macOS.
//  - Rapid events are coalesced via a cancel-and-reschedule DispatchWorkItem
//    pattern (default 0.5 s debounce).
//  - stop() / deinit cancel the DispatchSource, which in turn triggers the
//    cancel handler that closes the file descriptor.
//

import Foundation

/// Watches a directory for filesystem changes and fires a debounced callback.
///
/// Usage:
/// ```swift
/// let watcher = DirectoryWatcher(url: folderURL) {
///     print("directory changed!")
/// }
/// watcher.start()
/// // ... later:
/// watcher.stop()
/// ```
final class DirectoryWatcher {

    // MARK: - Private properties

    /// The directory URL being observed.
    private let url: URL

    /// Dispatch queue on which source events are delivered and `onChange` is called.
    private let queue: DispatchQueue

    /// How long (in seconds) to wait after the last event before firing `onChange`.
    private let debounceDelay: TimeInterval

    /// The callback to invoke after the debounce period settles.
    private let onChange: () -> Void

    /// The active DispatchSource, or `nil` when stopped.
    private var source: DispatchSourceFileSystemObject?

    /// Pending debounce work item; cancelled and replaced on each new event.
    private var debounceWorkItem: DispatchWorkItem?

    // MARK: - Init

    /// Creates a new watcher. Call `start()` to begin observing.
    ///
    /// - Parameters:
    ///   - url:           URL of the directory to watch.
    ///   - queue:         Dispatch queue for event delivery and callback.
    ///                    Defaults to a dedicated serial queue.
    ///   - debounceDelay: Seconds to wait after the last event before firing
    ///                    `onChange`. Defaults to 0.5.
    ///   - onChange:      Closure called (on `queue`) after the debounce settles.
    init(
        url: URL,
        queue: DispatchQueue = DispatchQueue(label: "com.lora-dataset.dirwatcher", qos: .utility),
        debounceDelay: TimeInterval = 0.5,
        onChange: @escaping () -> Void
    ) {
        self.url = url
        self.queue = queue
        self.debounceDelay = debounceDelay
        self.onChange = onChange
    }

    // MARK: - Lifecycle

    /// Begins watching the directory. Idempotent — calling start() twice is safe.
    func start() {
        guard source == nil else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[watchdog] failed to open fd for \(url.lastPathComponent)")
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: queue
        )

        src.setEventHandler { [weak self] in
            self?.scheduleCallback()
        }

        // Close the fd when the source is cancelled (stop() or deinit).
        src.setCancelHandler {
            close(fd)
        }

        src.resume()
        source = src
        print("[watchdog] started watching \(url.lastPathComponent)")
    }

    /// Stops watching. Cancels any pending debounce and releases the file descriptor.
    /// Idempotent — safe to call multiple times.
    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
        print("[watchdog] stopped watching")
    }

    // MARK: - Private

    /// Cancels any in-flight debounce work item and schedules a new one.
    private func scheduleCallback() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        queue.asyncAfter(deadline: .now() + debounceDelay, execute: item)
        debounceWorkItem = item
    }

    // MARK: - Deinit

    deinit {
        stop()
    }
}

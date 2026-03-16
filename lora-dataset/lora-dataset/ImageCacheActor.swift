//
//  ImageCacheActor.swift
//  lora-dataset
//
//  LRU in-memory image cache with adaptive memory budget and system memory
//  pressure monitoring.  Designed to back the prefetch pipeline in Plan 02.
//

import Foundation
import AppKit
import Dispatch

// Allow NSImage to cross actor boundaries safely.
// NSImage is documented as safe to use from any thread once it has been drawn.
extension NSImage: @unchecked @retroactive Sendable {}

/// An LRU image cache backed by a Swift actor.
///
/// Storage uses a dictionary for O(1) lookup and a separate access-order array
/// whose front is most-recently-used.  This is simpler than a doubly-linked list
/// and acceptable for datasets in the hundreds-of-images range.
///
/// Memory budget defaults to 15 % of physical RAM.  On memory pressure warnings
/// the cache is trimmed to 50 % of budget; on critical pressure it is cleared
/// entirely.
actor ImageCacheActor {

    // MARK: - Private types

    private struct Entry {
        let image: NSImage
        let cost: Int
    }

    // MARK: - Storage

    private var storage: [URL: Entry] = [:]
    /// Ordered list of URLs; index 0 = most recently accessed (MRU).
    private var accessOrder: [URL] = []
    private var totalCost: Int = 0

    // MARK: - Configuration

    let budgetBytes: Int

    // MARK: - Memory pressure source

    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // MARK: - Init

    /// - Parameter budgetBytes: Maximum bytes to keep in cache.  When `nil`,
    ///   defaults to 15 % of physical RAM.
    init(budgetBytes: Int? = nil) {
        self.budgetBytes = budgetBytes ?? Int(Double(ProcessInfo.processInfo.physicalMemory) * 0.15)
        // Note: cannot call actor methods from init, so pressure monitor is
        // installed via a post-init Task (see installMemoryPressureMonitor).
    }

    // MARK: - Public API

    /// Returns the cached image for `url`, or `nil` on a miss.
    /// Touching moves the entry to the MRU position.
    func image(for url: URL) -> NSImage? {
        guard let entry = storage[url] else { return nil }
        touch(url)
        return entry.image
    }

    /// Inserts `image` into the cache under `url` with a given byte `cost`.
    /// If the entry already exists, it is replaced and the access order updated.
    /// Evicts LRU entries if the total cost exceeds `budgetBytes`.
    func insert(_ image: NSImage, cost: Int, for url: URL) {
        if let existing = storage[url] {
            totalCost -= existing.cost
            removeFromOrder(url)
        }
        storage[url] = Entry(image: image, cost: cost)
        totalCost += cost
        accessOrder.insert(url, at: 0)
        evictIfNeeded()
    }

    /// Removes a single cached entry by URL. Used for targeted eviction
    /// when an external file deletion is detected by the watchdog.
    func remove(for url: URL) {
        guard storage[url] != nil else { return }
        evict(url)
        print("[cache] removed \(url.lastPathComponent) on external deletion")
    }

    /// Removes all entries and resets totalCost to 0.
    func clear() {
        storage.removeAll()
        accessOrder.removeAll()
        totalCost = 0
        print("[cache] cleared all entries")
    }

    /// Evicts LRU entries until `totalCost <= budgetBytes * fraction`.
    func evictToFraction(_ fraction: Double) {
        let target = Int(Double(budgetBytes) * fraction)
        while totalCost > target, let lru = accessOrder.last {
            evict(lru)
        }
        print("[cache] evictToFraction(\(fraction)) → totalCost=\(totalCost)")
    }

    /// Handles a system memory pressure event.
    ///
    /// - `.warning`  → evict to 50 % of budget
    /// - `.critical` → clear everything
    func handleMemoryPressure(_ event: DispatchSource.MemoryPressureEvent) {
        switch event {
        case .warning:
            print("[cache] memory pressure: warning — evicting to 50%")
            evictToFraction(0.5)
        case .critical:
            print("[cache] memory pressure: critical — clearing all")
            clear()
        default:
            break
        }
    }

    // MARK: - Test-visible properties

    var currentTotalCost: Int { totalCost }
    var entryCount: Int { storage.count }

    // MARK: - Internal helpers

    /// Moves `url` to index 0 (MRU position).
    private func touch(_ url: URL) {
        removeFromOrder(url)
        accessOrder.insert(url, at: 0)
    }

    /// Evicts LRU entries until `totalCost <= budgetBytes`.
    private func evictIfNeeded() {
        while totalCost > budgetBytes, let lru = accessOrder.last {
            evict(lru)
        }
    }

    /// Removes the entry for `url` from both storage and access order.
    private func evict(_ url: URL) {
        guard let entry = storage.removeValue(forKey: url) else { return }
        totalCost -= entry.cost
        removeFromOrder(url)
        print("[cache] evicted \(url.lastPathComponent), totalCost=\(totalCost)")
    }

    /// Removes `url` from `accessOrder`.
    private func removeFromOrder(_ url: URL) {
        if let idx = accessOrder.firstIndex(of: url) {
            accessOrder.remove(at: idx)
        }
    }

    // MARK: - Memory pressure monitor

    /// Installs a DispatchSource that responds to system memory pressure events.
    /// Call once after construction (from a Task if needed).
    func installMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak source] in
            guard let src = source else { return }
            let event = src.data
            Task {
                await self.handleMemoryPressure(event)
            }
        }
        source.resume()
        memoryPressureSource = source
    }
}

//
//  DirectoryWatcherTests.swift
//  lora-datasetTests
//
//  Tests for DirectoryWatcher (VNODE filesystem watcher with debounce)
//  and ImageCacheActor.remove(for:) targeted eviction.
//

import Testing
import Foundation
import AppKit
@testable import lora_dataset

@Suite("DirectoryWatcher")
struct DirectoryWatcherTests {

    // MARK: - Helpers

    /// Creates a unique temporary directory for a test. Caller is responsible for cleanup.
    private func makeTempDir(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("DirectoryWatcherTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Polls `condition` every 100 ms until it returns true or `timeout` elapses.
    /// Returns true if the condition became true within the timeout.
    private func waitFor(
        timeout: TimeInterval,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    // MARK: - Tests: callback on add

    @Test func testCallbackFiresOnFileAdd() async throws {
        let tempDir = try makeTempDir(name: "add")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var callbackCount = 0
        let queue = DispatchQueue(label: "test.add")
        let watcher = DirectoryWatcher(url: tempDir, queue: queue, debounceDelay: 0.3) {
            callbackCount += 1
        }
        watcher.start()

        // Give the source a moment to arm before writing
        try await Task.sleep(for: .milliseconds(100))

        let file = tempDir.appendingPathComponent("new.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let fired = await waitFor(timeout: 2.0) { callbackCount > 0 }
        watcher.stop()

        #expect(fired, "Callback should fire after a file is added")
    }

    // MARK: - Tests: callback on delete

    @Test func testCallbackFiresOnFileDelete() async throws {
        let tempDir = try makeTempDir(name: "delete")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a file first
        let file = tempDir.appendingPathComponent("existing.txt")
        try "data".write(to: file, atomically: true, encoding: .utf8)

        var callbackCount = 0
        let queue = DispatchQueue(label: "test.delete")
        let watcher = DirectoryWatcher(url: tempDir, queue: queue, debounceDelay: 0.3) {
            callbackCount += 1
        }
        watcher.start()

        try await Task.sleep(for: .milliseconds(100))

        try FileManager.default.removeItem(at: file)

        let fired = await waitFor(timeout: 2.0) { callbackCount > 0 }
        watcher.stop()

        #expect(fired, "Callback should fire after a file is deleted")
    }

    // MARK: - Tests: stop prevents further callbacks

    @Test func testStopPreventsCallbacks() async throws {
        let tempDir = try makeTempDir(name: "stop")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var callbackCount = 0
        let queue = DispatchQueue(label: "test.stop")
        let watcher = DirectoryWatcher(url: tempDir, queue: queue, debounceDelay: 0.3) {
            callbackCount += 1
        }
        watcher.start()
        try await Task.sleep(for: .milliseconds(100))
        watcher.stop()

        // Create file after stop — should NOT trigger callback
        let file = tempDir.appendingPathComponent("after-stop.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let fired = await waitFor(timeout: 1.0) { callbackCount > 0 }
        #expect(!fired, "No callback should fire after stop()")
        #expect(callbackCount == 0)
    }

    // MARK: - Tests: debounce coalesces rapid events

    @Test func testDebounceCoalescesRapidEvents() async throws {
        let tempDir = try makeTempDir(name: "debounce")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var callbackCount = 0
        let queue = DispatchQueue(label: "test.debounce")
        // Use a longer debounce so rapid writes settle before the check
        let watcher = DirectoryWatcher(url: tempDir, queue: queue, debounceDelay: 0.5) {
            callbackCount += 1
        }
        watcher.start()
        try await Task.sleep(for: .milliseconds(100))

        // Create 5 files in rapid succession
        for i in 1...5 {
            let file = tempDir.appendingPathComponent("rapid-\(i).txt")
            try "data".write(to: file, atomically: true, encoding: .utf8)
            try await Task.sleep(for: .milliseconds(20))
        }

        // Wait long enough for debounce to fire (debounce = 0.5s + some margin)
        try await Task.sleep(for: .milliseconds(1500))
        watcher.stop()

        #expect(callbackCount == 1, "5 rapid writes should coalesce into exactly 1 callback, got \(callbackCount)")
    }

    // MARK: - Tests: deinit calls stop automatically

    @Test func testDeinitCallsStop() async throws {
        let tempDir = try makeTempDir(name: "deinit")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var callbackCount = 0
        let queue = DispatchQueue(label: "test.deinit")

        // Create watcher in inner scope; after scope it should be released
        do {
            let watcher = DirectoryWatcher(url: tempDir, queue: queue, debounceDelay: 0.3) {
                callbackCount += 1
            }
            watcher.start()
            try await Task.sleep(for: .milliseconds(100))
            // watcher goes out of scope here, deinit should stop it
        }

        // After deallocation, file creation must NOT trigger callback
        let file = tempDir.appendingPathComponent("after-deinit.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let fired = await waitFor(timeout: 1.0) { callbackCount > 0 }
        #expect(!fired, "No callback after deinit — watcher should have been stopped")
    }

    // MARK: - Tests: WATCH-04 watcher replacement lifecycle

    @Test func testWatcherReplacedOnNavigation() async throws {
        let tempDirA = try makeTempDir(name: "nav-A")
        let tempDirB = try makeTempDir(name: "nav-B")
        defer {
            try? FileManager.default.removeItem(at: tempDirA)
            try? FileManager.default.removeItem(at: tempDirB)
        }

        var callbackCount = 0

        // Create watcherA, start, then stop (simulating folder navigation away)
        let watcherA = DirectoryWatcher(
            url: tempDirA,
            queue: DispatchQueue(label: "test.navA"),
            debounceDelay: 0.3
        ) {
            callbackCount += 1
        }
        watcherA.start()
        try await Task.sleep(for: .milliseconds(100))
        watcherA.stop()

        // Create watcherB on tempDirB (simulating new folder selection)
        let watcherB = DirectoryWatcher(
            url: tempDirB,
            queue: DispatchQueue(label: "test.navB"),
            debounceDelay: 0.3
        ) {
            callbackCount += 1
        }
        watcherB.start()
        try await Task.sleep(for: .milliseconds(100))

        // Write to old dir A — stopped watcher must NOT fire
        let fileA = tempDirA.appendingPathComponent("old-dir-file.txt")
        try "stale".write(to: fileA, atomically: true, encoding: .utf8)

        let firedForA = await waitFor(timeout: 1.0) { callbackCount > 0 }
        #expect(!firedForA, "Stopped watcherA must not fire for changes in tempDirA")
        #expect(callbackCount == 0)

        // Write to active dir B — active watcher MUST fire
        let fileB = tempDirB.appendingPathComponent("new-dir-file.txt")
        try "fresh".write(to: fileB, atomically: true, encoding: .utf8)

        let firedForB = await waitFor(timeout: 2.0) { callbackCount > 0 }
        watcherB.stop()

        #expect(firedForB, "Active watcherB must fire for changes in tempDirB")
        #expect(callbackCount >= 1)
    }
}

// MARK: - ImageCacheActor.remove(for:) tests

@Suite("ImageCacheActor remove(for:)")
struct ImageCacheActorRemoveTests {

    private func makeImage(width: Int, height: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    @Test func testRemoveEvictsSingleEntry() async {
        let cache = ImageCacheActor(budgetBytes: 10_000_000)
        let url = URL(fileURLWithPath: "/tmp/remove-test.png")
        let img = makeImage(width: 10, height: 10)
        let cost = 10 * 10 * 4  // 400 bytes

        await cache.insert(img, cost: cost, for: url)

        let before = await cache.image(for: url)
        #expect(before != nil, "Image should be present before remove")

        await cache.remove(for: url)

        let after = await cache.image(for: url)
        let totalCost = await cache.currentTotalCost
        let count = await cache.entryCount

        #expect(after == nil, "Image should be gone after remove(for:)")
        #expect(totalCost == 0, "totalCost should be 0 after removing the only entry")
        #expect(count == 0, "entryCount should be 0")
    }

    @Test func testRemoveIsNoOpForUnknownURL() async {
        let cache = ImageCacheActor(budgetBytes: 10_000_000)
        let url = URL(fileURLWithPath: "/tmp/unknown-remove.png")

        // Should not crash
        await cache.remove(for: url)

        let count = await cache.entryCount
        let total = await cache.currentTotalCost
        #expect(count == 0)
        #expect(total == 0)
    }

    @Test func testRemoveDecrementsCorrectCost() async {
        let cache = ImageCacheActor(budgetBytes: 10_000_000)
        let url1 = URL(fileURLWithPath: "/tmp/remove-cost-1.png")
        let url2 = URL(fileURLWithPath: "/tmp/remove-cost-2.png")

        let cost1 = 400
        let cost2 = 1600

        await cache.insert(makeImage(width: 10, height: 10), cost: cost1, for: url1)
        await cache.insert(makeImage(width: 20, height: 20), cost: cost2, for: url2)

        await cache.remove(for: url1)

        let totalCost = await cache.currentTotalCost
        let count = await cache.entryCount

        #expect(totalCost == cost2, "Only url2's cost should remain")
        #expect(count == 1, "One entry should remain")

        let result1 = await cache.image(for: url1)
        let result2 = await cache.image(for: url2)
        #expect(result1 == nil)
        #expect(result2 != nil)
    }
}

//
//  DatasetViewModelCacheTests.swift
//  lora-datasetTests
//

import Testing
import AppKit
@testable import lora_dataset

@Suite("DatasetViewModel prefetch behavior")
struct DatasetViewModelCacheTests {

    /// Creates N test ImageCaptionPair entries with URLs pointing to /tmp/test_img_{i}.png.
    /// Files don't need to exist — we're testing task enqueue logic, not actual image loading.
    private func makeTestPairs(count: Int) -> [ImageCaptionPair] {
        (0..<count).map { i in
            ImageCaptionPair(
                imageURL: URL(fileURLWithPath: "/tmp/test_img_\(i).png"),
                captionURL: URL(fileURLWithPath: "/tmp/test_img_\(i).txt"),
                captionText: "",
                savedCaptionText: ""
            )
        }
    }

    // CACHE-03: triggerPrefetch enqueues tasks for exactly the +/-2 window
    @MainActor @Test func testPrefetchEnqueuedForNeighbors() {
        let vm = DatasetViewModel()
        vm.pairs = makeTestPairs(count: 7)
        vm.selectedID = vm.pairs[3].id

        vm.triggerPrefetch(aroundID: vm.pairs[3].id)

        // Window is indices 1-5 (3 +/- 2)
        #expect(vm.prefetchTasks.count == 5)
        for i in 1...5 {
            #expect(vm.prefetchTasks[vm.pairs[i].imageURL] != nil,
                    "Expected prefetch task for index \(i)")
        }
        // Indices 0 and 6 are outside the +/-2 window
        #expect(vm.prefetchTasks[vm.pairs[0].imageURL] == nil,
                "Index 0 is outside window, should not have a task")
        #expect(vm.prefetchTasks[vm.pairs[6].imageURL] == nil,
                "Index 6 is outside window, should not have a task")
    }

    // CACHE-06: Moving the selection window cancels stale prefetch tasks
    @MainActor @Test func testStalePrefetchCancelled() async {
        let vm = DatasetViewModel()
        vm.pairs = makeTestPairs(count: 10)

        // First window: index 2 → indices 0-4
        vm.triggerPrefetch(aroundID: vm.pairs[2].id)
        let staleTasks = (0...4).compactMap { vm.prefetchTasks[vm.pairs[$0].imageURL] }
        #expect(staleTasks.count == 5, "Expected 5 stale tasks from first window")

        // Second window: index 7 → indices 5-9
        vm.triggerPrefetch(aroundID: vm.pairs[7].id)

        // Old window (indices 0-4) should no longer be in prefetchTasks
        for i in 0...4 {
            #expect(vm.prefetchTasks[vm.pairs[i].imageURL] == nil,
                    "Index \(i) is outside new window, task should have been removed")
        }

        // New window (indices 5-9) should have tasks
        for i in 5...9 {
            #expect(vm.prefetchTasks[vm.pairs[i].imageURL] != nil,
                    "Index \(i) is in new window, should have a task")
        }

        // Stale tasks should have been cancelled
        for task in staleTasks {
            #expect(task.isCancelled, "Stale task should be cancelled after window shift")
        }
    }
}

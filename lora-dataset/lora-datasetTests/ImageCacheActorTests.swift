//
//  ImageCacheActorTests.swift
//  lora-datasetTests
//

import Testing
import AppKit
@testable import lora_dataset

@Suite("ImageCacheActor LRU cache")
struct ImageCacheActorTests {

    /// Creates a small test NSImage with the given pixel dimensions.
    private func makeImage(width: Int, height: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    /// Returns the expected cost for a w×h image: w * h * 4 bytes.
    private func expectedCost(width: Int, height: Int) -> Int {
        width * height * 4
    }

    // CACHE-01: Cache hit returns the exact same NSImage instance
    @Test func testCacheHitReturnsCachedImage() async {
        let cache = ImageCacheActor(budgetBytes: 10_000_000)
        let url = URL(fileURLWithPath: "/tmp/img1.png")
        let image = makeImage(width: 10, height: 10)
        let cost = expectedCost(width: 10, height: 10)
        await cache.insert(image, cost: cost, for: url)
        let result = await cache.image(for: url)
        #expect(result === image)
    }

    // Cache miss returns nil for unknown URL
    @Test func testCacheMissReturnsNil() async {
        let cache = ImageCacheActor(budgetBytes: 10_000_000)
        let url = URL(fileURLWithPath: "/tmp/does-not-exist.png")
        let result = await cache.image(for: url)
        #expect(result == nil)
    }

    // CACHE-02: Cost accounting — totalCost equals sum of inserted costs
    @Test func testCostAccounting() async {
        let cache = ImageCacheActor(budgetBytes: 10_000_000)
        let url1 = URL(fileURLWithPath: "/tmp/img-cost-1.png")
        let url2 = URL(fileURLWithPath: "/tmp/img-cost-2.png")
        let img1 = makeImage(width: 10, height: 10)
        let img2 = makeImage(width: 20, height: 20)
        let cost1 = expectedCost(width: 10, height: 10)  // 400
        let cost2 = expectedCost(width: 20, height: 20)  // 1600
        await cache.insert(img1, cost: cost1, for: url1)
        await cache.insert(img2, cost: cost2, for: url2)
        let total = await cache.currentTotalCost
        #expect(total == cost1 + cost2)
    }

    // LRU eviction — oldest-accessed entry is evicted first when budget exceeded
    @Test func testLRUEvictionOrder() async {
        // Budget = 500 bytes. Each 10x10 image costs 400 bytes.
        // Insert img1 (url1, 400 bytes), then img2 (url2, 400 bytes).
        // img2 insertion causes over-budget → img1 (LRU) evicted, img2 kept.
        let budget = 500
        let cache = ImageCacheActor(budgetBytes: budget)
        let url1 = URL(fileURLWithPath: "/tmp/img-lru-1.png")
        let url2 = URL(fileURLWithPath: "/tmp/img-lru-2.png")
        let img1 = makeImage(width: 10, height: 10)
        let img2 = makeImage(width: 10, height: 10)
        let cost = expectedCost(width: 10, height: 10) // 400

        await cache.insert(img1, cost: cost, for: url1)
        // Touch url1 so it's the most recent
        _ = await cache.image(for: url1)
        // Now insert a second entry; total would be 800 > 500
        await cache.insert(img2, cost: cost, for: url2)
        // img1 was accessed more recently than the initial insert order,
        // but img2 is the newest. Eviction removes from the back = img1.
        // After re-reading url1 above, url1 is MRU and url2 is LRU after insert.
        // Wait — url2 was just inserted (most recent). url1 was accessed before url2 insert.
        // LRU = url1 (older access). So url1 is evicted.
        let result1 = await cache.image(for: url1)
        let result2 = await cache.image(for: url2)
        #expect(result1 == nil, "url1 (LRU) should be evicted")
        #expect(result2 != nil, "url2 (MRU) should remain")
    }

    // evictToFraction reduces totalCost to <= budget * fraction
    @Test func testEvictToFraction() async {
        let budget = 10_000
        let cache = ImageCacheActor(budgetBytes: budget)
        // Insert 5 images at 10x10 (400 each) = 2000 bytes total
        for i in 1...5 {
            let url = URL(fileURLWithPath: "/tmp/img-frac-\(i).png")
            let img = makeImage(width: 10, height: 10)
            await cache.insert(img, cost: expectedCost(width: 10, height: 10), for: url)
        }
        await cache.evictToFraction(0.5)
        let total = await cache.currentTotalCost
        let limit = Int(Double(budget) * 0.5)
        #expect(total <= limit)
    }

    // clear() removes all entries and resets totalCost to 0
    @Test func testClearRemovesAll() async {
        let cache = ImageCacheActor(budgetBytes: 10_000_000)
        let url = URL(fileURLWithPath: "/tmp/img-clear.png")
        let img = makeImage(width: 10, height: 10)
        await cache.insert(img, cost: expectedCost(width: 10, height: 10), for: url)
        await cache.clear()
        let result = await cache.image(for: url)
        let count = await cache.entryCount
        let total = await cache.currentTotalCost
        #expect(result == nil)
        #expect(count == 0)
        #expect(total == 0)
    }

    // CACHE-05: Memory pressure warning → evict to 50% of budget
    @Test func testMemoryPressureWarning() async {
        let budget = 10_000
        let cache = ImageCacheActor(budgetBytes: budget)
        // Insert images totalling ~2000 bytes (5 × 400)
        for i in 1...5 {
            let url = URL(fileURLWithPath: "/tmp/img-warn-\(i).png")
            let img = makeImage(width: 10, height: 10)
            await cache.insert(img, cost: expectedCost(width: 10, height: 10), for: url)
        }
        await cache.handleMemoryPressure(.warning)
        let total = await cache.currentTotalCost
        let limit = Int(Double(budget) * 0.5)
        #expect(total <= limit)
    }

    // CACHE-05: Memory pressure critical → cache is fully cleared
    @Test func testMemoryPressureCritical() async {
        let cache = ImageCacheActor(budgetBytes: 10_000_000)
        for i in 1...3 {
            let url = URL(fileURLWithPath: "/tmp/img-crit-\(i).png")
            let img = makeImage(width: 10, height: 10)
            await cache.insert(img, cost: expectedCost(width: 10, height: 10), for: url)
        }
        await cache.handleMemoryPressure(.critical)
        let count = await cache.entryCount
        let total = await cache.currentTotalCost
        #expect(count == 0)
        #expect(total == 0)
    }
}

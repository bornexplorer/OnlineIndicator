import Foundation

// MARK: - Minimal test harness

var testsRun = 0
var testsPassed = 0
var testsFailed = 0
var currentTestName = ""

func test(_ name: String, block: () throws -> Void) {
    currentTestName = name
    testsRun += 1
    do {
        try block()
        testsPassed += 1
        print("  PASS: \(name)")
    } catch {
        testsFailed += 1
        print("  FAIL: \(name) — \(error)")
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, file: String = #file, line: Int = #line) throws {
    guard actual == expected else {
        throw TestError.assertionFailure("expected \(expected), got \(actual)")
    }
}

func assertTrue(_ value: Bool, _ message: String = "") throws {
    guard value else {
        throw TestError.assertionFailure(message.isEmpty ? "expected true" : message)
    }
}

func assertFalse(_ value: Bool, _ message: String = "") throws {
    guard !value else {
        throw TestError.assertionFailure(message.isEmpty ? "expected false" : message)
    }
}

func assertNil<T>(_ value: T?, _ message: String = "") throws {
    guard value == nil else {
        throw TestError.assertionFailure(message.isEmpty ? "expected nil, got \(value!)" : message)
    }
}

func assertNotNil<T>(_ value: T?, _ message: String = "") throws {
    guard value != nil else {
        throw TestError.assertionFailure(message.isEmpty ? "expected non-nil" : message)
    }
}

enum TestError: Error, CustomStringConvertible {
    case assertionFailure(String)
    case timeout(String)

    var description: String {
        switch self {
        case .assertionFailure(let msg): return msg
        case .timeout(let msg): return msg
        }
    }
}

// MARK: - HistoryStore Tests

func runHistoryStoreTests() {
    print("\n📋 HistoryStore Tests")

    test("insert and query buckets") {
        let store = HistoryStore(testPath: ":memory:")
        // Wait for the DB to initialize
        try awaitInitialization(store)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let bucketMs: Int64 = 60_000

        // Insert records with different statuses
        store.insert(timestamp: now - 180_000, status: "connected", latencyMs: 12, ssid: "MyWiFi", probeUrl: "http://captive.apple.com")
        store.insert(timestamp: now - 120_000, status: "connected", latencyMs: 15, ssid: "MyWiFi", probeUrl: "http://captive.apple.com")
        store.insert(timestamp: now - 60_000,  status: "blocked",   latencyMs: nil, ssid: "MyWiFi", probeUrl: "http://captive.apple.com")
        store.insert(timestamp: now - 30_000,  status: "noNetwork", latencyMs: nil, ssid: nil,      probeUrl: "http://captive.apple.com")

        let buckets = try awaitBuckets(store, from: now - 240_000, to: now, bucketMs: bucketMs)

        // Should have at least 3 buckets (some may be merged by severity)
        try assertTrue(buckets.count >= 3, "expected at least 3 buckets, got \(buckets.count)")

        // Last bucket should be noNetwork (most severe wins)
        let last = buckets.last!
        try assertEqual(last.status, "noNetwork")
    }

    test("query stats computes correct uptime and latency") {
        let store = HistoryStore(testPath: ":memory:")
        try awaitInitialization(store)

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // 3 connected (avg latency 10ms), 1 blocked
        store.insert(timestamp: now - 200_000, status: "connected", latencyMs: 5,  ssid: nil, probeUrl: "u")
        store.insert(timestamp: now - 150_000, status: "connected", latencyMs: 10, ssid: nil, probeUrl: "u")
        store.insert(timestamp: now - 100_000, status: "connected", latencyMs: 15, ssid: nil, probeUrl: "u")
        store.insert(timestamp: now - 50_000,  status: "blocked",   latencyMs: nil, ssid: nil, probeUrl: "u")

        let stats = try awaitStats(store, from: now - 300_000, to: now)

        try assertEqual(stats.totalRows, 4)
        try assertEqual(stats.connectedRows, 3)
        try assertTrue(abs(stats.avgLatencyMs - 10.0) < 0.1, "expected avg latency ~10ms, got \(stats.avgLatencyMs)")
    }

    test("query stats detects outage transitions") {
        let store = HistoryStore(testPath: ":memory:")
        try awaitInitialization(store)

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // connected -> blocked = 1 outage
        store.insert(timestamp: now - 200_000, status: "connected", latencyMs: 5, ssid: nil, probeUrl: "u")
        store.insert(timestamp: now - 150_000, status: "blocked",   latencyMs: nil, ssid: nil, probeUrl: "u")
        // blocked -> noNetwork is NOT an outage (not from connected)
        store.insert(timestamp: now - 100_000, status: "noNetwork", latencyMs: nil, ssid: nil, probeUrl: "u")
        // noNetwork -> connected = not an outage
        store.insert(timestamp: now - 50_000,  status: "connected", latencyMs: 8, ssid: nil, probeUrl: "u")

        let stats = try awaitStats(store, from: now - 300_000, to: now)

        try assertEqual(stats.outageCount, 1)
        try assertEqual(stats.totalRows, 4)
        try assertEqual(stats.connectedRows, 2)
    }

    test("query segments returns raw records ordered by timestamp") {
        let store = HistoryStore(testPath: ":memory:")
        try awaitInitialization(store)

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        store.insert(timestamp: now - 100_000, status: "connected", latencyMs: 20, ssid: "Home", probeUrl: "http://a.com")
        store.insert(timestamp: now - 50_000,  status: "blocked",   latencyMs: nil, ssid: nil,  probeUrl: "http://a.com")
        store.insert(timestamp: now,           status: "noNetwork", latencyMs: nil, ssid: nil,  probeUrl: "http://a.com")

        let segments = try awaitSegments(store, from: now - 200_000, to: now)

        try assertEqual(segments.count, 3)
        try assertEqual(segments[0].status, "connected")
        try assertEqual(segments[0].ssid, "Home")
        try assertEqual(segments[0].latencyMs, 20)
        try assertEqual(segments[1].status, "blocked")
        try assertNil(segments[1].ssid)
        try assertNil(segments[1].latencyMs)
        try assertEqual(segments[2].status, "noNetwork")
    }

    test("clear all removes all records") {
        let store = HistoryStore(testPath: ":memory:")
        try awaitInitialization(store)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        store.insert(timestamp: now, status: "connected", latencyMs: 5, ssid: nil, probeUrl: "u")
        store.insert(timestamp: now + 1, status: "blocked", latencyMs: nil, ssid: nil, probeUrl: "u")

        // Verify rows exist
        let before = try awaitStats(store, from: 0, to: now + 1000)
        try assertEqual(before.totalRows, 2)

        // Clear
        store.clearAll {}
        Thread.sleep(forTimeInterval: 0.2)

        let after = try awaitStats(store, from: 0, to: now + 1000)
        try assertEqual(after.totalRows, 0)
    }

    test("bucket severity: noNetwork wins over blocked and connected") {
        let store = HistoryStore(testPath: ":memory:")
        try awaitInitialization(store)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let bucketMs: Int64 = 60_000

        // All three statuses in the same minute bucket -> noNetwork should win
        store.insert(timestamp: now, status: "connected", latencyMs: 5, ssid: nil, probeUrl: "u")
        store.insert(timestamp: now + 1000, status: "blocked", latencyMs: nil, ssid: nil, probeUrl: "u")
        store.insert(timestamp: now + 2000, status: "noNetwork", latencyMs: nil, ssid: nil, probeUrl: "u")

        let buckets = try awaitBuckets(store, from: now - 1000, to: now + bucketMs, bucketMs: bucketMs)
        try assertTrue(buckets.count >= 1)
        try assertEqual(buckets.last!.status, "noNetwork")
    }

    test("range filter excludes records outside time range") {
        let store = HistoryStore(testPath: ":memory:")
        try awaitInitialization(store)

        let now = Int64(Date().timeIntervalSince1970 * 1000)

        store.insert(timestamp: now - 100_000, status: "connected", latencyMs: 5, ssid: nil, probeUrl: "u")
        store.insert(timestamp: now,           status: "blocked",   latencyMs: nil, ssid: nil, probeUrl: "u")
        store.insert(timestamp: now + 100_000, status: "noNetwork", latencyMs: nil, ssid: nil, probeUrl: "u")

        // Query a narrow range that only includes the middle record
        let stats = try awaitStats(store, from: now - 1000, to: now + 1000)
        try assertEqual(stats.totalRows, 1)
    }
}

// MARK: - Merge Consecutive

struct ChartSegment {
    let endTime: Date
    let status: String
}

func mergeConsecutive(_ buckets: [HistoryStore.Bucket], bucketMs: Int64) -> [ChartSegment] {
    guard !buckets.isEmpty else { return [] }

    var result: [ChartSegment] = []
    var currentStatus = buckets[0].status

    for i in 1..<buckets.count {
        let b = buckets[i]
        if b.status == currentStatus {
            continue
        } else {
            result.append(ChartSegment(
                endTime: Date(timeIntervalSince1970: Double(b.timestamp) / 1000),
                status:  currentStatus
            ))
            currentStatus = b.status
        }
    }

    // Final segment
    let lastBucket = buckets.last!
    let endMs = min(lastBucket.timestamp + bucketMs, Int64(Date().timeIntervalSince1970 * 1000))
    result.append(ChartSegment(
        endTime: Date(timeIntervalSince1970: Double(endMs) / 1000),
        status:  currentStatus
    ))

    return result
}

// MARK: - Merge Consecutive Tests

func runMergeConsecutiveTests() {
    print("\n📋 MergeConsecutive Tests")

    let bucketMs: Int64 = 60_000
    let base = Int64(Date().timeIntervalSince1970 * 1000)

    test("single bucket returns one segment") {
        let buckets = [HistoryStore.Bucket(timestamp: base, status: "connected")]
        let result = mergeConsecutive(buckets, bucketMs: bucketMs)
        try assertEqual(result.count, 1)
        try assertEqual(result[0].status, "connected")
    }

    test("consecutive same status are merged") {
        let buckets = [
            HistoryStore.Bucket(timestamp: base, status: "connected"),
            HistoryStore.Bucket(timestamp: base + bucketMs, status: "connected"),
            HistoryStore.Bucket(timestamp: base + bucketMs * 2, status: "connected"),
        ]
        let result = mergeConsecutive(buckets, bucketMs: bucketMs)
        try assertEqual(result.count, 1)
        try assertEqual(result[0].status, "connected")
    }

    test("different statuses produce separate segments") {
        let buckets = [
            HistoryStore.Bucket(timestamp: base, status: "connected"),
            HistoryStore.Bucket(timestamp: base + bucketMs, status: "blocked"),
            HistoryStore.Bucket(timestamp: base + bucketMs * 2, status: "noNetwork"),
        ]
        let result = mergeConsecutive(buckets, bucketMs: bucketMs)
        try assertEqual(result.count, 3)
        try assertEqual(result[0].status, "connected")
        try assertEqual(result[1].status, "blocked")
        try assertEqual(result[2].status, "noNetwork")
    }

    test("alternating statuses are not merged") {
        let buckets = [
            HistoryStore.Bucket(timestamp: base, status: "connected"),
            HistoryStore.Bucket(timestamp: base + bucketMs, status: "blocked"),
            HistoryStore.Bucket(timestamp: base + bucketMs * 2, status: "connected"),
        ]
        let result = mergeConsecutive(buckets, bucketMs: bucketMs)
        try assertEqual(result.count, 3)
    }

    test("adjacent same-status blocks are merged correctly") {
        let buckets = [
            HistoryStore.Bucket(timestamp: base, status: "connected"),
            HistoryStore.Bucket(timestamp: base + bucketMs, status: "connected"),
            HistoryStore.Bucket(timestamp: base + bucketMs * 2, status: "blocked"),
            HistoryStore.Bucket(timestamp: base + bucketMs * 3, status: "blocked"),
            HistoryStore.Bucket(timestamp: base + bucketMs * 4, status: "connected"),
        ]
        let result = mergeConsecutive(buckets, bucketMs: bucketMs)
        try assertEqual(result.count, 3) // connected, blocked, connected
        try assertEqual(result[0].status, "connected")
        try assertEqual(result[1].status, "blocked")
        try assertEqual(result[2].status, "connected")
    }

    test("empty input returns empty output") {
        let buckets: [HistoryStore.Bucket] = []
        let result = mergeConsecutive(buckets, bucketMs: bucketMs)
        try assertEqual(result.count, 0)
    }
}

// MARK: - Async helpers

func awaitInitialization(_ store: HistoryStore) throws {
    // Wait a bit for the DB to initialize on the serial queue
    Thread.sleep(forTimeInterval: 0.1)
}

final class Flag {
    var value = false
}

func awaitBuckets(_ store: HistoryStore, from: Int64, to: Int64, bucketMs: Int64) throws -> [HistoryStore.Bucket] {
    var result: [HistoryStore.Bucket] = []
    let done = Flag()
    store.queryBuckets(from: from, to: to, bucketMs: bucketMs) { buckets in
        result = buckets
        done.value = true
    }
    let deadline = Date().addingTimeInterval(3)
    while !done.value && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    guard done.value else { throw TestError.timeout("queryBuckets timed out") }
    return result
}

func awaitStats(_ store: HistoryStore, from: Int64, to: Int64) throws -> HistoryStore.Stats {
    var result: HistoryStore.Stats?
    let done = Flag()
    store.queryStats(from: from, to: to) { stats in
        result = stats
        done.value = true
    }
    let deadline = Date().addingTimeInterval(3)
    while !done.value && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    guard let r = result else { throw TestError.timeout("queryStats timed out") }
    return r
}

func awaitSegments(_ store: HistoryStore, from: Int64, to: Int64) throws -> [HistoryStore.Segment] {
    var result: [HistoryStore.Segment] = []
    let done = Flag()
    store.querySegments(from: from, to: to) { segments in
        result = segments
        done.value = true
    }
    let deadline = Date().addingTimeInterval(3)
    while !done.value && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    guard done.value else { throw TestError.timeout("querySegments timed out") }
    return result
}

// MARK: - Run all tests

print("═══════════════════════════════════════")
print("  Online Indicator — Test Suite")
print("═══════════════════════════════════════")

runHistoryStoreTests()
runMergeConsecutiveTests()

print("\n═══════════════════════════════════════")
print("  Results: \(testsPassed)/\(testsRun) passed")
if testsFailed > 0 {
    print("  \(testsFailed) test(s) FAILED")
    exit(1)
} else {
    print("  All tests passed")
    exit(0)
}

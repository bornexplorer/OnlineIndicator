import Foundation
import SQLite3

// MARK: - Model

struct HistoryRecord {
    let id: Int64
    let timestamp: Int64
    let status: String
    let latencyMs: Int?
    let ssid: String?
    let probeUrl: String
}

// MARK: - Store

class HistoryStore {

    static let shared = HistoryStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.bornexplorer.OnlineIndicator.history", qos: .utility)
    private var initialized = false

    private init() {
        queue.async { [weak self] in
            self?.openDatabase(at: nil)
        }
    }

    /// Initializer for testing: pass a custom path or ":memory:" for an in-memory DB.
    init(testPath: String) {
        queue.async { [weak self] in
            self?.openDatabase(at: testPath)
        }
    }

    // MARK: - Schema

    private func openDatabase(at customPath: String?) {
        let path: String
        if let customPath {
            path = customPath
        } else {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else { return }
            let dir = appSupport.appendingPathComponent("OnlineIndicator")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            path = dir.appendingPathComponent("history.db").path
        }

        if sqlite3_open(path, &db) != SQLITE_OK {
            print("HistoryStore: failed to open db at \(path)")
            return
        }

        let createSQL = """
            CREATE TABLE IF NOT EXISTS connection_log (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp  INTEGER NOT NULL,
                status     TEXT    NOT NULL,
                latency_ms INTEGER,
                ssid       TEXT,
                probe_url  TEXT    NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_connection_log_timestamp
                ON connection_log(timestamp);
        """

        if sqlite3_exec(db, createSQL, nil, nil, nil) != SQLITE_OK {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            print("HistoryStore: schema error: \(msg)")
        }

        initialized = true
    }

    // MARK: - Insert

    func insert(timestamp: Int64, status: String, latencyMs: Int?, ssid: String?, probeUrl: String) {
        queue.async { [weak self] in
            guard let self, let db = self.db, self.initialized else { return }

            let sql = """
                INSERT INTO connection_log (timestamp, status, latency_ms, ssid, probe_url)
                VALUES (?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else { return }
            defer { sqlite3_finalize(s) }

            sqlite3_bind_int64(s, 1, timestamp)
            sqlite3_bind_text(s, 2, (status as NSString).utf8String, -1, nil)
            if let lat = latencyMs {
                sqlite3_bind_int64(s, 3, Int64(lat))
            } else {
                sqlite3_bind_null(s, 3)
            }
            if let ssid {
                sqlite3_bind_text(s, 4, (ssid as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(s, 4)
            }
            sqlite3_bind_text(s, 5, (probeUrl as NSString).utf8String, -1, nil)

            if sqlite3_step(s) != SQLITE_DONE {
                print("HistoryStore: insert failed")
            }
        }
    }

    // MARK: - Query

    struct Bucket {
        let timestamp: Int64
        let status: String
    }

    func queryBuckets(from: Int64, to: Int64, bucketMs: Int64, completion: @escaping ([Bucket]) -> Void) {
        queue.async { [weak self] in
            guard let self, let db = self.db, self.initialized else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let sql = """
                SELECT (timestamp / ?) * ? AS bucket,
                       CASE
                           WHEN SUM(CASE WHEN status = 'noNetwork' THEN 1 ELSE 0 END) > 0 THEN 'noNetwork'
                           WHEN SUM(CASE WHEN status = 'blocked'   THEN 1 ELSE 0 END) > 0 THEN 'blocked'
                           ELSE 'connected'
                       END AS worst_status
                FROM connection_log
                WHERE timestamp >= ? AND timestamp <= ?
                GROUP BY bucket
                ORDER BY bucket ASC;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            defer { sqlite3_finalize(s) }

            sqlite3_bind_int64(s, 1, bucketMs)
            sqlite3_bind_int64(s, 2, bucketMs)
            sqlite3_bind_int64(s, 3, from)
            sqlite3_bind_int64(s, 4, to)

            var result: [Bucket] = []
            while sqlite3_step(s) == SQLITE_ROW {
                let ts     = sqlite3_column_int64(s, 0)
                let status = String(cString: sqlite3_column_text(s, 1))
                result.append(Bucket(timestamp: ts, status: status))
            }

            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Stats

    struct Stats {
        var totalRows: Int
        var connectedRows: Int
        var avgLatencyMs: Double
        var outageCount: Int
    }

    func queryStats(from: Int64, to: Int64, completion: @escaping (Stats) -> Void) {
        queue.async { [weak self] in
            guard let self, let db = self.db, self.initialized else {
                DispatchQueue.main.async {
                    completion(Stats(totalRows: 0, connectedRows: 0, avgLatencyMs: 0, outageCount: 0))
                }
                return
            }

            var stats = Stats(totalRows: 0, connectedRows: 0, avgLatencyMs: 0, outageCount: 0)

            // Total and connected counts with avg latency
            let countSQL = """
                SELECT COUNT(*),
                       SUM(CASE WHEN status = 'connected' THEN 1 ELSE 0 END),
                       AVG(CASE WHEN status = 'connected' THEN latency_ms ELSE NULL END)
                FROM connection_log
                WHERE timestamp >= ? AND timestamp <= ?;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, from)
                sqlite3_bind_int64(stmt, 2, to)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    stats.totalRows     = Int(sqlite3_column_int64(stmt, 0))
                    stats.connectedRows = Int(sqlite3_column_int64(stmt, 1))
                    stats.avgLatencyMs  = Double(sqlite3_column_double(stmt, 2))
                }
                sqlite3_finalize(stmt)
            }

            // Outage transitions: connected -> blocked or noNetwork
            let transitionSQL = """
                SELECT COUNT(*)
                FROM connection_log a
                JOIN connection_log b ON b.id = a.id + 1
                WHERE a.status = 'connected'
                  AND b.status IN ('blocked', 'noNetwork')
                  AND a.timestamp >= ?
                  AND b.timestamp <= ?;
            """

            if sqlite3_prepare_v2(db, transitionSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, from)
                sqlite3_bind_int64(stmt, 2, to)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    stats.outageCount = Int(sqlite3_column_int64(stmt, 0))
                }
                sqlite3_finalize(stmt)
            }

            DispatchQueue.main.async { completion(stats) }
        }
    }

    // MARK: - Raw segments for tooltip

    struct Segment: Identifiable {
        let id: Int64
        let timestamp: Int64
        let status: String
        let latencyMs: Int?
        let ssid: String?
    }

    func querySegments(from: Int64, to: Int64, completion: @escaping ([Segment]) -> Void) {
        queue.async { [weak self] in
            guard let self, let db = self.db, self.initialized else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let sql = """
                SELECT id, timestamp, status, latency_ms, ssid
                FROM connection_log
                WHERE timestamp >= ? AND timestamp <= ?
                ORDER BY timestamp ASC;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            defer { sqlite3_finalize(s) }

            sqlite3_bind_int64(s, 1, from)
            sqlite3_bind_int64(s, 2, to)

            var result: [Segment] = []
            while sqlite3_step(s) == SQLITE_ROW {
                let id    = sqlite3_column_int64(s, 0)
                let ts    = sqlite3_column_int64(s, 1)
                let stat  = String(cString: sqlite3_column_text(s, 2))
                let lat   = sqlite3_column_type(s, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, 3))
                let ssid  = sqlite3_column_type(s, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(s, 4))
                result.append(Segment(id: id, timestamp: ts, status: stat, latencyMs: lat, ssid: ssid))
            }

            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Clear

    func clearAll(completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self, let db = self.db, self.initialized else {
                DispatchQueue.main.async { completion() }
                return
            }
            sqlite3_exec(db, "DELETE FROM connection_log;", nil, nil, nil)
            DispatchQueue.main.async { completion() }
        }
    }
}

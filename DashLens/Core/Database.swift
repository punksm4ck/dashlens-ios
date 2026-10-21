import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Models (same shape as the Android app)

/// One logged chunk of time. state is "ONLINE" (online, no order) or "ORDER".
struct Seg {
    let startMs: Int64
    let endMs: Int64
    let state: String
    let meters: Double
}

struct DayRow {
    let key: String
    let orderM: Double
    let idleM: Double
    let orderMs: Int64
    let idleMs: Int64
}

struct Totals {
    let orderM: Double
    let idleM: Double
    let orderMs: Int64
    let idleMs: Int64
    var onlineM: Double { orderM + idleM }
    var onlineMs: Int64 { orderMs + idleMs }
}

/// Every offer DashLens analysed. outcome: PENDING, ACCEPTED, PASSED or UNKNOWN. lat/lon 0,0 = unknown.
struct OfferRow: Identifiable {
    let id: Int64
    let ts: Int64
    let pay: Double
    let miles: Double
    let minutes: Double
    let pickups: Int
    let verdict: String
    let netHr: Double
    let perMile: Double
    let outcome: String
    let lat: Double
    let lon: Double
    var merchant: String = ""
    var actualMin: Double = 0
    var actualMi: Double = 0
    var windowMin: Double = 0
    var tipsIncl: Bool = false
    var items: Int = 0
    var payPlus: Bool = false
    var hasLoc: Bool { lat != 0 || lon != 0 }
}

struct MerchantStat: Identifiable {
    let name: String
    let seen: Int
    let accepted: Int
    let done: Int
    let avgPay: Double
    let avgMin: Double
    let avgMi: Double
    var id: String { name }

    /// Realised $/hr over completed orders, using costMi per mile.
    func hourly(_ costMi: Double) -> Double {
        avgMin > 0 ? (avgPay - costMi * avgMi) / (avgMin / 60.0) : 0
    }
}

struct Earning: Identifiable {
    let id: Int64
    let ts: Int64
    let amount: Double
    let platform: String
    let kind: String
    let note: String
}

struct Expense: Identifiable {
    let id: Int64
    let ts: Int64
    let amount: Double
    let category: String
    let note: String
    let receipt: String
}

struct CatSum {
    let cat: String
    let total: Double
}

// MARK: - SQLite plumbing

struct Row {
    let st: OpaquePointer?
    func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(st, i)) }
    func i64(_ i: Int32) -> Int64 { sqlite3_column_int64(st, i) }
    func dbl(_ i: Int32) -> Double { sqlite3_column_double(st, i) }
    func str(_ i: Int32) -> String {
        if let p = sqlite3_column_text(st, i) { return String(cString: p) }
        return ""
    }
    func isNull(_ i: Int32) -> Bool { sqlite3_column_type(st, i) == SQLITE_NULL }
}

final class Database {
    static let shared = Database()

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("dashlens.db").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            // Fall back to an in-memory database so the app still opens; data would not persist.
            sqlite3_open(":memory:", &db)
        }
        createTables()
    }

    private func createTables() {
        _ = run("CREATE TABLE IF NOT EXISTS seg(id INTEGER PRIMARY KEY AUTOINCREMENT, start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, state TEXT NOT NULL, meters REAL NOT NULL)", notify: false)
        _ = run("CREATE INDEX IF NOT EXISTS seg_start ON seg(start_ms)", notify: false)
        _ = run("CREATE TABLE IF NOT EXISTS offer(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, pay REAL NOT NULL, miles REAL NOT NULL, minutes REAL NOT NULL, pickups INTEGER NOT NULL, verdict TEXT NOT NULL, net_hr REAL NOT NULL, per_mile REAL NOT NULL, outcome TEXT NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL, merchant TEXT NOT NULL DEFAULT '', actual_min REAL NOT NULL DEFAULT 0, actual_mi REAL NOT NULL DEFAULT 0, window_min REAL NOT NULL DEFAULT 0, tips_incl INTEGER NOT NULL DEFAULT 0)", notify: false)
        _ = run("CREATE INDEX IF NOT EXISTS offer_ts ON offer(ts)", notify: false)
        _ = run("CREATE INDEX IF NOT EXISTS offer_merchant ON offer(merchant)", notify: false)
        _ = run("CREATE TABLE IF NOT EXISTS earning(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, amount REAL NOT NULL, platform TEXT NOT NULL, kind TEXT NOT NULL, note TEXT NOT NULL)", notify: false)
        _ = run("CREATE INDEX IF NOT EXISTS earning_ts ON earning(ts)", notify: false)
        _ = run("CREATE TABLE IF NOT EXISTS expense(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, amount REAL NOT NULL, category TEXT NOT NULL, note TEXT NOT NULL, receipt TEXT NOT NULL)", notify: false)
        _ = run("CREATE INDEX IF NOT EXISTS expense_ts ON expense(ts)", notify: false)
        // 4.2.0: item count and "+" pay flag on each offer. Older installs get the columns added; no data is lost.
        addColumn("offer", "items", "INTEGER NOT NULL DEFAULT 0")
        addColumn("offer", "pay_plus", "INTEGER NOT NULL DEFAULT 0")
    }

    private func addColumn(_ table: String, _ column: String, _ type: String) {
        let have: [String] = query("PRAGMA table_info(\(table))") { (r: Row) -> String in r.str(1) }
        if !have.contains(column) {
            _ = run("ALTER TABLE \(table) ADD COLUMN \(column) \(type)", notify: false)
        }
    }

    private func bind(_ st: OpaquePointer?, _ args: [Any]) {
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case let v as Bool: sqlite3_bind_int(st, idx, v ? 1 : 0)
            case let v as Int64: sqlite3_bind_int64(st, idx, v)
            case let v as Int: sqlite3_bind_int64(st, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(st, idx, v)
            case let v as String: sqlite3_bind_text(st, idx, v, -1, SQLITE_TRANSIENT)
            default: sqlite3_bind_null(st, idx)
            }
        }
    }

    /// Runs a write statement. Returns the last inserted row id.
    @discardableResult
    func run(_ sql: String, _ args: [Any] = [], notify: Bool = true) -> Int64 {
        lock.lock()
        var st: OpaquePointer?
        var rowId: Int64 = 0
        if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
            bind(st, args)
            _ = sqlite3_step(st)
            rowId = sqlite3_last_insert_rowid(db)
        }
        sqlite3_finalize(st)
        lock.unlock()
        if notify {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .dashLensDataChanged, object: nil) }
        }
        return rowId
    }

    func query<T>(_ sql: String, _ args: [Any] = [], _ map: (Row) -> T) -> [T] {
        lock.lock()
        defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        bind(st, args)
        var out: [T] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(map(Row(st: st))) }
        return out
    }

    // MARK: mileage segments

    func insertSeg(_ startMs: Int64, _ endMs: Int64, _ state: String, _ meters: Double) {
        run("INSERT INTO seg(start_ms,end_ms,state,meters) VALUES(?,?,?,?)", [startMs, endMs, state, meters])
    }

    func firstStart() -> Int64? {
        let r: [Int64?] = query("SELECT MIN(start_ms) FROM seg") { (row: Row) -> Int64? in
            row.isNull(0) ? nil : row.i64(0)
        }
        if let first = r.first { return first }
        return nil
    }

    func segments(_ fromMs: Int64, _ toMs: Int64) -> [Seg] {
        query("SELECT start_ms,end_ms,state,meters FROM seg WHERE start_ms>=? AND start_ms<? ORDER BY start_ms", [fromMs, toMs]) {
            Seg(startMs: $0.i64(0), endMs: $0.i64(1), state: $0.str(2), meters: $0.dbl(3))
        }
    }

    func totals(_ fromMs: Int64, _ toMs: Int64) -> Totals {
        var om = 0.0, im = 0.0
        var oms: Int64 = 0, ims: Int64 = 0
        let rows = query("SELECT state, SUM(meters), SUM(end_ms-start_ms) FROM seg WHERE start_ms>=? AND start_ms<? GROUP BY state", [fromMs, toMs]) {
            (state: $0.str(0), meters: $0.dbl(1), ms: $0.i64(2))
        }
        for r in rows {
            if r.state == "ORDER" { om = r.meters; oms = r.ms } else { im = r.meters; ims = r.ms }
        }
        return Totals(orderM: om, idleM: im, orderMs: oms, idleMs: ims)
    }

    /// Grouped by local-time key, e.g. fmt "%Y-%m-%d" (days) or "%Y-%m" (months).
    func grouped(_ fromMs: Int64, _ toMs: Int64, _ fmt: String) -> [DayRow] {
        let sql = "SELECT strftime('\(fmt)', start_ms/1000, 'unixepoch', 'localtime') AS k, state, SUM(meters), SUM(end_ms-start_ms) FROM seg WHERE start_ms>=? AND start_ms<? GROUP BY k, state ORDER BY k"
        let rows = query(sql, [fromMs, toMs]) {
            (k: $0.str(0), state: $0.str(1), meters: $0.dbl(2), ms: $0.i64(3))
        }
        var order: [String] = []
        var acc: [String: (om: Double, im: Double, oms: Int64, ims: Int64)] = [:]
        for r in rows {
            if acc[r.k] == nil { acc[r.k] = (0, 0, 0, 0); order.append(r.k) }
            var a = acc[r.k]!
            if r.state == "ORDER" { a.om = r.meters; a.oms = r.ms } else { a.im = r.meters; a.ims = r.ms }
            acc[r.k] = a
        }
        return order.map { k in
            let a = acc[k]!
            return DayRow(key: k, orderM: a.om, idleM: a.im, orderMs: a.oms, idleMs: a.ims)
        }
    }

    // MARK: offers

    private static let offerCols = "id,ts,pay,miles,minutes,pickups,verdict,net_hr,per_mile,outcome,lat,lon,merchant,actual_min,actual_mi,window_min,tips_incl,items,pay_plus"

    private static func readOffer(_ r: Row) -> OfferRow {
        OfferRow(id: r.i64(0), ts: r.i64(1), pay: r.dbl(2), miles: r.dbl(3), minutes: r.dbl(4), pickups: r.int(5),
                 verdict: r.str(6), netHr: r.dbl(7), perMile: r.dbl(8), outcome: r.str(9), lat: r.dbl(10), lon: r.dbl(11),
                 merchant: r.str(12), actualMin: r.dbl(13), actualMi: r.dbl(14), windowMin: r.dbl(15), tipsIncl: r.int(16) == 1,
                 items: r.int(17), payPlus: r.int(18) == 1)
    }

    func insertOffer(_ o: OfferRow) -> Int64 {
        run("INSERT INTO offer(ts,pay,miles,minutes,pickups,verdict,net_hr,per_mile,outcome,lat,lon,merchant,actual_min,actual_mi,window_min,tips_incl,items,pay_plus) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [o.ts, o.pay, o.miles, o.minutes, o.pickups, o.verdict, o.netHr, o.perMile, o.outcome, o.lat, o.lon,
             o.merchant, o.actualMin, o.actualMi, o.windowMin, o.tipsIncl ? 1 : 0, o.items, o.payPlus ? 1 : 0])
    }

    func setOutcome(_ id: Int64, _ outcome: String) {
        run("UPDATE offer SET outcome=? WHERE id=?", [outcome, id])
    }

    func offers(_ fromMs: Int64, _ toMs: Int64, limit: Int = 1000) -> [OfferRow] {
        query("SELECT \(Database.offerCols) FROM offer WHERE ts>=? AND ts<? ORDER BY ts DESC LIMIT \(limit)", [fromMs, toMs], Database.readOffer)
    }

    func offer(id: Int64) -> OfferRow? {
        query("SELECT \(Database.offerCols) FROM offer WHERE id=?", [id], Database.readOffer).first
    }

    func setActual(_ id: Int64, _ minutes: Double, _ miles: Double) {
        run("UPDATE offer SET actual_min=?, actual_mi=? WHERE id=?", [minutes, miles, id])
    }

    /// Accepted offers that have no measured order time yet, oldest first.
    func unmeasuredAccepted(sinceMs: Int64) -> [OfferRow] {
        query("SELECT \(Database.offerCols) FROM offer WHERE outcome='ACCEPTED' AND actual_min=0 AND ts>=? ORDER BY ts", [sinceMs], Database.readOffer)
    }

    /// Offers still waiting for an outcome, newest first.
    func pendingOffers(sinceMs: Int64) -> [OfferRow] {
        query("SELECT \(Database.offerCols) FROM offer WHERE outcome='PENDING' AND ts>=? ORDER BY ts DESC", [sinceMs], Database.readOffer)
    }

    /// Offers still PENDING that are older than the cutoff.
    func stalePending(beforeMs: Int64) -> [OfferRow] {
        query("SELECT \(Database.offerCols) FROM offer WHERE outcome='PENDING' AND ts<? ORDER BY ts", [beforeMs], Database.readOffer)
    }

    /// (offer miles, measured order minutes) for recent completed orders, newest first.
    func calibrationSamples(_ limit: Int) -> [(Double, Double)] {
        query("SELECT miles, actual_min FROM offer WHERE outcome='ACCEPTED' AND actual_min>0 AND miles>0 ORDER BY ts DESC LIMIT \(limit)") {
            ($0.dbl(0), $0.dbl(1))
        }
    }

    func merchant(_ name: String) -> MerchantStat? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        let sql = "SELECT COUNT(*), SUM(CASE WHEN outcome='ACCEPTED' THEN 1 ELSE 0 END), SUM(CASE WHEN outcome='ACCEPTED' AND actual_min>0 THEN 1 ELSE 0 END), COALESCE(AVG(CASE WHEN outcome='ACCEPTED' THEN pay END),0), COALESCE(AVG(CASE WHEN outcome='ACCEPTED' AND actual_min>0 THEN actual_min END),0), COALESCE(AVG(CASE WHEN outcome='ACCEPTED' AND actual_min>0 THEN actual_mi END),0) FROM offer WHERE merchant=?"
        let r = query(sql, [name]) {
            MerchantStat(name: name, seen: $0.int(0), accepted: $0.int(1), done: $0.int(2), avgPay: $0.dbl(3), avgMin: $0.dbl(4), avgMi: $0.dbl(5))
        }
        if let m = r.first, m.seen > 0 { return m }
        return nil
    }

    func merchants(_ fromMs: Int64, _ toMs: Int64) -> [MerchantStat] {
        let sql = "SELECT merchant, COUNT(*), SUM(CASE WHEN outcome='ACCEPTED' THEN 1 ELSE 0 END), SUM(CASE WHEN outcome='ACCEPTED' AND actual_min>0 THEN 1 ELSE 0 END), COALESCE(AVG(CASE WHEN outcome='ACCEPTED' THEN pay END),0), COALESCE(AVG(CASE WHEN outcome='ACCEPTED' AND actual_min>0 THEN actual_min END),0), COALESCE(AVG(CASE WHEN outcome='ACCEPTED' AND actual_min>0 THEN actual_mi END),0) FROM offer WHERE merchant<>'' AND ts>=? AND ts<? GROUP BY merchant ORDER BY 3 DESC, 2 DESC"
        return query(sql, [fromMs, toMs]) {
            MerchantStat(name: $0.str(0), seen: $0.int(1), accepted: $0.int(2), done: $0.int(3), avgPay: $0.dbl(4), avgMin: $0.dbl(5), avgMi: $0.dbl(6))
        }
    }

    /// Sum of pay and count of ACCEPTED offers.
    func acceptedPay(_ fromMs: Int64, _ toMs: Int64) -> (Double, Int) {
        let r = query("SELECT COALESCE(SUM(pay),0), COUNT(*) FROM offer WHERE outcome='ACCEPTED' AND ts>=? AND ts<?", [fromMs, toMs]) {
            ($0.dbl(0), $0.int(1))
        }
        return r.first ?? (0, 0)
    }

    // MARK: earnings

    func insertEarning(_ ts: Int64, _ amount: Double, _ platform: String, _ kind: String, _ note: String) {
        run("INSERT INTO earning(ts,amount,platform,kind,note) VALUES(?,?,?,?,?)", [ts, amount, platform, kind, note])
    }

    func earnings(_ fromMs: Int64, _ toMs: Int64) -> [Earning] {
        query("SELECT id,ts,amount,platform,kind,note FROM earning WHERE ts>=? AND ts<? ORDER BY ts DESC", [fromMs, toMs]) {
            Earning(id: $0.i64(0), ts: $0.i64(1), amount: $0.dbl(2), platform: $0.str(3), kind: $0.str(4), note: $0.str(5))
        }
    }

    func deleteEarning(_ id: Int64) { run("DELETE FROM earning WHERE id=?", [id]) }

    func sumEarnings(_ fromMs: Int64, _ toMs: Int64) -> Double {
        query("SELECT COALESCE(SUM(amount),0) FROM earning WHERE ts>=? AND ts<?", [fromMs, toMs]) { $0.dbl(0) }.first ?? 0
    }

    // MARK: expenses

    func insertExpense(_ ts: Int64, _ amount: Double, _ category: String, _ note: String, _ receipt: String) {
        run("INSERT INTO expense(ts,amount,category,note,receipt) VALUES(?,?,?,?,?)", [ts, amount, category, note, receipt])
    }

    func expenses(_ fromMs: Int64, _ toMs: Int64) -> [Expense] {
        query("SELECT id,ts,amount,category,note,receipt FROM expense WHERE ts>=? AND ts<? ORDER BY ts DESC", [fromMs, toMs]) {
            Expense(id: $0.i64(0), ts: $0.i64(1), amount: $0.dbl(2), category: $0.str(3), note: $0.str(4), receipt: $0.str(5))
        }
    }

    func deleteExpense(_ id: Int64) { run("DELETE FROM expense WHERE id=?", [id]) }

    func expenseByCat(_ fromMs: Int64, _ toMs: Int64) -> [CatSum] {
        query("SELECT category, SUM(amount) FROM expense WHERE ts>=? AND ts<? GROUP BY category ORDER BY category", [fromMs, toMs]) {
            CatSum(cat: $0.str(0), total: $0.dbl(1))
        }
    }
}

func nowMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) }

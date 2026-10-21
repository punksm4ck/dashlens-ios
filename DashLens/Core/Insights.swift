import Foundation

struct SlotStat {
    let key: Int
    let minutes: Double
    let pay: Double
    var perHr: Double { minutes > 0 ? pay / (minutes / 60.0) : 0 }
}

struct Hot: Identifiable {
    let lat: Double
    let lon: Double
    let count: Int
    let avgPay: Double
    var id: String { "\(lat),\(lon)" }
}

struct OfferStats {
    let total: Int
    let accepted: Int
    let passed: Int
    let avgPay: Double
    let avgPerMile: Double
    let avgNetHr: Double
    let passedGood: Int
    let acceptedBad: Int
}

/// Personal analytics from your own logs. Nothing leaves the phone.
enum Insights {
    static let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func offerStats(_ rows: [OfferRow]) -> OfferStats {
        let acc = rows.filter { $0.outcome == "ACCEPTED" }
        let passed = rows.filter { $0.outcome == "PASSED" }.count
        func avg(_ l: [Double]) -> Double { l.isEmpty ? 0 : l.reduce(0, +) / Double(l.count) }
        return OfferStats(
            total: rows.count, accepted: acc.count, passed: passed,
            avgPay: avg(acc.map { $0.pay }), avgPerMile: avg(acc.map { $0.perMile }), avgNetHr: avg(acc.map { $0.netHr }),
            passedGood: rows.filter { $0.outcome == "PASSED" && $0.verdict == "TAKE" }.count,
            acceptedBad: acc.filter { $0.verdict == "DECLINE" }.count)
    }

    /// Online minutes and estimated income per (weekday * 24 + hour) slot over the last `days` days.
    static func slots(_ days: Int) -> [Int: SlotStat] {
        let now = nowMs()
        let from = now - Int64(days) * 86_400_000
        let db = Database.shared
        let cal = LDate.cal
        var mins = [Double](repeating: 0, count: 7 * 24)
        var pay = [Double](repeating: 0, count: 7 * 24)

        func slotOf(_ d: Date) -> Int {
            let w = cal.component(.weekday, from: d)      // Sunday = 1
            let h = cal.component(.hour, from: d)
            return ((w + 5) % 7) * 24 + h
        }

        for s in db.segments(from, now) {
            var cur = s.startMs
            while cur < s.endMs {
                let d = Date(timeIntervalSince1970: Double(cur) / 1000.0)
                let nextHourDate = cal.dateInterval(of: .hour, for: d)?.end ?? d.addingTimeInterval(3600)
                let nextHour = Int64(nextHourDate.timeIntervalSince1970 * 1000.0)
                let end = min(s.endMs, max(nextHour, cur + 1))
                mins[slotOf(d)] += Double(end - cur) / 60_000.0
                cur = end
            }
        }
        if !Prefs.bool("income_manual_only", false) {
            for o in db.offers(from, now) where o.outcome == "ACCEPTED" {
                pay[slotOf(Date(timeIntervalSince1970: Double(o.ts) / 1000.0))] += o.pay
            }
        }
        for e in db.earnings(from, now) {
            pay[slotOf(Date(timeIntervalSince1970: Double(e.ts) / 1000.0))] += e.amount
        }
        var out: [Int: SlotStat] = [:]
        for i in 0..<(7 * 24) where mins[i] > 0 { out[i] = SlotStat(key: i, minutes: mins[i], pay: pay[i]) }
        return out
    }

    static func topSlots(_ s: [Int: SlotStat], minMinutes: Double, n: Int) -> [SlotStat] {
        Array(s.values.filter { $0.minutes >= minMinutes }.sorted { $0.perHr > $1.perHr }.prefix(n))
    }

    static func byWeekday(_ s: [Int: SlotStat]) -> [SlotStat] {
        (0..<7).map { d in
            let l = s.values.filter { $0.key / 24 == d }
            return SlotStat(key: d, minutes: l.reduce(0) { $0 + $1.minutes }, pay: l.reduce(0) { $0 + $1.pay })
        }
    }

    static func slotLabel(_ key: Int) -> String {
        let h = key % 24
        let h2 = (h + 1) % 24
        return days[key / 24] + String(format: " %02d:00-%02d:00", h, h2)
    }

    /// Where you accepted offers, in ~1 km cells (0.01 degrees), busiest first.
    static func hotspots(_ rows: [OfferRow], _ n: Int) -> [Hot] {
        var m: [String: [OfferRow]] = [:]
        for o in rows where o.outcome == "ACCEPTED" && o.hasLoc {
            let k = "\(Int((o.lat * 100.0).rounded())),\(Int((o.lon * 100.0).rounded()))"
            m[k, default: []].append(o)
        }
        let hots = m.values.map { l -> Hot in
            let c = Double(l.count)
            return Hot(lat: l.reduce(0) { $0 + $1.lat } / c, lon: l.reduce(0) { $0 + $1.lon } / c,
                       count: l.count, avgPay: l.reduce(0) { $0 + $1.pay } / c)
        }
        let sorted = hots.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.avgPay > b.avgPay
        }
        return Array(sorted.prefix(n))
    }
}

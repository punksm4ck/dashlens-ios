import Foundation

enum Period: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
}

struct Report {
    let period: Period
    let from: LDate
    let toExcl: LDate
    let title: String
    let totals: Totals
    let rows: [DayRow]
}

enum Reports {
    static func mi(_ meters: Double) -> String { Fmt.f("%.1f", meters / 1609.344) }
    static func hrs(_ ms: Int64) -> String { Fmt.f("%.2f", Double(ms) / 3_600_000.0) }
    static func dur(_ ms: Int64) -> String {
        let m = Int(ms / 60_000)
        return "\(m / 60)h " + String(format: "%02d", m % 60) + "m"
    }

    static func shift(_ p: Period, _ anchor: LDate, _ n: Int) -> LDate {
        switch p {
        case .week: return anchor.plusWeeks(n)
        case .month: return anchor.plusMonths(n)
        case .year: return anchor.plusYears(n)
        }
    }

    static func build(_ p: Period, _ anchor: LDate) -> Report {
        let from: LDate
        let to: LDate
        switch p {
        case .week: from = anchor.weekStart(); to = from.plusWeeks(1)
        case .month: from = anchor.firstOfMonth(); to = from.plusMonths(1)
        case .year: from = anchor.firstOfYear(); to = from.plusYears(1)
        }
        let last = to.plusDays(-1)
        let title: String
        switch p {
        case .week: title = "Week \(from.format("MMM d")) - \(last.format("MMM d")), \(last.year)"
        case .month: title = from.format("MMMM yyyy")
        case .year: title = "Year \(from.year)"
        }
        let db = Database.shared
        let f = from.startMs
        let t = to.startMs
        let foundRows = db.grouped(f, t, p == .year ? "%Y-%m" : "%Y-%m-%d")
        var found: [String: DayRow] = [:]
        for r in foundRows { found[r.key] = r }

        var keys: [String] = []
        switch p {
        case .week: for i in 0..<7 { keys.append(from.plusDays(i).description) }
        case .year: for m in 1...12 { keys.append("\(from.year)-" + String(format: "%02d", m)) }
        case .month: keys = found.keys.sorted()
        }
        let rows = keys.map { found[$0] ?? DayRow(key: $0, orderM: 0, idleM: 0, orderMs: 0, idleMs: 0) }
        return Report(period: p, from: from, toExcl: to, title: title, totals: db.totals(f, t), rows: rows)
    }

    private static func money(_ v: Double) -> String { Fmt.money(v) }

    static func text(_ r: Report) -> String {
        let t = r.totals
        let rate = Prefs.num("irs_rate")
        var sb = "DashLens - \(r.title)\n\n"
        sb += "On order:          \(mi(t.orderM)) mi   \(dur(t.orderMs))\n"
        sb += "Online, no order:  \(mi(t.idleM)) mi   \(dur(t.idleMs))\n"
        sb += "Online total:      \(mi(t.onlineM)) mi   \(dur(t.onlineMs))  (includes on-order)\n\n"
        sb += "Estimated deduction at \(Fmt.f("%.3f", rate)) per mile:\n"
        sb += "  on-order miles only:  \(money(t.orderM / 1609.344 * rate))\n"
        sb += "  all online miles:     \(money(t.onlineM / 1609.344 * rate))\n"
        sb += "(Estimate only. Confirm which miles you can claim with a tax professional.)\n\n"
        sb += Finance.section(r.from, r.toExcl) + "\n"
        sb += "By \(r.period == .year ? "month" : "day") (on-order mi / h, online total mi / h):\n"
        let prefix = "\(r.from.year)-"
        for d in r.rows {
            let key = d.key.hasPrefix(prefix) ? String(d.key.dropFirst(prefix.count)) : d.key
            sb += key.padR(8) + " " + mi(d.orderM).padL(7) + " " + hrs(d.orderMs).padL(7) + " "
                + mi(d.orderM + d.idleM).padL(7) + " " + hrs(d.orderMs + d.idleMs).padL(7) + "\n"
        }
        return sb
    }

    private static func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    static func csv(_ r: Report) -> String {
        var sb = "Report,\(q(r.title))\n"
        sb += "Period,OnOrder_Miles,OnOrder_Hours,OnlineNoOrder_Miles,OnlineNoOrder_Hours,OnlineTotal_Miles,OnlineTotal_Hours\n"
        for d in r.rows {
            sb += "\(d.key),\(mi(d.orderM)),\(hrs(d.orderMs)),\(mi(d.idleM)),\(hrs(d.idleMs)),\(mi(d.orderM + d.idleM)),\(hrs(d.orderMs + d.idleMs))\n"
        }
        let t = r.totals
        sb += "TOTAL,\(mi(t.orderM)),\(hrs(t.orderMs)),\(mi(t.idleM)),\(hrs(t.idleMs)),\(mi(t.onlineM)),\(hrs(t.onlineMs))\n"
        return sb
    }

    /// Continuous runs (one row per stretch in the same state), the form you want for a mileage log.
    static func tripLog(_ r: Report) -> String {
        let segs = Database.shared.segments(r.from.startMs, r.toExcl.startMs)
        var runs: [Seg] = []
        for s in segs {
            if let l = runs.last, l.state == s.state, s.startMs - l.endMs <= 2000 {
                runs[runs.count - 1] = Seg(startMs: l.startMs, endMs: s.endMs, state: l.state, meters: l.meters + s.meters)
            } else {
                runs.append(s)
            }
        }
        var sb = "Date,Start,End,Type,Miles,Minutes\n"
        for s in runs {
            let type = s.state == "ORDER" ? "On order" : "Online (no order)"
            let mins = Fmt.f("%.0f", Double(s.endMs - s.startMs) / 60_000.0)
            sb += "\(Fmt.ms(s.startMs, "yyyy-MM-dd")),\(Fmt.ms(s.startMs, "HH:mm")),\(Fmt.ms(s.endMs, "HH:mm")),\(type),\(mi(s.meters)),\(mins)\n"
        }
        return sb
    }

    static func offersCsv(_ r: Report) -> String {
        let rows = Array(Database.shared.offers(r.from.startMs, r.toExcl.startMs).reversed())
        var sb = "DateTime,Verdict,Outcome,Pay,Miles,Minutes,Pickups,NetPerHour,PerRealMile,Lat,Lon\n"
        for o in rows {
            let nums = Fmt.f("%.2f,%.1f,%.0f", o.pay, o.miles, o.minutes) + ",\(o.pickups)," + Fmt.f("%.2f,%.2f", o.netHr, o.perMile)
            let loc = o.hasLoc ? Fmt.f("%.5f,%.5f", o.lat, o.lon) : ","
            sb += "\(Fmt.ms(o.ts, "yyyy-MM-dd HH:mm")),\(o.verdict),\(o.outcome),\(nums),\(loc)\n"
        }
        return sb
    }

    /// Earnings and expenses in one file: Type,Date,Amount,Category,Platform,Note,Receipt.
    static func ledgerCsv(_ r: Report) -> String {
        let db = Database.shared
        let f = r.from.startMs
        let t = r.toExcl.startMs
        var sb = "Type,Date,Amount,Category,Platform,Note,Receipt\n"
        for e in db.earnings(f, t).reversed() {
            sb += "Earning,\(Fmt.ms(e.ts, "yyyy-MM-dd")),\(Fmt.f("%.2f", e.amount)),\(q(e.kind)),\(q(e.platform)),\(q(e.note)),\n"
        }
        for e in db.expenses(f, t).reversed() {
            sb += "Expense,\(Fmt.ms(e.ts, "yyyy-MM-dd")),\(Fmt.f("%.2f", e.amount)),\(q(e.category)),,\(q(e.note)),\(q(e.receipt))\n"
        }
        return sb
    }
}

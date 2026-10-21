import Foundation

struct Pnl {
    let offerIncome: Double
    let offerCount: Int
    let manualIncome: Double
    let income: Double
    let expenses: [CatSum]
    let expenseTotal: Double
    let miles: Double
    let mileageDeduction: Double
    let expenseDeduction: Double
    let deductions: Double
    let net: Double
    let actualMethod: Bool
    let bizPct: Double
}

struct Due {
    let label: String
    let date: LDate
    let from: LDate
    let toExcl: LDate
}

struct Today {
    let income: Double
    let accepted: Int
    let onlineMs: Int64
    let miles: Double
    var perHour: Double { onlineMs > 0 ? income / (Double(onlineMs) / 3_600_000.0) : 0 }
}

/// Profit, deduction and tax-set-aside estimates. Everything here is an estimate, not tax advice.
enum Finance {
    static let cats = ["Gas", "Tolls", "Parking", "Car wash", "Maintenance", "Insurance", "Phone", "Supplies", "Other"]
    static let kinds = ["Dash payout", "Tips / cash", "Bonus / promo", "Other income"]

    /// Costs the standard mileage rate already covers (so they are not deducted again under that method).
    private static let vehicle: Set<String> = ["Gas", "Car wash", "Maintenance", "Insurance"]
    /// Variable cost used for the "actual cost per mile" offer analysis.
    private static let variable: Set<String> = ["Gas", "Maintenance"]

    static func money(_ v: Double) -> String { Fmt.money(v) }

    private static func manualOnly() -> Bool { Prefs.bool("income_manual_only", false) }

    static func bizPct(_ year: Int) -> Double {
        let s = Double(Prefs.str("odo_start_\(year)"))
        let e = Double(Prefs.str("odo_end_\(year)"))
        if let s = s, let e = e, e > s {
            let t = Database.shared.totals(LDate(year, 1, 1).startMs, LDate(year + 1, 1, 1).startMs)
            let tracked = (Prefs.bool("basis_online", false) ? t.onlineM : t.orderM) / 1609.344
            return min(max(tracked / (e - s) * 100.0, 0), 100)
        }
        return min(max(Prefs.num("biz_pct"), 0), 100)
    }

    static func pnl(_ from: LDate, _ toExcl: LDate) -> Pnl {
        let db = Database.shared
        let f = from.startMs
        let t = toExcl.startMs
        let acc = db.acceptedPay(f, t)
        let manual = db.sumEarnings(f, t)
        let income = manualOnly() ? manual : acc.0 + manual
        let tot = db.totals(f, t)
        let miles = (Prefs.bool("basis_online", false) ? tot.onlineM : tot.orderM) / 1609.344
        let exp = db.expenseByCat(f, t)
        let expTotal = exp.reduce(0) { $0 + $1.total }
        let actual = Prefs.bool("method_actual", false)
        let pct = bizPct(from.year)
        let vehicleExp = exp.filter { vehicle.contains($0.cat) }.reduce(0) { $0 + $1.total }
        let otherExp = expTotal - vehicleExp
        let mileDed = actual ? 0 : miles * Prefs.num("irs_rate")
        let expDed = otherExp + (actual ? vehicleExp * pct / 100.0 : 0)
        let ded = mileDed + expDed
        return Pnl(offerIncome: acc.0, offerCount: acc.1, manualIncome: manual, income: income, expenses: exp,
                   expenseTotal: expTotal, miles: miles, mileageDeduction: mileDed, expenseDeduction: expDed,
                   deductions: ded, net: income - ded, actualMethod: actual, bizPct: pct)
    }

    /// Self-employment tax: 15.3% on 92.35% of net profit, only when net is at least $400.
    static func seTax(_ net: Double) -> Double { net < 400 ? 0 : net * 0.9235 * 0.153 }

    static func setAside(_ net: Double) -> Double {
        if net <= 0 { return 0 }
        let se = seTax(net)
        return se + max(net - se / 2.0, 0) * Prefs.num("tax_rate") / 100.0
    }

    // MARK: quarterly estimated-tax dates

    private static func adj(_ d: LDate) -> LDate {
        if d.isSaturday { return d.plusDays(2) }
        if d.isSunday { return d.plusDays(1) }
        return d
    }

    static func dues(_ year: Int) -> [Due] {
        [
            Due(label: "Q1", date: adj(LDate(year, 4, 15)), from: LDate(year, 1, 1), toExcl: LDate(year, 4, 1)),
            Due(label: "Q2", date: adj(LDate(year, 6, 15)), from: LDate(year, 4, 1), toExcl: LDate(year, 6, 1)),
            Due(label: "Q3", date: adj(LDate(year, 9, 15)), from: LDate(year, 6, 1), toExcl: LDate(year, 9, 1)),
            Due(label: "Q4", date: adj(LDate(year + 1, 1, 15)), from: LDate(year, 9, 1), toExcl: LDate(year + 1, 1, 1)),
        ]
    }

    static func nextDue(_ today: LDate) -> Due? {
        for y in [today.year - 1, today.year, today.year + 1] {
            for d in dues(y) where !(d.date < today) { return d }
        }
        return nil
    }

    /// One line when an estimated payment is due within 21 days, otherwise empty.
    static func taxHint() -> String {
        let today = LDate.today()
        guard let d = nextDue(today) else { return "" }
        let days = today.daysUntil(d.date)
        if days > 21 { return "" }
        let p = pnl(d.from, d.toExcl)
        return "Estimated tax payment for \(d.label) is due \(d.date.format("MMM d, yyyy")) (\(days) days). Rough set-aside for that period: \(money(setAside(p.net)))."
    }

    static func quartersText(_ year: Int) -> String {
        var sb = ""
        for d in dues(year) {
            let p = pnl(d.from, d.toExcl)
            sb += "\(d.label)  due \(d.date.format("MMM d, yyyy").padR(13))  net \(money(p.net).padL(10))  set-aside \(money(setAside(p.net)).padL(9))\n"
        }
        return sb
    }

    // MARK: text block used by reports

    static func section(_ from: LDate, _ toExcl: LDate) -> String {
        let p = pnl(from, toExcl)
        var sb = "Money (estimates)\n"
        sb += "  Income:            \(money(p.income))"
        if manualOnly() {
            sb += "  (logged by hand only)\n"
        } else {
            sb += "  (\(money(p.offerIncome)) from \(p.offerCount) accepted offers + \(money(p.manualIncome)) logged)\n"
        }
        if p.actualMethod {
            sb += "  Vehicle + other expenses: \(money(p.expenseDeduction))  (actual method, \(Fmt.f("%.0f", p.bizPct))% business use)\n"
        } else {
            sb += "  Mileage deduction: \(money(p.mileageDeduction))  (\(Fmt.f("%.1f", p.miles)) mi at \(Prefs.fmt(Prefs.num("irs_rate"))))\n"
            sb += "  Other expenses:    \(money(p.expenseDeduction))  (tolls, parking, phone, supplies...)\n"
        }
        sb += "  Net profit:        \(money(p.net))\n"
        sb += "  Tax set-aside:     \(money(setAside(p.net)))  (self-employment tax + your income-tax %, rough)\n"
        if !p.expenses.isEmpty {
            sb += "  Logged expenses by category:\n"
            for e in p.expenses { sb += "    \(e.cat.padR(12)) \(money(e.total))\n" }
        }
        let hint = taxHint()
        if !hint.isEmpty { sb += "  \(hint)\n" }
        sb += "(Estimates only. Not tax advice. Confirm with a tax professional.)\n"
        return sb
    }

    // MARK: live numbers

    static func today() -> Today {
        let db = Database.shared
        let d = LDate.today()
        let s = d.startMs
        let e = d.plusDays(1).startMs
        let acc = db.acceptedPay(s, e)
        let income = manualOnly() ? db.sumEarnings(s, e) : acc.0 + db.sumEarnings(s, e)
        let t = db.totals(s, e)
        return Today(income: income, accepted: acc.1, onlineMs: t.onlineMs, miles: t.onlineM / 1609.344)
    }

    static func incomeBetween(_ from: LDate, _ toExcl: LDate) -> Double {
        let db = Database.shared
        let f = from.startMs
        let t = toExcl.startMs
        return manualOnly() ? db.sumEarnings(f, t) : db.acceptedPay(f, t).0 + db.sumEarnings(f, t)
    }

    static func goalLine(_ t: Today) -> String {
        let g = Prefs.num("goal_day")
        if g <= 0 { return "" }
        return "Goal: \(money(t.income)) of \(money(g)) (\(Fmt.f("%.0f", t.income / g * 100.0))%)"
    }

    /// Gas + maintenance dollars per tracked mile over the last 90 days, or nil when there is too little data.
    static func actualCostPerMile() -> Double? {
        let now = nowMs()
        let from = now - 90 * 86_400_000
        let db = Database.shared
        let miles = db.totals(from, now).onlineM / 1609.344
        let cost = db.expenseByCat(from, now).filter { variable.contains($0.cat) }.reduce(0) { $0 + $1.total }
        return (miles >= 100 && cost >= 20) ? cost / miles : nil
    }
}

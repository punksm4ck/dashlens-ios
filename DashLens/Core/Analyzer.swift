import Foundation

enum Verdict: String {
    case take = "TAKE"
    case maybe = "MAYBE"
    case decline = "DECLINE"

    var title: String {
        switch self {
        case .take: return "✓  TAKE"
        case .maybe: return "~  MAYBE"
        case .decline: return "✕  DECLINE"
        }
    }

    var spoken: String {
        switch self {
        case .take: return "Take"
        case .maybe: return "Maybe"
        case .decline: return "Decline"
        }
    }
}

struct Analysis {
    let netHr: Double
    let netPay: Double
    let realMiles: Double
    let emptyMiles: Double
    let tripMin: Double          // minutes on the order itself (drive + wait + handoff)
    let totalMin: Double         // plus the empty drive back
    let waitMin: Double
    let perMile: Double          // $ per real mile
    let perOfferMile: Double     // $ per mile as listed
    let verdict: Verdict
    let source: String           // where the time estimate came from
    let merchantLine: String     // history at this merchant, or empty
    let reasons: [String]
}

/// Learns minutes-per-mile from orders you actually completed (GPS stretch linked to the accepted offer).
enum Calibration {
    struct Cal {
        let minPerMi: Double
        let n: Int
        var mph: Double { 60.0 / minPerMi }
    }

    private static var cached: Cal?
    private static var cachedAt: Double = 0
    private static let lock = NSLock()

    static func get() -> Cal? {
        if !Prefs.bool("auto_calibrate", true) { return nil }
        lock.lock()
        defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        if now - cachedAt < 60 { return cached }
        cachedAt = now
        let s = Database.shared.calibrationSamples(40)
        if s.count < 5 {
            cached = nil
        } else {
            let fixed = Prefs.num("wait_min") + Prefs.num("dropoff_min")
            let r = s.map { max($0.1 - fixed, 0.5) / $0.0 }.sorted()
            let med = r[r.count / 2]
            cached = Cal(minPerMi: Swift.min(Swift.max(med, 1.0), 6.0), n: s.count)
        }
        return cached
    }

    static func reset() {
        lock.lock()
        cachedAt = 0
        lock.unlock()
    }
}

enum Analyzer {
    static func analyze(_ o: Offer) -> Analysis {
        func p(_ k: String) -> Double { Prefs.num(k) }

        let actual: Double? = Prefs.bool("use_actual_cost", false) ? Finance.actualCostPerMile() : nil
        let costMi = actual ?? p("cost_mi")

        let empty = o.miles * p("empty_pct") / 100.0
        let real = o.miles + empty
        let backMin = p("speed_mph") > 0 ? empty / p("speed_mph") * 60.0 : 0
        let extra = p("extra_pickup_min") * Double(o.pickups - 1)
        let wait = p("wait_min") * Double(o.pickups)

        // how long will the order take?
        let cal = Calibration.get()
        let driveMin: Double
        var source: String
        if o.shownMinutes > 0 {
            driveMin = o.shownMinutes
            source = "time shown by Dasher"
        } else if let c = cal {
            driveMin = o.miles * c.minPerMi
            source = "your real pace (\(c.n) orders)"
        } else {
            driveMin = o.miles / max(p("offer_speed_mph"), 5.0) * 60.0
            source = "estimated at \(Prefs.fmt(p("offer_speed_mph"))) mph"
        }
        var orderMin = driveMin + wait + extra + p("dropoff_min")

        // merchant history overrides the model once you have two completed orders there
        var merchantLine = ""
        let m: MerchantStat? = Prefs.bool("auto_calibrate", true) ? Database.shared.merchant(o.merchant) : nil
        if let m = m {
            if m.done >= 2 && m.avgMin > 0 {
                let ratio = m.avgMi > 0 ? min(max(o.miles / m.avgMi, 0.7), 1.5) : 1.0
                orderMin = m.avgMin * ratio + extra
                source = "your history at \(o.merchant)"
                merchantLine = "\(o.merchant): \(m.done) completed orders, avg \(Fmt.f("%.0f", m.avgMin)) min, about \(Fmt.f("$%.0f", m.hourly(costMi)))/hr realised"
            } else if m.seen > 1 {
                merchantLine = "\(o.merchant): seen \(m.seen) times, accepted \(m.accepted)"
            }
        }
        let total = orderMin + backMin

        let netPay = o.pay - costMi * real
        let netHr = netPay / (total / 60.0)
        let perMile = o.pay / real
        let perOfferMile = o.pay / o.miles

        let okHr = netHr >= p("min_hr")
        let okMi = perMile >= p("min_mi")
        let near = netHr >= p("min_hr") * 0.85 && perMile >= p("min_mi") * 0.85

        var hard: [String] = []
        if p("min_pay") > 0 && o.pay < p("min_pay") {
            hard.append(Fmt.f("Pay $%.2f is under your $%.2f minimum offer pay.", o.pay, p("min_pay")))
        }
        if p("max_mi") > 0 && o.miles > p("max_mi") {
            hard.append(Fmt.f("%.1f mi is over your %.1f mi maximum.", o.miles, p("max_mi")))
        }
        if p("max_stops") > 0 && o.pickups > Int(p("max_stops")) {
            hard.append("\(o.pickups) pickups is over your maximum of \(Int(p("max_stops"))).")
        }

        let verdict: Verdict
        if !hard.isEmpty { verdict = .decline }
        else if okHr && okMi { verdict = .take }
        else if near { verdict = .maybe }
        else { verdict = .decline }

        var reasons: [String] = hard
        reasons.append(Fmt.f("About $%.0f/hr once the whole cycle is counted — %@ your $%.0f minimum.", netHr, okHr ? "above" : "under", p("min_hr")))
        reasons.append(Fmt.f("$%.2f per real mile (%.1f incl. ~%.1f empty) — %@ your $%.2f minimum.", perMile, real, empty, okMi ? "above" : "under", p("min_mi")))
        reasons.append(Fmt.f("Order time ~%.0f min, based on %@.", orderMin, source))
        if o.windowMin > 0 && orderMin > o.windowMin * 1.25 {
            reasons.append(Fmt.f("Deliver-by window is only %.0f min; your estimate is longer.", o.windowMin))
        }
        if let a = actual {
            reasons.append(Fmt.f("Using your actual gas + maintenance cost: $%.2f per mile.", a))
        }
        if !o.tipsIncluded {
            reasons.append("Dasher did not say tips are included: pay may be higher.")
        }

        return Analysis(netHr: netHr, netPay: netPay, realMiles: real, emptyMiles: empty, tripMin: orderMin, totalMin: total,
                        waitMin: wait, perMile: perMile, perOfferMile: perOfferMile, verdict: verdict, source: source,
                        merchantLine: merchantLine, reasons: reasons)
    }
}

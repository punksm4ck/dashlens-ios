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
    var hard: [String] = []              // hard-filter failures (they force DECLINE)
    var netPerOfferMile: Double = 0      // net pay / miles as listed
    var vehicleCost: Double = 0          // gas + wear (or flat cost) over the counted miles
    var mathLines: [String] = []         // gas / wear / net pay / time / miles counted, line by line
    var assumed: String = ""             // the assumptions the grade was based on
    var floorLine: String = ""           // "against your $18/hr floor, after vehicle costs"
    var payPlus: Bool = false            // graded at a "+" minimum pay
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
    /// Vehicle cost per mile in force right now: your logged actual cost, gas + wear, or the flat rate.
    static func costPerMile() -> Double {
        let actual: Double? = Prefs.bool("use_actual_cost", false) ? Finance.actualCostPerMile() : nil
        return costPerMile(p: { Prefs.num($0) }, flag: { Prefs.bool($0, $1) }, actual: actual)
    }

    static func costPerMile(p: (String) -> Double, flag: (String, Bool) -> Bool, actual: Double?) -> Double {
        if let a = actual { return a }
        if !flag("itemize_cost", true) { return p("cost_mi") }
        let mpg = p("mpg")
        let gas = mpg > 0 ? p("gas_price") / mpg : 0
        return gas + p("wear_mi")
    }

    static func analyze(_ o: Offer) -> Analysis {
        let actual: Double? = Prefs.bool("use_actual_cost", false) ? Finance.actualCostPerMile() : nil
        let cal = Calibration.get()
        let m: MerchantStat? = Prefs.bool("auto_calibrate", true) ? Database.shared.merchant(o.merchant) : nil
        return grade(o, p: { Prefs.num($0) }, flag: { Prefs.bool($0, $1) }, actual: actual, cal: cal, m: m)
    }

    /// The whole grading model, the same as Android 4.2.0. Pure (no Prefs or database calls) so it can be tested alone.
    static func grade(_ o: Offer, p: (String) -> Double, flag: (String, Bool) -> Bool,
                      actual: Double?, cal: Calibration.Cal?, m: MerchantStat?) -> Analysis {
        let itemize = actual == nil && flag("itemize_cost", true)
        let mpg = p("mpg")
        let gasPerMi = mpg > 0 ? p("gas_price") / mpg : 0
        let costMi = costPerMile(p: p, flag: flag, actual: actual)
        let minHr = p("min_hr")
        let minMi = p("min_mi")

        let empty = o.miles * p("empty_pct") / 100.0
        let real = o.miles + empty
        let speed = p("speed_mph")
        let backMin = speed > 0 ? empty / speed * 60.0 : 0
        let pickupsD = Double(o.pickups)
        let extra = p("extra_pickup_min") * (pickupsD - 1)

        // shop & deliver: shopping plus checkout replaces the wait at the first store
        let waitEach = p("wait_min")
        let shop: Double = o.items > 0 ? Double(o.items) * p("shop_min_item") + p("checkout_min") * pickupsD : 0
        let wait: Double = o.items > 0 ? shop + waitEach * (pickupsD - 1) : waitEach * pickupsD

        // how long will the order take?
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
        var usedHistory = false
        if let m = m {
            if m.done >= 2 && m.avgMin > 0 {
                let ratio = m.avgMi > 0 ? min(max(o.miles / m.avgMi, 0.7), 1.5) : 1.0
                orderMin = m.avgMin * ratio + extra
                source = "your history at \(o.merchant)"
                usedHistory = true
                merchantLine = cat(o.merchant, ": \(m.done) completed orders, avg ", Fmt.f("%.0f", m.avgMin),
                                   " min, about ", Fmt.f("$%.0f", m.hourly(costMi)), "/hr realised")
            } else if m.seen > 1 {
                merchantLine = "\(o.merchant): seen \(m.seen) times, accepted \(m.accepted)"
            }
        }
        let total = orderMin + backMin

        let gasCost: Double = itemize ? gasPerMi * real : 0
        let wearCost: Double = itemize ? p("wear_mi") * real : 0
        let vehicleCost = costMi * real
        let netPay = o.pay - vehicleCost
        let netHr = netPay / (total / 60.0)
        let perMile = o.pay / real
        let perOfferMile = o.pay / o.miles
        let netPerOfferMile = netPay / o.miles

        let okHr = netHr >= minHr
        let okMi = perMile >= minMi
        let near = netHr >= minHr * 0.85 && perMile >= minMi * 0.85

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
        reasons.append(Fmt.f("About $%.0f/hr once the whole cycle is counted — %@ your $%.0f minimum.", netHr, okHr ? "above" : "under", minHr))
        reasons.append(Fmt.f("$%.2f per real mile (%.1f incl. ~%.1f empty) — %@ your $%.2f minimum.", perMile, real, empty, okMi ? "above" : "under", minMi))
        reasons.append(Fmt.f("Order time ~%.0f min, based on %@.", orderMin, source))
        if o.windowMin > 0 && orderMin > o.windowMin * 1.25 {
            reasons.append(Fmt.f("Deliver-by window is only %.0f min; your estimate is longer.", o.windowMin))
        }
        if let a = actual {
            reasons.append(Fmt.f("Using your actual gas + maintenance cost: $%.2f per mile.", a))
        }
        if o.payPlus {
            reasons.append("Pay is shown with a +: graded at that minimum, so the real pay may be higher.")
        } else if !o.tipsIncluded {
            reasons.append("Dasher did not say tips are included: pay may be higher.")
        }

        // the line-by-line math (what the offer card and the share card print)
        var math: [String] = []
        if itemize {
            math.append(Fmt.f("Gas: %.2f mi ÷ %@ mpg × $%.2f/gal = -$%.2f", real, Prefs.fmt(mpg), p("gas_price"), gasCost))
            math.append(Fmt.f("Wear & tear: %.2f mi × $%.2f/mi = -$%.2f", real, p("wear_mi"), wearCost))
            math.append(Fmt.f("Net pay = $%.2f pay - $%.2f gas - $%.2f wear = $%.2f", o.pay, gasCost, wearCost, netPay))
        } else {
            let tag = actual != nil ? " (your actual gas + maintenance)" : ""
            math.append(cat(Fmt.f("Vehicle: %.2f mi × $%.2f/mi = -$%.2f", real, costMi, vehicleCost), tag))
            math.append(Fmt.f("Net pay = $%.2f pay - $%.2f vehicle = $%.2f", o.pay, vehicleCost, netPay))
        }
        if usedHistory {
            math.append(Fmt.f("Time: ~%.0f min from your history at %@ + %.0f min driving back = %.0f min", orderMin, o.merchant, backMin, total))
        } else {
            var parts: [String] = []
            let driveTot = driveMin + backMin
            let perMi: Double = real > 0 ? driveTot / real : 0
            parts.append(Fmt.f("%.0f driving (%.2f mi × %.1f min/mi)", driveTot, real, perMi))
            if o.items > 0 {
                parts.append(cat(Fmt.f("%.0f shopping (", shop), "\(o.items) items × ", Prefs.fmt(p("shop_min_item")),
                                 " + \(o.pickups) checkout × ", Prefs.fmt(p("checkout_min")), ")"))
                if o.pickups > 1 {
                    parts.append(Fmt.f("%.0f waiting at the other stops", waitEach * (pickupsD - 1)))
                }
            } else if wait > 0 {
                parts.append(Fmt.f("%.0f waiting at the store", wait))
            }
            if extra > 0 {
                parts.append(Fmt.f("%.0f for the extra pickups", extra))
            }
            parts.append(cat(Prefs.fmt(p("dropoff_min")), " for 1 drop-off"))
            math.append(cat("Time: ", parts.joined(separator: " + "), Fmt.f(" = %.0f min", total)))
        }
        math.append(Fmt.f("Miles counted: %.1f + %.2f back = %.2f mi", o.miles, empty, real))

        var ass: [String] = []
        if itemize {
            ass.append(Fmt.f("gas $%.2f/gal", p("gas_price")))
            ass.append(cat(Prefs.fmt(mpg), " mpg"))
            ass.append(Fmt.f("wear $%.2f/mi", p("wear_mi")))
        } else {
            ass.append(Fmt.f("vehicle cost $%.2f/mi", costMi))
        }
        if o.items > 0 {
            ass.append(cat(Prefs.fmt(p("shop_min_item")), " min per shop item"))
            ass.append(cat(Prefs.fmt(p("checkout_min")), " min checkout per store"))
        } else {
            ass.append(cat(Prefs.fmt(waitEach), " min wait per pickup"))
        }
        ass.append(cat(Prefs.fmt(p("dropoff_min")), " min per drop-off"))
        ass.append(Fmt.f("%.0f%% of the miles driven back empty", p("empty_pct")))
        ass.append(source)
        if o.payPlus { ass.append("graded at the \"+\" minimum") }
        let assumed = cat("Assumed: ", ass.joined(separator: " · "))
        let floor = cat("against your $", Prefs.fmt(minHr), "/hr floor, after vehicle costs")

        return Analysis(netHr: netHr, netPay: netPay, realMiles: real, emptyMiles: empty, tripMin: orderMin, totalMin: total,
                        waitMin: wait, perMile: perMile, perOfferMile: perOfferMile, verdict: verdict, source: source,
                        merchantLine: merchantLine, reasons: reasons, hard: hard, netPerOfferMile: netPerOfferMile,
                        vehicleCost: vehicleCost, mathLines: math, assumed: assumed, floorLine: floor, payPlus: o.payPlus)
    }
}

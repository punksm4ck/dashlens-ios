import Foundation

struct Field {
    let key: String
    let label: String
    let def: Double
    let group: String
}

struct Sw {
    let key: String
    let label: String
    let def: Bool
}

enum Prefs {
    static let gRules = "Offer rules (what counts as TAKE)"
    static let gCost = "Costs and time assumptions"
    static let gMoney = "Goals, mileage rate and taxes"

    static let fields: [Field] = [
        Field(key: "min_hr", label: "Minimum net $/hr (full cycle)", def: 18, group: gRules),
        Field(key: "min_mi", label: "Minimum $ per real mile", def: 1.5, group: gRules),
        Field(key: "min_pay", label: "Hard filter: minimum offer pay $ (0 = off)", def: 0, group: gRules),
        Field(key: "max_mi", label: "Hard filter: maximum offer miles (0 = off)", def: 0, group: gRules),
        Field(key: "max_stops", label: "Hard filter: maximum pickups / stops (0 = off)", def: 0, group: gRules),
        Field(key: "gas_price", label: "Gas price ($ per gallon)", def: 3.87, group: gCost),
        Field(key: "mpg", label: "Your car's fuel economy (mpg)", def: 25, group: gCost),
        Field(key: "wear_mi", label: "Wear and tear ($ per mile: tires, maintenance, depreciation)", def: 0.18, group: gCost),
        Field(key: "cost_mi", label: "Flat vehicle cost per mile ($) - used only when itemizing is turned off", def: 0.30, group: gCost),
        Field(key: "empty_pct", label: "Empty miles coming back (% of offer miles)", def: 20, group: gCost),
        Field(key: "wait_min", label: "Merchant wait per pickup (min)", def: 7, group: gCost),
        Field(key: "extra_pickup_min", label: "Extra overhead per additional pickup (min)", def: 5, group: gCost),
        Field(key: "dropoff_min", label: "Drop-off handoff time (min)", def: 3, group: gCost),
        Field(key: "shop_min_item", label: "Shop & deliver: shopping time per item (min)", def: 1.5, group: gCost),
        Field(key: "checkout_min", label: "Shop & deliver: checkout time per store (min)", def: 5, group: gCost),
        Field(key: "offer_speed_mph", label: "Avg speed on an order, before DashLens has learned yours (mph)", def: 22, group: gCost),
        Field(key: "speed_mph", label: "Avg speed for the return drive (mph)", def: 25, group: gCost),
        Field(key: "irs_rate", label: "IRS business mileage rate ($/mi) - check each Jan/Jul", def: 0.76, group: gMoney),
        Field(key: "goal_day", label: "Daily earnings goal $ (0 = off)", def: 0, group: gMoney),
        Field(key: "goal_week", label: "Weekly earnings goal $ (0 = off)", def: 0, group: gMoney),
        Field(key: "tax_rate", label: "Income-tax set-aside % (federal + state, applied after self-employment tax)", def: 10, group: gMoney),
        Field(key: "biz_pct", label: "Business-use % of vehicle (actual-expense method only; odometer log overrides)", def: 100, group: gMoney),
    ]

    static let switches: [Sw] = [
        Sw(key: "auto_calibrate", label: "Learn my real order times and merchant history from my own shifts", def: true),
        Sw(key: "overlay_compact", label: "Compact offer card (verdict and key numbers only)", def: false),
        Sw(key: "fb_haptic", label: "Vibrate on verdict (1 buzz take, 2 maybe, 3 decline)", def: false),
        Sw(key: "fb_voice", label: "Speak the verdict aloud", def: false),
        Sw(key: "itemize_cost", label: "Vehicle cost = gas (mpg and gas price) + wear and tear, shown line by line (off = one flat $/mile)", def: true),
        Sw(key: "overlay_math", label: "Show the full math on the offer card (gas, wear, net pay, time, miles counted)", def: true),
        Sw(key: "use_actual_cost", label: "Use my actual gas + maintenance cost per mile (from logged expenses) in offer analysis", def: false),
        Sw(key: "income_manual_only", label: "Income = only what I log by hand (ignore accepted-offer estimates)", def: false),
        Sw(key: "method_actual", label: "Tax method: actual vehicle expenses instead of standard mileage", def: false),
        Sw(key: "basis_online", label: "Mileage basis: all online miles instead of on-order miles only", def: false),
    ]

    /// Typical Dasher numbers for the "Load typical Dasher assumptions" button. Minimum $/hr and $/mile are not touched.
    static let typical: [(String, Double)] = [
        ("gas_price", 3.87), ("mpg", 25), ("wear_mi", 0.18), ("shop_min_item", 1.5), ("checkout_min", 5),
        ("dropoff_min", 5), ("empty_pct", 50), ("offer_speed_mph", 25), ("speed_mph", 25),
    ]

    static func loadTypical() {
        for (k, v) in typical { setNum(k, v) }
        setBool("itemize_cost", true)
        Calibration.reset()
    }

    private static var ud: UserDefaults { UserDefaults.standard }

    static func defaultFor(_ k: String) -> Double {
        fields.first(where: { $0.key == k })?.def ?? 0
    }

    static func num(_ k: String) -> Double {
        let v: Double = ud.object(forKey: k) == nil ? defaultFor(k) : ud.double(forKey: k)
        return (v * 10000.0).rounded() / 10000.0
    }

    static func setNum(_ k: String, _ v: Double) { ud.set(v, forKey: k) }

    static func str(_ k: String) -> String { ud.string(forKey: k) ?? "" }
    static func setStr(_ k: String, _ v: String) { ud.set(v, forKey: k) }

    static func bool(_ k: String, _ def: Bool) -> Bool {
        ud.object(forKey: k) == nil ? def : ud.bool(forKey: k)
    }
    static func setBool(_ k: String, _ v: Bool) { ud.set(v, forKey: k) }

    static func long(_ k: String) -> Int64 { Int64(ud.object(forKey: k) as? Int ?? 0) }
    static func setLong(_ k: String, _ v: Int64) { ud.set(Int(v), forKey: k) }

    static func fmt(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

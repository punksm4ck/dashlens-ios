import Foundation

/// What the Dasher offer screen shows (verified from real screenshots): pay "$5.00" + "Guaranteed (incl. tips)",
/// distance "1.4 mi", "Deliver by 9:44 AM", a "Pickup" label followed by the merchant name, and Accept / Decline.
/// It does NOT show an estimated trip time, so shownMinutes is 0 unless some Dasher version prints one.
struct Offer {
    let pay: Double
    let miles: Double
    let shownMinutes: Double      // minutes printed on the offer, 0 when Dasher shows none
    let windowMin: Double         // minutes from now until "Deliver by", 0 when not shown
    let pickups: Int
    let merchants: [String]
    let tipsIncluded: Bool

    var merchant: String { merchants.first ?? "" }
}

enum OfferParser {
    private static let payRe = rx(#"\$\s?(\d{1,3}(?:\.\d{1,2})?)"#)
    private static let miRe = rx(#"(\d+(?:\.\d+)?)\s*mi\b"#)
    private static let hrRe = rx(#"(\d+)\s*h(?:r|our)s?\b"#)
    private static let minRe = rx(#"(\d+)\s*min"#)
    private static let shownMinRe = rx(#"^\D{0,3}(\d+)\s*min"#)
    private static let countRe = rx(#"(\d+)\s*(?:pickups?|stops?)\b"#)
    private static let deliverByRe = rx(#"deliver\s+by\s+(\d{1,2}):(\d{2})\s*([ap])?\.?m?"#)
    private static let pickupLabelRe = rx(#"^pick-?up(\s+\d+)?$"#)
    private static let notMerchantRe = rx(#"^(customer\s+drop-?off|drop-?off.*|deliver.*|accept.*|decline.*)$"#)

    private static func minutesIn(_ s: String) -> Double? {
        let h = Double(hrRe.firstGroups(in: s)?[1] ?? "") ?? 0
        let m = Double(minRe.firstGroups(in: s)?[1] ?? "")
        if m == nil && h == 0 { return nil }
        return h * 60 + (m ?? 0)
    }

    static func looksLikeOffer(_ texts: [String]) -> Bool {
        texts.contains { $0.lowercased().hasPrefix("accept") || $0.lowercased().hasPrefix("decline") }
    }

    /// Glues "$", "5", ".", "0", "0" back together if a screen draws money one character per node.
    static func normalize(_ texts: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < texts.count {
            let t = texts[i]
            if t == "$" {
                var sb = "$"
                var j = i + 1
                while j < texts.count && j < i + 9 && (texts[j] == "." || (!texts[j].isEmpty && texts[j].allSatisfy { $0.isNumber })) {
                    sb += texts[j]
                    j += 1
                }
                if sb.count > 1 { out.append(sb); i = j; continue }
            }
            out.append(t.replacingOccurrences(of: "\u{2019}", with: "'"))
            i += 1
        }
        return out
    }

    /// Minutes from `now` until a "Deliver by 9:44 AM" line, or 0 when absent / implausible.
    static func windowMinutes(_ texts: [String], now: Date) -> Double {
        let c = LDate.cal.dateComponents([.hour, .minute, .second], from: now)
        let nowMin = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60.0
        for t in texts {
            guard let g = deliverByRe.firstGroups(in: t) else { continue }
            var h = Int(g[1]) ?? 0
            let min = Int(g[2]) ?? 0
            let ap = g[3].lowercased()
            if h > 23 || min > 59 { continue }
            if ap == "p" && h < 12 { h += 12 }
            if ap == "a" && h == 12 { h = 0 }
            var d = Double(h * 60 + min) - nowMin
            if d < -1.0 { d += 24 * 60.0 }
            return (d >= 0 && d <= 240) ? max(d, 1.0) : 0.0
        }
        return 0.0
    }

    /// Returns nil unless the text looks like a DoorDash offer screen with a pay and a distance.
    static func parse(_ raw: [String], now: Date = Date()) -> Offer? {
        if !looksLikeOffer(raw) { return nil }
        let t = normalize(raw)
        let all = t.joined(separator: " | ")

        // pay: the amount on / next to the "Guaranteed (incl. tips)" line, else the first dollar amount
        let money = t.indices.filter { payRe.hasMatch(t[$0]) }
        if money.isEmpty { return nil }
        var pick = money[0]
        for i in money {
            let here = t[i].ci("guarantee") || t[i].ci("incl")
            let next = i + 1 < t.count && t[i + 1].ci("guarantee")
            if here || next { pick = i; break }
        }
        guard let pay = Double(payRe.firstGroups(in: t[pick])?[1] ?? "") else { return nil }

        let combo = t.first { miRe.hasMatch($0) && minutesIn($0) != nil }
        let milesLine: String
        if let c = combo { milesLine = c }
        else if let m = t.first(where: { miRe.hasMatch($0) }) { milesLine = m }
        else { return nil }
        guard let miles = Double(miRe.firstGroups(in: milesLine)?[1] ?? "") else { return nil }

        var shown = 0.0
        if let c = combo {
            shown = minutesIn(c) ?? 0
        } else {
            for line in t {
                if let g = shownMinRe.firstGroups(in: line), let v = Double(g[1]) { shown = v; break }
            }
        }

        var merchants: [String] = []
        for i in t.indices where pickupLabelRe.hasMatch(t[i].trimmingCharacters(in: .whitespaces)) {
            let name = i + 1 < t.count ? t[i + 1].trimmingCharacters(in: .whitespaces) : ""
            if !name.isEmpty && !notMerchantRe.hasMatch(name) && !pickupLabelRe.hasMatch(name) {
                merchants.append(name)
            }
        }
        let counted = Int(countRe.firstGroups(in: all)?[1] ?? "") ?? 0
        let pickups = min(max(max(merchants.count, counted), 1), 6)

        if pay <= 0 || miles <= 0 { return nil }
        let tips = all.ci("incl. tip") || all.ci("guaranteed")
        return Offer(pay: pay, miles: miles, shownMinutes: shown, windowMin: windowMinutes(t, now: now),
                     pickups: pickups, merchants: merchants, tipsIncluded: tips)
    }
}

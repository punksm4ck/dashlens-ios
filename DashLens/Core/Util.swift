import Foundation

/// Calendar date without a time, like java.time.LocalDate. Weeks start on Monday.
struct LDate: Hashable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = TimeZone.autoupdatingCurrent
        return c
    }

    init(_ y: Int, _ m: Int, _ d: Int) { year = y; month = m; day = d }

    init(date: Date) {
        let c = LDate.cal.dateComponents([.year, .month, .day], from: date)
        year = c.year ?? 1970
        month = c.month ?? 1
        day = c.day ?? 1
    }

    static func today() -> LDate { LDate(date: Date()) }

    /// Start of this day in local time.
    var date: Date {
        LDate.cal.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    var startMs: Int64 { Int64((date.timeIntervalSince1970 * 1000.0).rounded()) }

    func plusDays(_ n: Int) -> LDate {
        LDate(date: LDate.cal.date(byAdding: .day, value: n, to: date) ?? date)
    }
    func plusWeeks(_ n: Int) -> LDate { plusDays(7 * n) }
    func plusMonths(_ n: Int) -> LDate {
        LDate(date: LDate.cal.date(byAdding: .month, value: n, to: date) ?? date)
    }
    func plusYears(_ n: Int) -> LDate {
        LDate(date: LDate.cal.date(byAdding: .year, value: n, to: date) ?? date)
    }

    /// Monday = 0 ... Sunday = 6
    var weekdayIndex: Int {
        let w = LDate.cal.component(.weekday, from: date)   // Sunday = 1 ... Saturday = 7
        return (w + 5) % 7
    }

    var isSaturday: Bool { weekdayIndex == 5 }
    var isSunday: Bool { weekdayIndex == 6 }

    func weekStart() -> LDate { plusDays(-weekdayIndex) }
    func firstOfMonth() -> LDate { LDate(year, month, 1) }
    func firstOfYear() -> LDate { LDate(year, 1, 1) }

    func daysUntil(_ other: LDate) -> Int {
        LDate.cal.dateComponents([.day], from: date, to: other.date).day ?? 0
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func parse(_ s: String) -> LDate? {
        let p = s.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }
        let r = LDate(y, m, d)
        // Feb 31 and friends roll over to another day, so they fail this round trip.
        return LDate(date: r.date) == r ? r : nil
    }

    static func < (a: LDate, b: LDate) -> Bool {
        if a.year != b.year { return a.year < b.year }
        if a.month != b.month { return a.month < b.month }
        return a.day < b.day
    }

    func format(_ pattern: String) -> String { Fmt.date(date, pattern) }
}

enum Fmt {
    static func date(_ d: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.autoupdatingCurrent
        f.dateFormat = pattern
        return f.string(from: d)
    }

    static func ms(_ ms: Int64, _ pattern: String) -> String {
        date(Date(timeIntervalSince1970: Double(ms) / 1000.0), pattern)
    }

    static let moneyFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        nf.locale = Locale(identifier: "en_US")
        return nf
    }()

    static func money(_ v: Double) -> String {
        let s = moneyFormatter.string(from: NSNumber(value: abs(v))) ?? "0.00"
        return (v < -0.005 ? "-" : "") + "$" + s
    }

    static func f(_ format: String, _ args: CVarArg...) -> String {
        String(format: format, locale: Locale(identifier: "en_US_POSIX"), arguments: args)
    }
}

extension String {
    func ci(_ needle: String) -> Bool { range(of: needle, options: .caseInsensitive) != nil }

    func padR(_ n: Int) -> String {
        count >= n ? self : self + String(repeating: " ", count: n - count)
    }
    func padL(_ n: Int) -> String {
        count >= n ? self : String(repeating: " ", count: n - count) + self
    }
}

extension NSRegularExpression {
    /// [whole match, group 1, group 2 ...] of the first match, or nil.
    func firstGroups(in s: String) -> [String]? {
        let ns = s as NSString
        guard let m = firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        var out: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            out.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return out
    }

    func hasMatch(_ s: String) -> Bool {
        let ns = s as NSString
        return firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) != nil
    }
}

func rx(_ pattern: String) -> NSRegularExpression {
    // Patterns are constants in this app, so a failure here is a programming error.
    return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
}

/// Runs `f` on the main thread and waits (safe to call from any thread).
func onMainSync(_ f: () -> Void) {
    if Thread.isMainThread { f() } else { DispatchQueue.main.sync(execute: f) }
}

extension Notification.Name {
    static let dashLensDataChanged = Notification.Name("dashLensDataChanged")
}

import Foundation
import UserNotifications

enum Exporter {
    /// Documents/DashLens: shows up in the Files app under On My iPhone > DashLens.
    static func dir() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("DashLens", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func receiptsDir() -> URL {
        let d = dir().appendingPathComponent("Receipts", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @discardableResult
    static func save(name: String, content: String) -> URL? {
        let url = dir().appendingPathComponent(name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func saveReport(_ r: Report, base: String) -> [URL] {
        var out: [URL] = []
        if let u = save(name: base + "_summary.csv", content: Reports.csv(r)) { out.append(u) }
        if let u = save(name: base + "_triplog.csv", content: Reports.tripLog(r)) { out.append(u) }
        if let u = save(name: base + "_summary.txt", content: Reports.text(r)) { out.append(u) }
        if let u = save(name: base + "_offers.csv", content: Reports.offersCsv(r)) { out.append(u) }
        if let u = save(name: base + "_ledger.csv", content: Reports.ledgerCsv(r)) { out.append(u) }
        return out
    }
}

enum Summaries {
    @discardableResult
    static func saveWeek(_ weekStart: LDate, force: Bool) -> Report {
        let r = Reports.build(.week, weekStart)
        if force || r.totals.onlineMs > 0 {
            _ = Exporter.saveReport(r, base: "DashLens_week_\(weekStart.description)")
        }
        Prefs.setStr("last_week_saved", weekStart.description)
        return r
    }

    /// Saves files for every finished week that has not been saved yet. iOS cannot run code at Sunday 23:59,
    /// so this runs whenever the app opens.
    static func catchUp() {
        guard let first = Database.shared.firstStart() else { return }
        var w = LDate(date: Date(timeIntervalSince1970: Double(first) / 1000.0)).weekStart()
        let thisWeek = LDate.today().weekStart()
        var last = Prefs.str("last_week_saved")
        while w < thisWeek {
            if last.isEmpty || w.description > last {
                saveWeek(w, force: false)
                last = w.description
            }
            w = w.plusWeeks(1)
        }
    }
}

enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func status(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let ok = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// Sunday 23:59 reminder to open the app (which then saves the week's files).
    static func scheduleWeekly() {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["weekly"])
        let content = UNMutableNotificationContent()
        content.title = "DashLens weekly summary"
        content.body = "Open DashLens to save this week's mileage and money report."
        var comps = DateComponents()
        comps.weekday = 1          // Sunday
        comps.hour = 23
        comps.minute = 59
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        c.add(UNNotificationRequest(identifier: "weekly", content: content, trigger: trigger))
    }
}

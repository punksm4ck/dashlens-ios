import Foundation
import UIKit
import UserNotifications

/// Counters and status for the Live detection chain, so a tester can copy one report that shows exactly where it stopped:
/// broadcast -> screen reading (extension) -> handoff -> grading -> banner.
final class LiveStats {
    static let shared = LiveStats()
    private let lock = NSLock()

    private var extAt: Date?
    private var ext: [String: Any] = [:]
    private var datagrams = 0
    private var statusMsgs = 0
    private var offerMsgs = 0
    private var rejected = 0
    private var lastReject = ""
    private var gradedCount = 0
    private var banners = 0
    private var selfTests = 0
    private var listenerUp = false
    private var notif = "not checked yet"

    func datagram() { lock.lock(); datagrams += 1; lock.unlock() }
    func offerMsg() { lock.lock(); offerMsgs += 1; lock.unlock() }
    func graded() { lock.lock(); gradedCount += 1; lock.unlock() }
    func banner() { lock.lock(); banners += 1; lock.unlock() }
    func selfTest() { lock.lock(); selfTests += 1; lock.unlock() }
    func listener(_ up: Bool) { lock.lock(); listenerUp = up; lock.unlock() }

    func reject(_ why: String) {
        lock.lock()
        rejected += 1
        lastReject = why
        lock.unlock()
    }

    /// Heartbeat from the extension. Only known keys are kept, with short values.
    func status(_ obj: [String: Any]) {
        var keep: [String: Any] = [:]
        for k in ["up", "frames", "scans", "buttons", "offers", "sent", "mem"] {
            if let n = obj[k] as? Int { keep[k] = n }
        }
        if let e = obj["err"] as? String { keep["err"] = String(e.prefix(120)) }
        lock.lock()
        statusMsgs += 1
        ext = keep
        extAt = Date()
        lock.unlock()
    }

    func refreshNotif(_ done: @escaping () -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            var auth = "unknown"
            switch s.authorizationStatus {
            case .authorized: auth = "allowed"
            case .denied: auth = "DENIED (turn on in Settings > Notifications > DashLens)"
            case .notDetermined: auth = "not asked yet"
            case .provisional: auth = "provisional"
            case .ephemeral: auth = "ephemeral"
            @unknown default: auth = "unknown"
            }
            let alerts = s.alertSetting == .enabled ? "alerts on" : "alerts OFF"
            let ts = s.timeSensitiveSetting == .enabled ? "time-sensitive on" : "time-sensitive off"
            self.lock.lock()
            self.notif = auth + ", " + alerts + ", " + ts
            self.lock.unlock()
            DispatchQueue.main.async { done() }
        }
    }

    private func n(_ k: String) -> String {
        if let v = ext[k] as? Int { return String(v) }
        return "?"
    }

    func report() -> String {
        lock.lock()
        defer { lock.unlock() }
        let info = Bundle.main.infoDictionary
        let ver = (info?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
        var l: [String] = []
        l.append("DashLens Live report, version " + ver + ", iOS " + UIDevice.current.systemVersion)
        l.append("Broadcast: " + (UIScreen.main.isCaptured ? "ON" : "off") + "    Shift running: " + (Tracker.shared.running ? "yes" : "NO"))
        l.append("App receiver listening: " + (listenerUp ? "yes" : "NO"))
        if let at = extAt {
            let age = Int(Date().timeIntervalSince(at))
            l.append("Extension heartbeat: " + String(age) + "s ago, running " + n("up") + "s")
            l.append("  frames " + n("frames") + ", scans " + n("scans") + ", offer screens seen " + n("buttons") + ", offers read " + n("offers") + ", sent " + n("sent"))
            l.append("  lowest free memory " + n("mem") + " MB, last error: " + ((ext["err"] as? String) ?? "none"))
        } else {
            l.append("Extension heartbeat: NONE (broadcast not started, or it cannot reach the app)")
        }
        let why = lastReject.isEmpty ? "" : " [last: " + lastReject + "]"
        l.append("App: datagrams " + String(datagrams) + " (status " + String(statusMsgs) + ", offers " + String(offerMsgs) + "), rejected " + String(rejected) + why)
        l.append("     graded " + String(gradedCount) + ", banners posted " + String(banners) + ", self-tests " + String(selfTests))
        l.append("Notifications: " + notif)
        let ps = Prefs.str("parse_status")
        l.append("Last offer read: " + (ps.isEmpty ? "none yet" : ps))
        return l.joined(separator: "\n")
    }
}

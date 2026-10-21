import Foundation
import CoreLocation

enum DState: String {
    case offline = "OFFLINE"
    case online = "ONLINE"
    case order = "ORDER"

    var label: String {
        switch self {
        case .offline: return "Paused (not logging)"
        case .online: return "Online"
        case .order: return "On order"
        }
    }
}

/// Process-wide shift tracker. All state changes happen on the main thread.
final class Tracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Tracker()

    @Published private(set) var state: DState = .offline
    @Published private(set) var running = false
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var lastFix: CLLocation?

    private var manager: CLLocationManager?
    private var orderStart: Int64 = 0
    private var orderMeters = 0.0
    private var segStart: Int64 = 0
    private var segMeters = 0.0
    private var last: CLLocation?
    private var timer: Timer?
    private var wantAlways = false

    private override init() {
        super.init()
        onMainSync {
            let m = CLLocationManager()
            m.delegate = self
            m.desiredAccuracy = kCLLocationAccuracyBest
            m.distanceFilter = 10
            m.activityType = .automotiveNavigation
            m.pausesLocationUpdatesAutomatically = false
            self.manager = m
            self.authorization = m.authorizationStatus
        }
    }

    var hasLocation: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var hasAlways: Bool { authorization == .authorizedAlways }

    // MARK: permissions

    /// Asks for While Using first, then Always (iOS only shows the Always prompt after While Using).
    func askLocation() {
        onMainSync {
            guard let m = self.manager else { return }
            switch m.authorizationStatus {
            case .notDetermined:
                self.wantAlways = true
                m.requestWhenInUseAuthorization()
            case .authorizedWhenInUse:
                m.requestAlwaysAuthorization()
            default:
                break
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if wantAlways && manager.authorizationStatus == .authorizedWhenInUse {
            wantAlways = false
            manager.requestAlwaysAuthorization()
        }
    }

    // MARK: shift control

    private func persist() {
        Prefs.setBool("trk_running", running)
        Prefs.setStr("trk_state", state.rawValue)
    }

    private func startUpdates() {
        guard let m = manager else { return }
        m.allowsBackgroundLocationUpdates = true
        m.showsBackgroundLocationIndicator = true
        m.startUpdatingLocation()
        m.startMonitoringSignificantLocationChanges()   // lets iOS relaunch the app if it was killed mid-shift
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.flush() }
    }

    private func stopUpdates() {
        guard let m = manager else { return }
        m.stopUpdatingLocation()
        m.stopMonitoringSignificantLocationChanges()
        m.allowsBackgroundLocationUpdates = false
        timer?.invalidate()
        timer = nil
    }

    /// Resume after iOS relaunched the app in the middle of a shift.
    func restore() {
        onMainSync {
            guard !self.running, Prefs.bool("trk_running", false), self.hasLocation else { return }
            self.running = true
            self.state = DState(rawValue: Prefs.str("trk_state")) ?? .online
            if self.state == .offline { self.state = .online }
            self.segStart = nowMs()
            self.segMeters = 0
            self.last = nil
            self.orderStart = self.state == .order ? self.segStart : 0
            self.orderMeters = 0
            self.startUpdates()
        }
    }

    /// Returns false when location permission is missing.
    @discardableResult
    func begin(_ initial: DState = .online) -> Bool {
        var ok = false
        onMainSync {
            guard self.hasLocation else { return }
            if self.running { ok = true; return }
            self.running = true
            self.state = initial
            self.segStart = nowMs()
            self.segMeters = 0
            self.last = nil
            self.orderStart = initial == .order ? self.segStart : 0
            self.orderMeters = 0
            self.persist()
            self.startUpdates()
            ok = true
        }
        return ok
    }

    /// Writes the open chunk to the database and starts a fresh one (every minute and on state changes).
    func flush() {
        onMainSync {
            let now = nowMs()
            if self.running && self.state != .offline && now > self.segStart {
                Database.shared.insertSeg(self.segStart, now, self.state == .order ? "ORDER" : "ONLINE", self.segMeters)
            }
            self.segStart = now
            self.segMeters = 0
        }
    }

    func setState(_ s: DState) {
        onMainSync {
            guard self.running, s != self.state else { return }
            let now = nowMs()
            self.flush()
            if self.state == .order { self.closeOrder(now) }
            self.state = s
            if s == .order { self.orderStart = now; self.orderMeters = 0 }
            self.persist()
        }
    }

    private func closeOrder(_ now: Int64) {
        if orderStart > 0 {
            OfferLog.linkOrder(startMs: orderStart, minutes: Double(now - orderStart) / 60_000.0, miles: orderMeters / 1609.344)
        }
        orderStart = 0
        orderMeters = 0
    }

    func end() {
        onMainSync {
            if self.state == .order { self.closeOrder(nowMs()) }
            self.flush()
            self.running = false
            self.state = .offline
            self.last = nil
            self.persist()
            self.stopUpdates()
        }
    }

    // MARK: location

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for l in locations { onLocation(l) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func onLocation(_ loc: CLLocation) {
        guard running else { return }
        if loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 100 { lastFix = loc }
        if loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > 40 { return }      // poor fix
        guard let prev = last else { last = loc; return }
        let dt = loc.timestamp.timeIntervalSince(prev.timestamp)
        if dt <= 0 { return }
        let d = loc.distance(from: prev)
        if d / dt > 55 { last = loc; return }                                        // > ~120 mph: GPS jump, ignore
        if d < 6 { return }                                                          // jitter while stopped
        last = loc
        if state != .offline { segMeters += d }
        if state == .order { orderMeters += d }
    }
}

/// Tracks the outcome of offers: accepted, passed or still pending.
enum OfferLog {
    /// Offers you never marked count as passed after this long.
    private static let staleMs: Int64 = 5 * 60_000

    static func resolveStale() {
        let db = Database.shared
        for o in db.stalePending(beforeMs: nowMs() - staleMs) { db.setOutcome(o.id, "PASSED") }
    }

    /// Marks the newest pending offer (last 10 minutes) as accepted.
    @discardableResult
    static func acceptLatest() -> OfferRow? {
        let db = Database.shared
        guard let o = db.pendingOffers(sinceMs: nowMs() - 10 * 60_000).first else { return nil }
        db.setOutcome(o.id, "ACCEPTED")
        return db.offer(id: o.id)
    }

    @discardableResult
    static func passLatest() -> OfferRow? {
        let db = Database.shared
        guard let o = db.pendingOffers(sinceMs: nowMs() - 10 * 60_000).first else { return nil }
        db.setOutcome(o.id, "PASSED")
        return db.offer(id: o.id)
    }

    /// An order stretch just ended. Attach its real duration and GPS miles to the accepted offer(s) it belongs to,
    /// so DashLens can learn your true order times. Stacked offers share the stretch equally.
    static func linkOrder(startMs: Int64, minutes: Double, miles: Double) {
        if minutes < 1.0 { return }
        let db = Database.shared
        let open = db.unmeasuredAccepted(sinceMs: startMs - 20 * 60_000)
        if open.isEmpty { return }
        let n = Double(open.count)
        for o in open { db.setActual(o.id, minutes / n, miles / n) }
    }
}

/// What the buttons, the Shortcuts actions and Back Tap all call.
enum ShiftActions {
    static func start() -> String {
        let t = Tracker.shared
        if t.running { return "Shift already running." }
        if !t.hasLocation { return "Open DashLens once and allow location, then try again." }
        return t.begin(.online) ? "Shift started. Logging miles." : "Could not start the shift."
    }

    static func stop() -> String {
        let t = Tracker.shared
        if !t.running { return "No shift is running." }
        t.end()
        let td = Finance.today()
        return "Shift stopped. Today: \(Finance.money(td.income)) estimated, \(Fmt.f("%.1f", td.miles)) miles."
    }

    /// You accepted the offer in Dasher: marks it accepted and starts the on-order stretch.
    static func accepted() -> String {
        OfferLog.resolveStale()
        let o = OfferLog.acceptLatest()
        let t = Tracker.shared
        if t.running { t.setState(.order) }
        if let o = o {
            let who = o.merchant.isEmpty ? "offer" : o.merchant
            return "Accepted \(who), \(Fmt.money(o.pay))." + (t.running ? " On order." : " Start a shift to log miles.")
        }
        return t.running ? "On order. (No recent offer to mark.)" : "No recent offer to mark accepted."
    }

    static func passed() -> String {
        if let o = OfferLog.passLatest() {
            return "Marked passed: \(o.merchant.isEmpty ? "offer" : o.merchant)."
        }
        return "No recent offer to mark."
    }

    static func orderDone() -> String {
        let t = Tracker.shared
        if !t.running { return "No shift is running." }
        t.setState(.online)
        return "Order done. Back online."
    }

    static func pause() -> String {
        let t = Tracker.shared
        if !t.running { return "No shift is running." }
        t.setState(.offline)
        return "Paused."
    }

    static func resume() -> String {
        let t = Tracker.shared
        if !t.running { return "No shift is running." }
        t.setState(.online)
        return "Online."
    }

    static func todayLine() -> String {
        let td = Finance.today()
        return "Today: \(Finance.money(td.income)) estimated, \(td.accepted) accepted, \(Reports.dur(td.onlineMs)) online, \(Fmt.f("%.1f", td.miles)) miles."
    }
}

import Foundation
import Network
import UserNotifications

/// Receives messages from the DashLens Live broadcast extension (same phone, loopback UDP): heartbeats and offers. Offers
/// are graded by the normal engine and shown as a banner on top of whatever app is open. The app is kept running during a
/// shift by the background location session, so start a shift first.
///
/// Security note: any app on this phone can send to a loopback port, so every datagram is validated (size, shape,
/// length, rate) and a forged one can at worst show a fake card.
final class LiveReceiver {
    static let shared = LiveReceiver()
    static let port = NWEndpoint.Port(rawValue: 47831)!

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.dashlens.live.rx")
    private var lastAt = Date.distantPast
    private var lastNotifyKey = ""
    private var lastNotifyAt = Date.distantPast

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.udp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: LiveReceiver.port) else {
            LiveStats.shared.listener(false)
            return
        }
        l.newConnectionHandler = { [weak self] c in
            c.start(queue: self?.queue ?? .global())
            self?.receive(c)
        }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                LiveStats.shared.listener(true)
            case .failed, .cancelled:
                LiveStats.shared.listener(false)
                self?.listener = nil                                   // start() runs again when the app becomes active
            default:
                break
            }
        }
        l.start(queue: queue)
        listener = l
    }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            if let d = data, !d.isEmpty { self?.handle(d) }
            if error == nil { self?.receive(c) } else { c.cancel() }
        }
    }

    private func handle(_ d: Data) {
        let st = LiveStats.shared
        st.datagram()
        guard d.count <= 30_000 else { st.reject("too big"); return }
        guard let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              (obj["v"] as? Int) == 1 else { st.reject("not our format"); return }
        if (obj["type"] as? String) == "status" {
            st.status(obj)
            return
        }
        guard let raw = obj["lines"] as? [String], raw.count <= 120 else { st.reject("bad text list"); return }
        st.offerMsg()
        let isTest = (obj["test"] as? Bool) == true
        let now = Date()
        if !isTest && now.timeIntervalSince(lastAt) < 1.0 { return }     // at most one offer per second
        lastAt = now
        let lines = raw.map { String($0.prefix(160)) }
        guard OfferParser.looksLikeOffer(lines) else { st.reject("no Accept or Decline in the text"); return }

        let outcome = OfferEngine.process(lines: lines, log: !isTest)    // self-tests are never written to the history
        guard let o = outcome.offer, let a = outcome.analysis else { st.reject("could not read pay or miles"); return }
        st.graded()

        let key = "\(o.pay)|\(o.miles)|\(o.merchant)"
        if !isTest && key == lastNotifyKey && now.timeIntervalSince(lastNotifyAt) < 45 { return }
        lastNotifyKey = key
        lastNotifyAt = now
        Feedback.run(a, o)
        LiveReceiver.notify(o, a)
        st.banner()
    }

    /// The banner that appears over Dasher. `delay` > 0 schedules it, so it can be tested after switching to another app.
    static func notify(_ o: Offer, _ a: Analysis, delay: TimeInterval = 0) {
        let c = UNMutableNotificationContent()
        c.title = a.verdict.title + "   " + Fmt.f("$%.0f", a.netHr) + "/hr net"
        var body = o.merchant.isEmpty ? "" : o.merchant + " · "
        body += Fmt.f("$%.2f · %.1f mi · $%.2f per real mile", o.pay, o.miles, a.perMile)
        c.body = body
        c.threadIdentifier = "dashlens-offer"
        c.interruptionLevel = .timeSensitive
        let id = "offer-" + UUID().uuidString
        let trigger: UNNotificationTrigger? = delay > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) : nil
        let center = UNUserNotificationCenter.current()
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
        DispatchQueue.global().asyncAfter(deadline: .now() + delay + 40) {
            center.removeDeliveredNotifications(withIdentifiers: [id])   // offers expire fast: do not leave stale cards
        }
    }

    /// Test 1: sends a fake offer to the listener, exactly like the extension does. Checks the app half of the chain.
    static func selfTest() {
        LiveStats.shared.selfTest()
        let lines = ["Decline", "$5.00", "Guaranteed (incl. tips)", "1.4 mi", "Deliver by 9:44 AM",
                     "Pickup", "Self-test Deli", "Customer dropoff", "Accept 37"]
        let obj: [String: Any] = ["v": 1, "test": true, "lines": lines]
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        let c = NWConnection(host: "127.0.0.1", port: LiveReceiver.port, using: .udp)
        c.start(queue: .global())
        c.send(content: data, completion: .contentProcessed { _ in c.cancel() })
    }

    /// Test 2: a banner in 5 seconds, so you can switch to another app and see it appear on top.
    static func delayedTestBanner() {
        let s = OfferEngine.sample()
        notify(s.0, s.1, delay: 5)
    }
}

/// Lets the banner also show while DashLens itself is open.
final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

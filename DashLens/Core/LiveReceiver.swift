import Foundation
import Network
import UserNotifications

/// Receives offers from the DashLens Live broadcast extension (same phone, loopback UDP), grades them with the normal
/// engine and shows the verdict as a banner on top of whatever app is open. The app is kept running during a shift by
/// the background location session, so start a shift first.
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
        guard let l = try? NWListener(using: params, on: LiveReceiver.port) else { return }
        l.newConnectionHandler = { [weak self] c in
            c.start(queue: self?.queue ?? .global())
            self?.receive(c)
        }
        l.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.listener = nil }         // start() runs again when the app becomes active
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
        guard d.count <= 30_000,
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              (obj["v"] as? Int) == 1,
              let raw = obj["lines"] as? [String], raw.count <= 120 else { return }
        let now = Date()
        if now.timeIntervalSince(lastAt) < 1.0 { return }             // at most one offer per second
        lastAt = now
        let lines = raw.map { String($0.prefix(160)) }
        guard OfferParser.looksLikeOffer(lines) else { return }

        let outcome = OfferEngine.process(lines: lines, log: true)
        guard let o = outcome.offer, let a = outcome.analysis else { return }

        let key = "\(o.pay)|\(o.miles)|\(o.merchant)"
        if key == lastNotifyKey && now.timeIntervalSince(lastNotifyAt) < 45 { return }
        lastNotifyKey = key
        lastNotifyAt = now
        Feedback.run(a, o)
        LiveReceiver.notify(o, a)
    }

    /// The banner that appears over Dasher.
    static func notify(_ o: Offer, _ a: Analysis) {
        let c = UNMutableNotificationContent()
        c.title = a.verdict.title + "   " + Fmt.f("$%.0f", a.netHr) + "/hr net"
        var body = o.merchant.isEmpty ? "" : o.merchant + " · "
        body += Fmt.f("$%.2f · %.1f mi · $%.2f per real mile", o.pay, o.miles, a.perMile)
        c.body = body
        c.threadIdentifier = "dashlens-offer"
        c.interruptionLevel = .timeSensitive
        let id = "offer-" + UUID().uuidString
        let center = UNUserNotificationCenter.current()
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
        DispatchQueue.global().asyncAfter(deadline: .now() + 40) {
            center.removeDeliveredNotifications(withIdentifiers: [id])   // offers expire fast: do not leave stale cards
        }
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

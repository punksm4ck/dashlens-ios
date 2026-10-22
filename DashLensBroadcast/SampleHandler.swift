import ReplayKit
import Vision
import Network
import CoreMedia
import CoreVideo
import ImageIO
import os

/// DashLens Live. While you run a screen broadcast, this extension looks at the lower part of the screen about twice a
/// second. When it sees a Dasher offer (Accept button, pay and miles) it reads the text and sends it to the DashLens app
/// over loopback (this phone only). The app does the grading and shows the verdict as a banner. It also sends a small
/// heartbeat every 5 seconds (counters only) so the app can show whether the broadcast is alive. Nothing leaves the phone.
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "app.dashlens.live.ocr", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var lastRun = Date.distantPast
    private var conn: NWConnection?
    private var timer: DispatchSourceTimer?
    private let startedAt = Date()

    // counters, guarded by `lock`
    private var frames = 0
    private var scans = 0
    private var buttons = 0
    private var offers = 0
    private var sent = 0
    private var minMemMB = Int.max
    private var lastError = "none"

    // used only on `queue`
    private var lastKey = ""
    private var lastSentAt = Date.distantPast
    private var missing = 0

    private func bump(_ f: () -> Void) {
        lock.lock()
        f()
        lock.unlock()
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let c = NWConnection(host: "127.0.0.1", port: 47831, using: .udp)
        c.start(queue: queue)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 5)
        t.setEventHandler { [weak self] in self?.sendStatus() }
        t.resume()
        queue.sync {
            conn = c
            timer = t
        }
    }

    override func broadcastFinished() {
        queue.sync {
            timer?.cancel()
            timer = nil
            conn?.cancel()
            conn = nil
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        bump { frames += 1 }
        let now = Date()
        if now.timeIntervalSince(lastRun) < 0.5 { return }          // about 2 looks per second keeps battery and memory low

        lock.lock()
        let skip = busy
        if !skip { busy = true }
        lock.unlock()
        if skip { return }

        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            finishScan()
            return
        }
        lastRun = now

        var orientation = CGImagePropertyOrientation.up
        if let n = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
           let o = CGImagePropertyOrientation(rawValue: n.uint32Value) {
            orientation = o
        }
        queue.async { [weak self] in
            autoreleasepool { self?.scan(pb, orientation) }
        }
    }

    private func finishScan() {
        lock.lock()
        busy = false
        lock.unlock()
    }

    private func read(_ pb: CVPixelBuffer, _ orientation: CGImagePropertyOrientation, _ roi: CGRect, accurate: Bool) -> [String] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = accurate ? .accurate : .fast
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US"]
        req.regionOfInterest = roi
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: orientation, options: [:])
        do {
            try handler.perform([req])
        } catch {
            let msg = "vision: " + error.localizedDescription
            bump { lastError = msg }
            return []
        }
        return ScreenText.lines(from: req.results ?? [])
    }

    private func scan(_ pb: CVPixelBuffer, _ orientation: CGImagePropertyOrientation) {
        defer { finishScan() }
        // The offer card and the Accept button sit in the lower part of the screen. Reading only that part keeps
        // the extension well under iOS's small memory limit for broadcast extensions.
        let roi = CGRect(x: 0, y: 0, width: 1, height: 0.62)

        let quick = read(pb, orientation, roi, accurate: false)
        bump { scans += 1 }
        let mem = os_proc_available_memory() / 1_048_576
        bump { minMemMB = min(minMemMB, mem) }

        let sawButton = quick.contains { l in
            let s = l.lowercased()
            return s.hasPrefix("accept") || s.hasPrefix("decline")
        }
        if !sawButton {
            missing += 1
            if missing >= 3 { lastKey = "" }                        // the offer is gone: a repeat of it counts as new
            return
        }
        missing = 0
        bump { buttons += 1 }

        let lines = read(pb, orientation, roi, accurate: true)       // careful second read, only when an offer is up
        guard ScreenText.looksLikeOffer(lines) else { return }
        bump { offers += 1 }

        let money = lines.first { $0.contains("$") } ?? ""
        let miles = lines.first { $0.lowercased().contains(" mi") } ?? ""
        let key = money + "|" + miles
        let now = Date()
        if key == lastKey && now.timeIntervalSince(lastSentAt) < 45 { return }
        lastKey = key
        lastSentAt = now
        send(lines)
    }

    private func send(_ lines: [String]) {
        let clipped = lines.prefix(120).map { String($0.prefix(160)) }
        let obj: [String: Any] = ["v": 1, "t": Date().timeIntervalSince1970, "lines": clipped]
        guard let data = try? JSONSerialization.data(withJSONObject: obj), data.count < 30_000 else { return }
        bump { sent += 1 }
        conn?.send(content: data, completion: .contentProcessed { [weak self] err in
            if let err = err {
                let msg = "send: " + err.localizedDescription
                self?.bump { self?.lastError = msg }
            }
        })
    }

    /// Counters only, every 5 seconds, so the app can show whether the broadcast is alive and what it has seen.
    private func sendStatus() {
        lock.lock()
        let obj: [String: Any] = [
            "v": 1, "type": "status", "up": Int(Date().timeIntervalSince(startedAt)),
            "frames": frames, "scans": scans, "buttons": buttons, "offers": offers, "sent": sent,
            "mem": minMemMB == Int.max ? -1 : minMemMB, "err": String(lastError.prefix(120))
        ]
        lock.unlock()
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        conn?.send(content: data, completion: .contentProcessed { _ in })
    }
}

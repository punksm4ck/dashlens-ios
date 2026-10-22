import ReplayKit
import Vision
import Network
import CoreMedia
import CoreVideo
import ImageIO

/// DashLens Live. While you run a screen broadcast, this extension looks at the lower part of the screen about twice a
/// second. When it sees a Dasher offer (Accept button, pay and miles) it reads the text and sends it to the DashLens app
/// over loopback (this phone only). The app does the grading and shows the verdict as a banner. Nothing leaves the phone.
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "app.dashlens.live.ocr", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var lastRun = Date.distantPast
    private var conn: NWConnection?

    // used only on `queue`
    private var lastKey = ""
    private var lastSentAt = Date.distantPast
    private var missing = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let c = NWConnection(host: "127.0.0.1", port: 47831, using: .udp)
        c.start(queue: queue)
        queue.sync { conn = c }
    }

    override func broadcastFinished() {
        queue.sync {
            conn?.cancel()
            conn = nil
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
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
        do { try handler.perform([req]) } catch { return [] }
        return ScreenText.lines(from: req.results ?? [])
    }

    private func scan(_ pb: CVPixelBuffer, _ orientation: CGImagePropertyOrientation) {
        defer { finishScan() }
        // The offer card and the Accept button sit in the lower part of the screen. Reading only that part keeps
        // the extension well under iOS's small memory limit for broadcast extensions.
        let roi = CGRect(x: 0, y: 0, width: 1, height: 0.62)

        let quick = read(pb, orientation, roi, accurate: false)
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

        let lines = read(pb, orientation, roi, accurate: true)       // careful second read, only when an offer is up
        guard ScreenText.looksLikeOffer(lines) else { return }

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
        conn?.send(content: data, completion: .contentProcessed { _ in })
    }
}

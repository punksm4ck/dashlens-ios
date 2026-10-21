import Foundation
import UIKit
import Vision
import AVFoundation
import AudioToolbox

/// Screenshot -> on-device text recognition -> offer parser -> verdict. Nothing leaves the phone.
enum OfferEngine {
    struct Outcome {
        let offer: Offer?
        let analysis: Analysis?
        let lines: [String]
        let loggedId: Int64?
    }

    // MARK: text recognition

    private struct Item {
        let text: String
        let x: CGFloat
        let y: CGFloat
    }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// Text lines of the screenshot, top to bottom and left to right. Blocking: call off the main thread.
    static func recognize(_ image: UIImage) -> [String] {
        guard let cg = image.cgImage else { return [] }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image.imageOrientation), options: [:])
        do { try handler.perform([req]) } catch { return [] }

        var items: [Item] = []
        for o in (req.results ?? []) {
            guard let s = o.topCandidates(1).first?.string else { continue }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            items.append(Item(text: t, x: o.boundingBox.minX, y: o.boundingBox.midY))
        }
        items.sort { $0.y > $1.y }                       // Vision's origin is bottom-left, so larger y = higher on screen

        var rows: [[Item]] = []
        for it in items {
            if let first = rows.last?.first, abs(first.y - it.y) < 0.012 {
                rows[rows.count - 1].append(it)
            } else {
                rows.append([it])
            }
        }
        var out: [String] = []
        for r in rows {
            for it in r.sorted(by: { $0.x < $1.x }) { out.append(it.text) }
        }
        return out
    }

    // MARK: analysis + log

    private static let lock = NSLock()
    private static var lastKey = ""
    private static var lastAt: Int64 = 0
    private static var lastId: Int64 = 0

    /// Parses the screen text. When `log` is true the offer is written to the history (the same offer twice
    /// within a minute is logged once).
    static func process(lines: [String], log: Bool) -> Outcome {
        Prefs.setStr("last_dump", String(lines.joined(separator: " | ").prefix(4000)))
        let offer = OfferParser.parse(lines)
        guard let o = offer else {
            if OfferParser.looksLikeOffer(lines) {
                Prefs.setStr("parse_status", "FAILED: an offer screen was seen but pay or miles could not be read. Copy the offer text below.")
            } else {
                Prefs.setStr("parse_status", "No Accept / Decline buttons found in that screenshot, so it was not treated as an offer.")
            }
            return Outcome(offer: nil, analysis: nil, lines: lines, loggedId: nil)
        }
        Prefs.setStr("parse_status", "OK: read $\(o.pay), \(o.miles) mi" + (o.merchant.isEmpty ? ", merchant not found" : ", \(o.merchant)"))
        let a = Analyzer.analyze(o)
        var id: Int64? = nil
        if log { id = logOffer(o, a) }
        return Outcome(offer: o, analysis: a, lines: lines, loggedId: id)
    }

    private static func logOffer(_ o: Offer, _ r: Analysis) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(o.pay)|\(o.miles)|\(o.merchants.joined(separator: "+"))"
        let now = nowMs()
        if key == lastKey && now - lastAt < 60_000 && lastId > 0 {
            lastAt = now
            return lastId
        }
        OfferLog.resolveStale()
        let fix = Tracker.shared.lastFix
        let row = OfferRow(id: 0, ts: now, pay: o.pay, miles: o.miles, minutes: r.tripMin, pickups: o.pickups,
                           verdict: r.verdict.rawValue, netHr: r.netHr, perMile: r.perMile, outcome: "PENDING",
                           lat: fix?.coordinate.latitude ?? 0, lon: fix?.coordinate.longitude ?? 0,
                           merchant: o.merchant, actualMin: 0, actualMi: 0, windowMin: o.windowMin, tipsIncl: o.tipsIncluded,
                           items: o.items, payPlus: o.payPlus)
        let id = Database.shared.insertOffer(row)
        lastKey = key
        lastAt = now
        lastId = id
        return id
    }

    /// A sample shop & deliver offer, like the Android preview. Never written to the history.
    static func sample() -> (Offer, Analysis) {
        let o = Offer(pay: 22.0, miles: 4.7, shownMinutes: 0, windowMin: 0, pickups: 1, merchants: ["Dollar General"],
                      tipsIncluded: false, items: 4, payPlus: true)
        return (o, Analyzer.analyze(o))
    }

    /// One-line text for Shortcuts and Siri.
    static func spokenLine(_ o: Offer, _ a: Analysis) -> String {
        "\(a.verdict.spoken). \(Fmt.f("%.0f", a.netHr)) dollars an hour net. \(Fmt.f("$%.2f", o.pay)) for \(Fmt.f("%.1f", o.miles)) miles."
    }
}

/// Optional vibration / voice when a verdict arrives.
enum Feedback {
    private static let synth = AVSpeechSynthesizer()

    static func run(_ a: Analysis, _ o: Offer) {
        if Prefs.bool("fb_haptic", false) {
            let n: Int
            switch a.verdict {
            case .take: n = 1
            case .maybe: n = 2
            case .decline: n = 3
            }
            for i in 0..<n {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.45) {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        }
        if Prefs.bool("fb_voice", false) {
            DispatchQueue.main.async {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try? session.setActive(true)
                let u = AVSpeechUtterance(string: "\(a.verdict.spoken). \(Fmt.f("%.0f", a.netHr)) dollars an hour.")
                u.voice = AVSpeechSynthesisVoice(language: "en-US")
                synth.speak(u)
            }
        }
    }
}

import Foundation
import Vision
import CoreGraphics

/// Shared by the app and the DashLens Live broadcast extension: turns Vision text observations into screen
/// lines (top to bottom, left to right) and does a cheap "is this a Dasher offer?" check.
enum ScreenText {
    static func lines(from results: [VNRecognizedTextObservation]) -> [String] {
        struct Item {
            let text: String
            let x: CGFloat
            let y: CGFloat
        }
        var items: [Item] = []
        for o in results {
            guard let s = o.topCandidates(1).first?.string else { continue }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            items.append(Item(text: t, x: o.boundingBox.minX, y: o.boundingBox.midY))
        }
        items.sort { $0.y > $1.y }                        // Vision's origin is bottom-left: larger y = higher on screen
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

    /// Accept / Decline button plus a dollar amount plus miles.
    static func looksLikeOffer(_ lines: [String]) -> Bool {
        var button = false
        var money = false
        var miles = false
        for l in lines {
            let s = l.lowercased()
            if s.hasPrefix("accept") || s.hasPrefix("decline") { button = true }
            if s.contains("$") { money = true }
            if s.contains(" mi") || s.hasSuffix("mi") { miles = true }
        }
        return button && money && miles
    }
}

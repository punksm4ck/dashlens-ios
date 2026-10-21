import SwiftUI
import UIKit

/// A shareable picture of one graded offer: verdict, net $/hr and $/mi, and the line-by-line math.
/// Same content as the Android share card. Drawn on a white card so it reads well in any chat app.
struct ShareCardView: View {
    let offer: Offer
    let analysis: Analysis

    private static let ink = Color(hex: 0x1B1F23)
    private static let grey = Color(hex: 0x6B7280)
    private static let brand = Color(hex: 0x2E7D32)
    private static let tileFill = Color(hex: 0xF3F4F6)

    private var accent: Color {
        switch analysis.verdict {
        case .take: return Color(hex: 0x2E7D32)
        case .maybe: return Color(hex: 0xE09B00)
        case .decline: return Color(hex: 0xC62828)
        }
    }

    private var word: String {
        switch analysis.verdict {
        case .take: return "TAKE IT"
        case .maybe: return "MAYBE"
        case .decline: return "DECLINE"
        }
    }

    private func tile(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12, weight: .bold)).foregroundColor(ShareCardView.grey)
            Text(value).font(.system(size: 26, weight: .bold)).foregroundColor(ShareCardView.ink).minimumScaleFactor(0.6).lineLimit(1)
            Text(sub).font(.system(size: 11)).foregroundColor(ShareCardView.grey).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(ShareCardView.tileFill))
    }

    private var subtitle: String {
        guard !offer.merchant.isEmpty else { return "" }
        let more = offer.pickups > 1 ? "  +\(offer.pickups - 1) more" : ""
        let items = offer.items > 0 ? "  ·  \(offer.items) items" : ""
        return cat(offer.merchant, more, items)
    }

    var body: some View {
        let a = analysis
        let plus = offer.payPlus ? "+" : ""
        VStack(alignment: .leading, spacing: 0) {
            Text("DASHLENS OFFER CHECK").font(.system(size: 13, weight: .bold)).tracking(1.0).foregroundColor(ShareCardView.brand)
            Text(cat(Fmt.f("$%.2f", offer.pay), plus, Fmt.f("  ·  %.1f mi", offer.miles)))
                .font(.system(size: 30, weight: .bold)).foregroundColor(ShareCardView.ink).padding(.top, 8)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 18)).foregroundColor(ShareCardView.grey).padding(.top, 2)
            }
            VStack(spacing: 2) {
                Text(word).font(.system(size: 36, weight: .bold)).foregroundColor(.white)
                Text(a.floorLine).font(.system(size: 14)).foregroundColor(.white).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18).fill(accent))
            .padding(.top, 16)

            HStack(spacing: 10) {
                tile("NET $/HR", Finance.money(a.netHr) + plus, cat(Finance.money(a.netPay), " net ÷ ", Fmt.f("%.0f", a.totalMin), " min"))
                tile("NET $/MI", Finance.money(a.netPerOfferMile) + plus, cat(Finance.money(a.netPay), " net ÷ ", Fmt.f("%.1f", offer.miles), " offer mi"))
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(a.mathLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 13, weight: line.hasPrefix("Net pay") ? .bold : .regular))
                        .foregroundColor(ShareCardView.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 14)

            Text(a.assumed).font(.system(size: 11)).foregroundColor(ShareCardView.grey)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            Text("Graded by DashLens").font(.system(size: 14, weight: .bold)).foregroundColor(ShareCardView.brand)
                .frame(maxWidth: .infinity).padding(.top, 14)
            Text("Estimates from your own settings. Not financial or tax advice.").font(.system(size: 10))
                .foregroundColor(ShareCardView.grey).frame(maxWidth: .infinity).padding(.top, 2)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
        .frame(width: 360)
        .background(Color.white)
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

/// Renders the share card to a PNG and hands it to the iOS share sheet (which also offers Save Image).
enum ShareCard {
    /// The offer again, rebuilt from a history row so it can be graded with your current settings.
    static func offer(from row: OfferRow) -> Offer {
        Offer(pay: row.pay, miles: row.miles, shownMinutes: 0, windowMin: row.windowMin, pickups: row.pickups,
              merchants: row.merchant.isEmpty ? [] : [row.merchant], tipsIncluded: row.tipsIncl,
              items: row.items, payPlus: row.payPlus)
    }

    @MainActor static func payload(_ o: Offer, _ a: Analysis) -> SharePayload? {
        let renderer = ImageRenderer(content: ShareCardView(offer: o, analysis: a).environment(\.colorScheme, .light))
        renderer.scale = 3
        guard let img = renderer.uiImage, let data = img.pngData() else { return nil }
        let name = "DashLens_offer_" + Fmt.date(Date(), "yyyyMMdd_HHmmss") + ".png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url) } catch { return nil }
        return SharePayload(url: url)
    }

    @MainActor static func payload(_ row: OfferRow) -> SharePayload? {
        let o = offer(from: row)
        return payload(o, Analyzer.analyze(o))
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

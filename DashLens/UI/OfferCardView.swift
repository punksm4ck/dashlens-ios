import SwiftUI

/// The TAKE / MAYBE / DECLINE card. Used in the Shortcuts result and inside the app.
struct OfferCardView: View {
    let offer: Offer?
    let analysis: Analysis?
    var message: String = ""
    var compact: Bool = Prefs.bool("overlay_compact", false)

    private func stat(_ label: String, _ value: String, _ color: Color = .white) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.muted)
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(color).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        if let o = offer, let a = analysis {
            let accent = Theme.verdictColor(a.verdict.rawValue)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(a.verdict.title).font(.system(size: 22, weight: .bold)).foregroundColor(accent)
                    Spacer()
                    Text(Fmt.f("$%.0f/hr net", a.netHr)).font(.system(size: 19, weight: .bold)).foregroundColor(accent)
                }
                if !o.merchant.isEmpty {
                    let extra = o.pickups > 1 ? "  +\(o.pickups - 1) more" : ""
                    let tips = o.tipsIncluded ? "   ·   tips included" : ""
                    Text(o.merchant + extra + tips).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
                }
                HStack {
                    stat("PAY", Fmt.f("$%.2f", o.pay))
                    stat("$ / MILE", Fmt.f("$%.2f", a.perOfferMile))
                    stat("MILES", Fmt.f("%.1f", o.miles))
                    stat("ORDER TIME", "~\(Int(a.tripMin)) min")
                }
                if !compact {
                    HStack {
                        stat("$ / REAL MILE", Fmt.f("$%.2f", a.perMile), a.perMile >= Prefs.num("min_mi") ? Theme.green : Theme.red)
                        stat("REAL MILES", Fmt.f("%.1f", a.realMiles))
                        stat("WHOLE CYCLE", "~\(Int(a.totalMin)) min")
                        if o.windowMin > 0 { stat("DELIVER BY", "in \(Int(o.windowMin)) min") }
                    }
                    ForEach(Array(a.reasons.prefix(4).enumerated()), id: \.offset) { _, r in
                        Text("• " + r).font(.system(size: 11)).foregroundColor(Color(hex: 0xD0D3D8))
                    }
                }
                if !a.merchantLine.isEmpty {
                    Text(a.merchantLine).font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: 0x7FB2FF))
                }
                let td = Finance.today()
                let goal = Finance.goalLine(td)
                Text("Today: \(Finance.money(td.income)) est. · \(td.accepted) accepted · \(Reports.dur(td.onlineMs)) online" + (goal.isEmpty ? "" : " · " + goal))
                    .font(.system(size: 10)).foregroundColor(Theme.muted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x111418)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent, lineWidth: 2))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("No offer found").font(.system(size: 20, weight: .bold)).foregroundColor(Theme.amber)
                Text(message.isEmpty ? "Could not read an offer on that screenshot." : message)
                    .font(.system(size: 13)).foregroundColor(Theme.text)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x111418)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.amber, lineWidth: 2))
        }
    }
}

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

    /// The line-by-line math (gas, wear, net pay, time, miles counted), or the short reasons when it is switched off.
    @ViewBuilder private func detail(_ o: Offer, _ a: Analysis) -> some View {
        if Prefs.bool("overlay_math", true) {
            ForEach(Array(a.hard.enumerated()), id: \.offset) { _, h in
                Text("• " + h).font(.system(size: 11)).foregroundColor(Theme.red)
            }
            ForEach(Array(a.mathLines.enumerated()), id: \.offset) { _, line in
                let net = line.hasPrefix("Net pay")
                Text(line)
                    .font(.system(size: 11, weight: net ? .bold : .regular))
                    .foregroundColor(net ? Color.white : Color(hex: 0xD0D3D8))
            }
            if o.payPlus {
                Text("Graded at the + minimum: real pay may be higher.").font(.system(size: 11)).foregroundColor(Theme.amber)
            }
        } else {
            ForEach(Array(a.reasons.prefix(4).enumerated()), id: \.offset) { _, r in
                Text("• " + r).font(.system(size: 11)).foregroundColor(Color(hex: 0xD0D3D8))
            }
        }
    }

    var body: some View {
        if let o = offer, let a = analysis {
            let accent = Theme.verdictColor(a.verdict.rawValue)
            let plus = o.payPlus ? "+" : ""
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(a.verdict.title).font(.system(size: 22, weight: .bold)).foregroundColor(accent)
                    Spacer()
                    Text(Fmt.f("$%.0f/hr net", a.netHr) + plus).font(.system(size: 19, weight: .bold)).foregroundColor(accent)
                }
                Text(a.floorLine).font(.system(size: 11)).foregroundColor(Theme.muted)
                if !o.merchant.isEmpty {
                    let extra = o.pickups > 1 ? "  +\(o.pickups - 1) more" : ""
                    let tips = o.tipsIncluded ? "   ·   tips included" : ""
                    Text(o.merchant + extra + tips).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
                }
                HStack {
                    stat("PAY", Fmt.f("$%.2f", o.pay) + plus)
                    stat("NET $ / MI", Fmt.f("$%.2f", a.netPerOfferMile) + plus, a.netPerOfferMile >= 0 ? Color.white : Theme.red)
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
                    detail(o, a)
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

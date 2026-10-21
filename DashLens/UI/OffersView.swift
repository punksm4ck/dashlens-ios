import SwiftUI

struct OffersView: View {
    @EnvironmentObject var app: AppState
    @State private var tab = 0

    private func nextOutcome(_ o: String) -> String { o == "ACCEPTED" ? "PASSED" : "ACCEPTED" }

    var body: some View {
        let _ = app.rev
        let now = nowMs()
        let db = Database.shared
        let today = db.offers(LDate.today().startMs, now + 1000)
        Screen(title: "Offers") {
            HStack {
                StatTile(label: "Seen today", value: "\(today.count)")
                StatTile(label: "Accepted", value: "\(today.filter { $0.outcome == "ACCEPTED" }.count)", color: Theme.green)
                StatTile(label: "Passed", value: "\(today.filter { $0.outcome == "PASSED" }.count)")
            }
            .card()

            Chips(items: ["History", "Merchants"], selection: $tab)

            if tab == 0 { history(db.offers(now - 365 * 86_400_000, now + 1000, limit: 200)) }
            else { merchants(db.merchants(now - 365 * 86_400_000, now + 1000)) }
        }
    }

    private func extraLine(_ o: OfferRow) -> String {
        var extra = Fmt.ms(o.ts, "EEE MMM d, HH:mm")
        if o.actualMin > 0 { extra += Fmt.f(" · took %.0f min, %.1f mi", o.actualMin, o.actualMi) }
        return extra
    }

    @ViewBuilder private func history(_ rows: [OfferRow]) -> some View {
        if rows.isEmpty {
            Caption("Nothing logged yet. Every offer you analyze with the DashLens shortcut shows up here.")
        } else {
            Caption("Offers you don't mark accepted within 5 minutes count as passed. Tap the tag on a row to correct it.")
            ForEach(rows) { o in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Pill(text: o.verdict, color: Theme.verdictColor(o.verdict))
                        Text(o.merchant.isEmpty ? "Offer" : o.merchant).font(.subheadline.weight(.bold)).foregroundColor(Theme.text)
                        Spacer()
                        Button {
                            Database.shared.setOutcome(o.id, nextOutcome(o.outcome))
                        } label: {
                            Pill(text: o.outcome, color: Theme.outcomeColor(o.outcome))
                        }
                        .buttonStyle(.plain)
                    }
                    Text(Fmt.f("$%.2f · %.1f mi · ~$%.0f/hr net · $%.2f per real mile", o.pay, o.miles, o.netHr, o.perMile))
                        .font(.footnote).foregroundColor(Theme.text)
                    Caption(extraLine(o))
                }
                .card()
            }
        }
    }

    @ViewBuilder private func merchants(_ list: [MerchantStat]) -> some View {
        if list.isEmpty {
            Caption("Merchant history builds up as you take offers. After two completed orders at a place, DashLens uses your real times there.")
        } else {
            let cost = Prefs.num("cost_mi")
            let minHr = Prefs.num("min_hr")
            ForEach(list) { m in
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.name).font(.subheadline.weight(.bold)).foregroundColor(Theme.text)
                    Caption("Seen \(m.seen) · accepted \(m.accepted)" + (m.accepted > 0 ? Fmt.f(" · avg pay $%.2f", m.avgPay) : ""))
                    if m.done > 0 {
                        let hr = m.hourly(cost)
                        Text("\(m.done) completed · " + Fmt.f("avg %.0f min · about $%.0f/hr realised", m.avgMin, hr))
                            .font(.footnote.weight(.bold)).foregroundColor(hr >= minHr ? Theme.green : Theme.amber)
                    }
                }
                .card()
            }
        }
    }
}

import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openURL) private var openURL
    @State private var daysSel = 0
    private let options = [30, 90, 365]

    var body: some View {
        let _ = app.rev
        let days = options[daysSel]
        let now = nowMs()
        let rows = Database.shared.offers(now - Int64(days) * 86_400_000, now)
        let st = Insights.offerStats(rows)
        let slots = Insights.slots(days)
        let wd = Insights.byWeekday(slots)
        let best = wd.filter { $0.minutes >= 30 }.max(by: { $0.perHr < $1.perHr })
        let top = Insights.topSlots(slots, minMinutes: 60, n: 6)
        let hot = Insights.hotspots(rows, 5)
        let td = Finance.today()
        let week = LDate.today().weekStart()
        let wk = Finance.incomeBetween(week, week.plusWeeks(1))
        let gd = Prefs.num("goal_day")
        let gw = Prefs.num("goal_week")
        let cal = Calibration.get()

        Screen(title: "Insights") {
            Chips(items: ["30 days", "90 days", "365 days"], selection: $daysSel)

            VStack(alignment: .leading, spacing: 8) {
                Text("Offers").font(.headline).foregroundColor(Theme.text)
                if st.total == 0 {
                    Caption("Nothing logged yet. Offers appear here once you've analyzed some.")
                } else {
                    HStack {
                        StatTile(label: "Seen", value: "\(st.total)")
                        StatTile(label: "Accepted", value: "\(st.accepted)", color: Theme.green)
                        StatTile(label: "Accept rate", value: Fmt.f("%.0f%%", Double(st.accepted) * 100.0 / Double(st.total)))
                    }
                    Text("Accepted on average: \(Finance.money(st.avgPay)), " + Fmt.f("$%.2f per real mile, about $%.0f/hr net.", st.avgPerMile, st.avgNetHr))
                        .font(.footnote).foregroundColor(Theme.text)
                    Caption("\(st.passedGood) offers rated TAKE were passed · \(st.acceptedBad) rated DECLINE were accepted.")
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 6) {
                Text("Your real pace").font(.headline).foregroundColor(Theme.text)
                if let c = cal {
                    Caption("DashLens has learned that you drive about " + Fmt.f("%.0f", c.mph) + " mph on orders (" + Fmt.f("%.1f", c.minPerMi)
                            + " min per mile), from \(c.n) completed orders. Offer times now use your pace instead of a guess.")
                } else {
                    Caption("Dasher does not show trip time, so DashLens estimates it. Complete 5 orders with a shift running (mark On order / Order done) and it learns your real pace automatically.")
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 4) {
                Text("Best weekdays").font(.headline).foregroundColor(Theme.text)
                if wd.allSatisfy({ $0.minutes < 30 }) {
                    Caption("Needs some logged shifts first.")
                } else {
                    ForEach(wd, id: \.key) { w in
                        let isBest = best != nil && best!.key == w.key
                        let hrs = Fmt.f("%4.1f h", w.minutes / 60.0)
                        let rate = w.minutes >= 30 ? Fmt.f("$%.0f/hr", w.perHr) : "-"
                        Text(Insights.days[w.key] + "   " + hrs + "   " + Finance.money(w.pay).padL(9) + "   " + rate)
                            .font(.system(size: 12, weight: isBest ? .bold : .regular, design: .monospaced))
                            .foregroundColor(isBest ? Theme.green : Theme.text)
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 4) {
                Text("Best time slots").font(.headline).foregroundColor(Theme.text)
                if top.isEmpty {
                    Caption("Needs more shifts: a slot needs an hour online across the period.")
                } else {
                    ForEach(top, id: \.key) { s in
                        Text(Insights.slotLabel(s.key) + "   " + Fmt.f("$%.0f/hr", s.perHr) + "   (" + Fmt.f("%.1f", s.minutes / 60.0) + " h)")
                            .font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.text)
                    }
                }
                Caption("Income is the accepted-offer estimate plus what you log, divided by online time.")
            }
            .card()

            VStack(alignment: .leading, spacing: 8) {
                Text("Your hotspots").font(.headline).foregroundColor(Theme.text)
                if hot.isEmpty { Caption("Needs accepted offers recorded while a shift is running (GPS).") }
                ForEach(hot) { h in
                    BigButton(title: "\(h.count) accepted · avg \(Finance.money(h.avgPay)) · open in Maps") {
                        if let u = URL(string: "http://maps.apple.com/?ll=\(h.lat),\(h.lon)&q=Hotspot") { openURL(u) }
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 6) {
                Text("Goals").font(.headline).foregroundColor(Theme.text)
                if gd > 0 {
                    Caption("Today: \(Finance.money(td.income)) of \(Finance.money(gd))")
                    Bar(fraction: td.income / gd)
                } else { Caption("Set a daily goal in Settings.") }
                if gw > 0 {
                    Caption("This week: \(Finance.money(wk)) of \(Finance.money(gw))")
                    Bar(fraction: wk / gw, color: Theme.blue)
                } else { Caption("Set a weekly goal in Settings.") }
            }
            .card()
        }
    }
}

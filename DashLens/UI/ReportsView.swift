import SwiftUI

struct ReportsView: View {
    @EnvironmentObject var app: AppState
    @State private var periodIdx = 0
    @State private var anchor = LDate.today()
    @State private var saved: [URL] = []
    @State private var message = ""

    private var period: Period { Period.allCases[periodIdx] }

    var body: some View {
        let _ = app.rev
        let r = Reports.build(period, anchor)
        let t = r.totals
        let rate = Prefs.num("irs_rate")
        Screen(title: "Reports") {
            Chips(items: Period.allCases.map { $0.rawValue }, selection: $periodIdx)
            NavRow(title: r.title, prev: { anchor = Reports.shift(period, anchor, -1) }, next: { anchor = Reports.shift(period, anchor, 1) })

            VStack(alignment: .leading, spacing: 8) {
                Caption("On order")
                Text("\(Reports.mi(t.orderM)) mi   \(Reports.dur(t.orderMs))").font(.title3.bold()).foregroundColor(Theme.text)
                Caption("Online, between orders")
                Text("\(Reports.mi(t.idleM)) mi   \(Reports.dur(t.idleMs))").font(.title3.bold()).foregroundColor(Theme.text)
                Caption("Online total (includes on-order)")
                Text("\(Reports.mi(t.onlineM)) mi   \(Reports.dur(t.onlineMs))").font(.title3.bold()).foregroundColor(Theme.text)
                let dedOrder = Fmt.f("$%.2f", t.orderM / 1609.344 * rate)
                let dedOnline = Fmt.f("$%.2f", t.onlineM / 1609.344 * rate)
                Caption(cat("Est. deduction at $\(Prefs.fmt(rate))/mi:  on-order ", dedOrder, "  |  all online ", dedOnline,
                            ". Estimate only. Ask a tax professional which miles you can claim."))
            }
            .card()

            MoneyCardView(from: r.from, toExcl: r.toExcl)

            VStack(alignment: .leading, spacing: 4) {
                Text((period == .year ? "Month" : "Day") + "      order mi/h    online mi/h")
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(Theme.text)
                let prefix = "\(r.from.year)-"
                ForEach(r.rows, id: \.key) { d in
                    let key = d.key.hasPrefix(prefix) ? String(d.key.dropFirst(prefix.count)) : d.key
                    let totalM = d.orderM + d.idleM
                    let totalMs = d.orderMs + d.idleMs
                    let line = cat(key.padR(8), Reports.mi(d.orderM).padL(6), " ", Reports.hrs(d.orderMs).padL(5), "   ",
                                   Reports.mi(totalM).padL(6), " ", Reports.hrs(totalMs).padL(5))
                    Text(line)
                        .font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.text)
                }
            }
            .card()

            BigButton(title: "Save CSV + trip log + text to Files", prominent: true) {
                let base = "DashLens_\(period.rawValue.lowercased())_\(r.from.description)"
                saved = Exporter.saveReport(r, base: base)
                message = saved.isEmpty ? "Could not save." : "Saved \(saved.count) files. Open Files > On My iPhone > DashLens."
            }
            if !message.isEmpty { Text(message).font(.footnote.weight(.semibold)).foregroundColor(Theme.amber) }
            if !saved.isEmpty {
                ShareLink(items: saved) {
                    Text("Share the saved files").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundColor(Theme.text).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
                }
            }
            ShareLink(item: Reports.text(r), subject: Text(r.title)) {
                Text("Share summary text").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .foregroundColor(Theme.text).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
            }
            Caption("Miles come from GPS and can differ slightly from your odometer. Keep your Jan 1 and Dec 31 odometer readings for your return.")
        }
    }
}

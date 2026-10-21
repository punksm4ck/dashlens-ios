import SwiftUI
import PhotosUI
import CoreLocation

struct TestResult: Identifiable {
    let id = UUID()
    let outcome: OfferEngine.Outcome
}

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var tracker = Tracker.shared
    @Environment(\.openURL) private var openURL

    @State private var notifOK = true
    @State private var message = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var testResult: TestResult?
    @State private var showSetup = false
    @State private var showSample = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 5)) { _ in
            content
        }
        .sheet(isPresented: $showSetup) { OfferSetupView() }
        .sheet(isPresented: $showSample) { SampleCardView() }
        .sheet(item: $testResult) { r in TestResultView(outcome: r.outcome) }
        .onAppear { Notifier.status { notifOK = $0 } }
        .onChange(of: pickerItem) { _, item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    let lines = await Task.detached(priority: .userInitiated) { OfferEngine.recognize(img) }.value
                    let out = OfferEngine.process(lines: lines, log: false)
                    testResult = TestResult(outcome: out)
                }
                pickerItem = nil
            }
        }
    }

    private func settingsURL() {
        if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
    }

    private func check(_ label: String, _ ok: Bool, _ fix: String, _ action: @escaping () -> Void) -> some View {
        HStack {
            Text(ok ? "✓" : "✕").font(.headline).foregroundColor(ok ? Theme.green : Theme.red)
            Text(label).font(.subheadline).foregroundColor(Theme.text)
            Spacer()
            if !ok {
                Button(fix, action: action).font(.caption.weight(.semibold)).buttonStyle(.bordered)
            }
        }
    }

    private func toggleShift() {
        if tracker.running {
            message = ShiftActions.stop()
        } else if !tracker.hasLocation {
            tracker.askLocation()
            message = "Allow location, then tap Start shift again."
        } else {
            message = ShiftActions.start()
        }
    }

    @ViewBuilder private var content: some View {
        let _ = app.rev
        let td = Finance.today()
        let t = Database.shared.totals(LDate.today().startMs, nowMs())
        let goal = Prefs.num("goal_day")
        let now = nowMs()
        let last = Database.shared.offers(now - 24 * 3_600_000, now + 1000, limit: 1).first

        Screen(title: "DashLens") {
            Caption("Offer analyzer · mileage · earnings · taxes")

            if !(tracker.hasAlways && notifOK) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Finish setup").font(.headline).foregroundColor(Theme.text)
                    check("Location: Always", tracker.hasAlways, tracker.hasLocation ? "Open" : "Allow") {
                        if tracker.hasLocation { settingsURL() } else { tracker.askLocation() }
                    }
                    check("Notifications", notifOK, "Allow") { Notifier.requestAuth(); settingsURL() }
                    Caption("Always is what lets mileage keep logging while Dasher is on screen and your phone is locked.")
                }
                .card()
            }

            // shift card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Pill(text: tracker.running ? "ON SHIFT" : "NOT TRACKING", color: tracker.running ? Theme.green : Theme.muted)
                    Text(tracker.running ? tracker.state.label : (tracker.hasLocation ? "Tap Start shift when you go online" : "Location permission needed"))
                        .font(.caption).foregroundColor(Theme.muted)
                }
                HStack {
                    StatTile(label: "Est. income", value: Finance.money(td.income))
                    StatTile(label: "Accepted", value: "\(td.accepted)")
                    StatTile(label: "$ / hr online",
                             value: (td.onlineMs > 0 && td.income > 0) ? Fmt.f("$%.0f", td.perHour) : "-",
                             color: td.income > 0 ? Theme.green : Theme.muted)
                }
                HStack {
                    StatTile(label: "Online mi", value: Reports.mi(t.onlineM))
                    StatTile(label: "On-order mi", value: Reports.mi(t.orderM))
                    StatTile(label: "Online time", value: Reports.dur(t.onlineMs))
                }
                if goal > 0 {
                    Caption("Daily goal: \(Finance.money(td.income)) of \(Finance.money(goal)) (\(Fmt.f("%.0f", td.income / goal * 100.0))%)")
                    Bar(fraction: td.income / goal)
                }
                BigButton(title: tracker.running ? "Stop shift" : "Start shift", prominent: true,
                          tint: tracker.running ? Theme.red : Theme.green) { toggleShift() }
                HStack(spacing: 8) {
                    BigButton(title: "Online") { if tracker.running { tracker.setState(.online) } else { message = "Tap Start shift first." } }
                    BigButton(title: "On order") { if tracker.running { message = ShiftActions.accepted() } else { message = "Tap Start shift first." } }
                    BigButton(title: "Pause") { if tracker.running { tracker.setState(.offline) } else { message = "Tap Start shift first." } }
                }
                Caption("iPhone can't see the Dasher screen, so tell DashLens when you accept (On order) and when the order is done (Online). Back Tap can do this for you: see Offer card setup.")
                if !message.isEmpty { Text(message).font(.footnote.weight(.semibold)).foregroundColor(Theme.amber) }
            }
            .card()

            // last offer
            VStack(alignment: .leading, spacing: 8) {
                Text("Last offer").font(.headline).foregroundColor(Theme.text)
                if let o = last {
                    HStack {
                        Pill(text: o.verdict, color: Theme.verdictColor(o.verdict))
                        Text(o.merchant.isEmpty ? "Offer" : o.merchant).font(.subheadline.weight(.bold)).foregroundColor(Theme.text)
                    }
                    Text(Fmt.f("$%.2f · %.1f mi · about $%.0f/hr net · ", o.pay, o.miles, o.netHr) + o.outcome.lowercased())
                        .font(.footnote).foregroundColor(Theme.muted)
                    if o.outcome == "PENDING" {
                        HStack(spacing: 8) {
                            BigButton(title: "I accepted it") { message = ShiftActions.accepted() }
                            BigButton(title: "I passed") { message = ShiftActions.passed() }
                        }
                    }
                } else {
                    Caption("Nothing yet today. With a Dasher offer on screen, trigger your DashLens shortcut (Back Tap or Action Button) to get the card.")
                }
            }
            .card()

            BigButton(title: "Offer card setup (Back Tap / Action Button)", prominent: true, tint: Theme.blue) { showSetup = true }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text("Test with a saved Dasher screenshot")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(Theme.text)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
            }
            BigButton(title: "Preview the offer card") { showSample = true }

            NavigationLink {
                ReportsView()
            } label: {
                Text("Mileage reports (week / month / year)")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(Theme.text)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
            }
        }
    }
}

struct SampleCardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = OfferEngine.sample()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    OfferCardView(offer: s.0, analysis: s.1)
                    Caption("A sample offer, so you can check how the card looks with your settings. It is not saved to your history.")
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Sample card")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct TestResultView: View {
    let outcome: OfferEngine.Outcome
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    OfferCardView(offer: outcome.offer, analysis: outcome.analysis, message: Prefs.str("parse_status"))
                    Caption("This was a test: nothing was added to your offer history.")
                    Text("Text DashLens read from the screenshot").font(.headline).foregroundColor(Theme.text)
                    Text(outcome.lines.isEmpty ? "(no text found)" : outcome.lines.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.muted)
                        .textSelection(.enabled)
                    BigButton(title: "Copy text") { UIPasteboard.general.string = outcome.lines.joined(separator: " | ") }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Screenshot test")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

/// How to wire the screenshot shortcut to Back Tap or the Action Button.
struct OfferSetupView: View {
    @Environment(\.dismiss) private var dismiss

    private func step(_ n: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).foregroundColor(Color.black)
                .frame(width: 28, height: 28).background(Circle().fill(Theme.green))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.bold)).foregroundColor(Theme.text)
                Text(body).font(.footnote).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("On iPhone, DashLens can't draw on top of Dasher. Instead you take a screenshot of the offer and DashLens reads it on the phone and shows the verdict. One tap does both.")
                        .font(.subheadline).foregroundColor(Theme.text)
                    step(1, "Make the shortcut", "Shortcuts app > + > add \"Take Screenshot\", then add \"Analyze Dasher Offer\" (search DashLens) and drop the screenshot into its Screenshot box. Name it \"Dash Check\".")
                    step(2, "Back Tap", "Settings > Accessibility > Touch > Back Tap > Double Tap > choose Dash Check. Optional: Triple Tap > \"I Accepted the Offer\" (a DashLens action).")
                    step(3, "Or the Action Button", "On iPhone 15 Pro and newer: Settings > Action Button > Shortcut > Dash Check.")
                    step(4, "Try it", "Use \"Test with a saved Dasher screenshot\" on the Home screen first. Then try it on a real offer: the verdict card pops up over Dasher in a couple of seconds.")
                    Caption("Offers expire quickly. If the card arrives too late for you, use the Triple Tap / Action Button for \"I Accepted the Offer\" only when you accept, and let DashLens log offers you analyze.")
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Offer card setup")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

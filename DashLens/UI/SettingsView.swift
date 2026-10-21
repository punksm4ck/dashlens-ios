import SwiftUI
import PhotosUI

final class SettingsModel: ObservableObject {
    @Published var texts: [String: String] = [:]
    @Published var flags: [String: Bool] = [:]

    init() { reload() }

    func reload() {
        for f in Prefs.fields { texts[f.key] = Prefs.fmt(Prefs.num(f.key)) }
        for s in Prefs.switches { flags[s.key] = Prefs.bool(s.key, s.def) }
    }

    func text(_ key: String) -> Binding<String> {
        Binding(get: { self.texts[key] ?? "" }, set: { v in
            self.texts[key] = v
            if let d = Double(v.replacingOccurrences(of: ",", with: ".")) {
                Prefs.setNum(key, d)
                Calibration.reset()
            }
        })
    }

    func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { self.flags[key] ?? false }, set: { v in
            self.flags[key] = v
            Prefs.setBool(key, v)
            Calibration.reset()
            NotificationCenter.default.post(name: .dashLensDataChanged, object: nil)
        })
    }

    func preset(_ hr: Double, _ mi: Double) {
        Prefs.setNum("min_hr", hr)
        Prefs.setNum("min_mi", mi)
        reload()
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @State private var showSample = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var testResult: TestResult?
    @State private var diag = ""
    @State private var presetMsg = ""

    private var groups: [String] {
        var out: [String] = []
        for f in Prefs.fields where !out.contains(f.group) { out.append(f.group) }
        return out
    }

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    }

    var body: some View {
        Screen(title: "Settings") {
            VStack(alignment: .leading, spacing: 8) {
                Text("How picky should DashLens be?").font(.headline).foregroundColor(Theme.text)
                Caption("Quick profiles set the two minimums. You can fine-tune everything below.")
                HStack(spacing: 8) {
                    BigButton(title: "Strict") { model.preset(22, 1.75); presetMsg = "Strict: min $22/hr and $1.75 per real mile" }
                    BigButton(title: "Balanced") { model.preset(18, 1.25); presetMsg = "Balanced: min $18/hr and $1.25 per real mile" }
                    BigButton(title: "Easygoing") { model.preset(14, 1.0); presetMsg = "Easygoing: min $14/hr and $1.00 per real mile" }
                }
                if !presetMsg.isEmpty { Caption(presetMsg) }
            }
            .card()

            ForEach(groups, id: \.self) { g in
                VStack(alignment: .leading, spacing: 4) {
                    Text(g).font(.headline).foregroundColor(Theme.text)
                    ForEach(Prefs.fields.filter { $0.group == g }, id: \.key) { f in
                        Caption(f.label).padding(.top, 8)
                        TextField("", text: model.text(f.key))
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .card()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Options").font(.headline).foregroundColor(Theme.text)
                ForEach(Prefs.switches, id: \.key) { s in
                    Toggle(s.label, isOn: model.flag(s.key)).font(.subheadline).foregroundColor(Theme.text)
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnostics").font(.headline).foregroundColor(Theme.text)
                Caption("If the offer card is wrong, copy the text DashLens read and send it to whoever is tuning the app.")
                BigButton(title: "Preview the offer card") { showSample = true }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text("Test with a saved Dasher screenshot").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 12).foregroundColor(Theme.text)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
                }
                let ps = Prefs.str("parse_status")
                Text("Last offer read: " + (ps.isEmpty ? "no offer seen yet" : ps))
                    .font(.footnote.weight(.bold))
                    .foregroundColor(ps.hasPrefix("OK") ? Theme.green : (ps.hasPrefix("FAILED") ? Theme.red : Theme.muted))
                let dump = Prefs.str("last_dump")
                Caption("Last text read from a screenshot")
                Text(dump.isEmpty ? "(nothing read yet)" : dump).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.muted)
                BigButton(title: "Copy screenshot text") {
                    UIPasteboard.general.string = Prefs.str("last_dump")
                    diag = "Copied."
                }
                if !diag.isEmpty { Caption(diag) }
            }
            .card()

            VStack(alignment: .leading, spacing: 8) {
                Text("About DashLens").font(.headline).foregroundColor(Theme.text)
                Caption("Version \(version)")
                Text("Everything stays on this phone: DashLens has no account and no servers, and nothing is uploaded. It never reads the Dasher app live: it only reads screenshots you choose to run through it, on the phone. It is not affiliated with or endorsed by DoorDash. Earnings and tax figures are estimates, not tax advice.")
                    .font(.footnote).foregroundColor(Theme.muted)
                BigButton(title: "Replay the setup guide") { Prefs.setBool("onboarded", false); UserDefaults.standard.synchronize() }
            }
            .card()
        }
        .sheet(isPresented: $showSample) { SampleCardView() }
        .sheet(item: $testResult) { r in TestResultView(outcome: r.outcome) }
        .onChange(of: pickerItem) { _, item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    let lines = await Task.detached(priority: .userInitiated) { OfferEngine.recognize(img) }.value
                    testResult = TestResult(outcome: OfferEngine.process(lines: lines, log: false))
                }
                pickerItem = nil
            }
        }
    }
}

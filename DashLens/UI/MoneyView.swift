import SwiftUI
import PhotosUI

struct MoneyCardView: View {
    let from: LDate
    let toExcl: LDate

    var body: some View {
        let p = Finance.pnl(from, toExcl)
        let manualOnly = Prefs.bool("income_manual_only", false)
        VStack(alignment: .leading, spacing: 4) {
            Text("Profit (estimates)").font(.headline).foregroundColor(Theme.text)
            KV(label: "Income", value: Finance.money(p.income),
               note: manualOnly ? "logged by hand only"
               : "\(Finance.money(p.offerIncome)) from \(p.offerCount) accepted offers + \(Finance.money(p.manualIncome)) logged")
            if p.actualMethod {
                KV(label: "Vehicle + other expenses", value: Finance.money(p.expenseDeduction),
                   note: "actual-expense method, \(Fmt.f("%.0f", p.bizPct))% business use")
            } else {
                KV(label: "Mileage deduction", value: Finance.money(p.mileageDeduction),
                   note: Fmt.f("%.1f mi at $", p.miles) + Prefs.fmt(Prefs.num("irs_rate")) + " per mile")
                KV(label: "Other expenses", value: Finance.money(p.expenseDeduction), note: "tolls, parking, phone, supplies")
            }
            KV(label: "Net profit", value: Finance.money(p.net), color: p.net >= 0 ? Theme.green : Theme.red)
            KV(label: "Tax set-aside", value: Finance.money(Finance.setAside(p.net)), color: Theme.amber,
               note: "self-employment tax plus your income-tax %, rough")
            if !p.expenses.isEmpty {
                Caption("Logged expenses by category").padding(.top, 6)
                ForEach(p.expenses, id: \.cat) { e in KV(label: e.cat, value: Finance.money(e.total)) }
            }
            let hint = Finance.taxHint()
            if !hint.isEmpty { Text(hint).font(.footnote).foregroundColor(Theme.amber).padding(.top, 6) }
            Caption("Estimates only. Not tax advice. Confirm with a tax professional.").padding(.top, 6)
        }
        .card()
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

private func stamp(_ d: Date) -> Int64 {
    let l = LDate(date: d)
    if l == LDate.today() { return nowMs() }
    let noon = LDate.cal.date(bySettingHour: 12, minute: 0, second: 0, of: l.date) ?? l.date
    return Int64(noon.timeIntervalSince1970 * 1000.0)
}

struct AddEarningView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var kind = Finance.kinds[0]
    @State private var platform = "DoorDash"
    @State private var date = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount $", text: $amount).keyboardType(.decimalPad)
                Picker("Type", selection: $kind) { ForEach(Finance.kinds, id: \.self) { Text($0).tag($0) } }
                TextField("Platform", text: $platform)
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle("Add earning")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let a = Double(amount.replacingOccurrences(of: ",", with: ".")) {
                            let p = platform.trimmingCharacters(in: .whitespaces)
                            Database.shared.insertEarning(stamp(date), a, p.isEmpty ? "DoorDash" : p, kind,
                                                          note.trimmingCharacters(in: .whitespaces))
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

struct AddExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var category = Finance.cats[0]
    @State private var date = Date()
    @State private var note = ""
    @State private var receipt = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false

    private func saveReceipt(_ img: UIImage) {
        guard let data = img.jpegData(compressionQuality: 0.8) else { return }
        let name = "receipt_\(nowMs()).jpg"
        let url = Exporter.receiptsDir().appendingPathComponent(name)
        if (try? data.write(to: url)) != nil { receipt = name }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount $", text: $amount).keyboardType(.decimalPad)
                Picker("Category", selection: $category) { ForEach(Finance.cats, id: \.self) { Text($0).tag($0) } }
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                TextField("Note (optional)", text: $note)
                Section("Receipt") {
                    Button("Take photo") { showCamera = true }
                    PhotosPicker("Pick photo", selection: $photoItem, matching: .images)
                    Text(receipt.isEmpty ? "No receipt attached" : "Receipt attached").foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add expense")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let a = Double(amount.replacingOccurrences(of: ",", with: ".")) {
                            Database.shared.insertExpense(stamp(date), a, category, note.trimmingCharacters(in: .whitespaces), receipt)
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showCamera) { CameraPicker { saveReceipt($0) } }
            .onChange(of: photoItem) { _, item in
                guard let item = item else { return }
                Task {
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { saveReceipt(img) }
                }
            }
        }
    }
}

struct ReceiptView: View {
    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let path = Exporter.receiptsDir().appendingPathComponent(name).path
            ScrollView {
                if let img = UIImage(contentsOfFile: path) {
                    Image(uiImage: img).resizable().scaledToFit().padding()
                } else {
                    Text("Receipt file not found.").foregroundColor(Theme.muted).padding()
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Receipt")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct MoneyView: View {
    @EnvironmentObject var app: AppState
    @State private var sub = 0
    @State private var anchor = LDate.today()
    @State private var showAddEarning = false
    @State private var showAddExpense = false
    @State private var receiptName: String?
    @State private var odoStart = ""
    @State private var odoEnd = ""

    var body: some View {
        let _ = app.rev
        Screen(title: "Money") {
            Chips(items: ["Earnings", "Expenses", "Tax"], selection: $sub)
            NavRow(title: sub == 2 ? "Tax year \(anchor.year)" : anchor.firstOfMonth().format("MMMM yyyy"),
                   prev: { anchor = sub == 2 ? anchor.plusYears(-1) : anchor.plusMonths(-1) },
                   next: { anchor = sub == 2 ? anchor.plusYears(1) : anchor.plusMonths(1) })
            switch sub {
            case 0: earnings
            case 1: expenses
            default: tax
            }
        }
        .sheet(isPresented: $showAddEarning) { AddEarningView() }
        .sheet(isPresented: $showAddExpense) { AddExpenseView() }
        .sheet(item: Binding(get: { receiptName.map { Identifiable_String(id: $0) } }, set: { receiptName = $0?.id })) { r in
            ReceiptView(name: r.id)
        }
        .onChange(of: sub) { _, _ in loadOdo() }
        .onChange(of: anchor) { _, _ in loadOdo() }
        .onAppear { loadOdo() }
    }

    private func loadOdo() {
        odoStart = Prefs.str("odo_start_\(anchor.year)")
        odoEnd = Prefs.str("odo_end_\(anchor.year)")
    }

    // MARK: earnings

    @ViewBuilder private var earnings: some View {
        let from = anchor.firstOfMonth()
        let to = from.plusMonths(1)
        let db = Database.shared
        let list = db.earnings(from.startMs, to.startMs)
        let acc = db.acceptedPay(from.startMs, to.startMs)
        VStack(alignment: .leading, spacing: 6) {
            Caption("Logged by hand")
            Text(Finance.money(list.reduce(0) { $0 + $1.amount })).font(.title2.bold()).foregroundColor(Theme.text)
            Caption("Accepted offers (estimate from analyzed offers)")
            Text("\(Finance.money(acc.0))  (\(acc.1) offers)").font(.headline).foregroundColor(Theme.text)
            Caption("Offer pay may leave out part of the tip. Log the actual payout or any extra (cash tips, bonuses, promos) here. Turn on \"Income = only what I log by hand\" in Settings if you log full payouts.")
        }
        .card()
        BigButton(title: "+ Add earning", prominent: true) { showAddEarning = true }
        ForEach(list) { e in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Fmt.ms(e.ts, "MMM d")).font(.footnote).foregroundColor(Theme.muted)
                    Text(Finance.money(e.amount)).font(.subheadline.weight(.bold)).foregroundColor(Theme.text)
                    Spacer()
                    Text("\(e.kind) / \(e.platform)").font(.footnote).foregroundColor(Theme.muted)
                }
                if !e.note.isEmpty { Caption(e.note) }
            }
            .card()
            .contextMenu {
                Button("Delete", role: .destructive) { Database.shared.deleteEarning(e.id) }
            }
        }
        if !list.isEmpty { Caption("Press and hold an entry to delete it.") }
    }

    // MARK: expenses

    @ViewBuilder private var expenses: some View {
        let from = anchor.firstOfMonth()
        let to = from.plusMonths(1)
        let db = Database.shared
        let list = db.expenses(from.startMs, to.startMs)
        VStack(alignment: .leading, spacing: 4) {
            Caption("Total this month")
            Text(Finance.money(list.reduce(0) { $0 + $1.amount })).font(.title2.bold()).foregroundColor(Theme.text)
            ForEach(db.expenseByCat(from.startMs, to.startMs), id: \.cat) { c in
                Text(c.cat.padR(12) + " " + Finance.money(c.total)).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.text)
            }
            if let ac = Finance.actualCostPerMile() {
                Caption("Your actual gas + maintenance cost: \(Finance.money(ac)) per tracked mile (last 90 days). Compare with the cost-per-mile setting.")
            } else {
                Caption("Log gas and maintenance and track 100+ miles to see your actual cost per mile.")
            }
        }
        .card()
        BigButton(title: "+ Add expense", prominent: true) { showAddExpense = true }
        ForEach(list) { e in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Fmt.ms(e.ts, "MMM d")).font(.footnote).foregroundColor(Theme.muted)
                    Text(Finance.money(e.amount)).font(.subheadline.weight(.bold)).foregroundColor(Theme.text)
                    Spacer()
                    Text(e.category + (e.receipt.isEmpty ? "" : "  [receipt]")).font(.footnote).foregroundColor(Theme.muted)
                }
                if !e.note.isEmpty { Caption(e.note) }
            }
            .card()
            .onTapGesture { if !e.receipt.isEmpty { receiptName = e.receipt } }
            .contextMenu {
                Button("Delete", role: .destructive) { Database.shared.deleteExpense(e.id) }
            }
        }
        if !list.isEmpty { Caption("Tap an entry to open its receipt. Press and hold to delete.") }
    }

    // MARK: tax

    @ViewBuilder private var tax: some View {
        let y = anchor.year
        MoneyCardView(from: LDate(y, 1, 1), toExcl: LDate(y + 1, 1, 1))
        VStack(alignment: .leading, spacing: 6) {
            Text("Quarterly estimated-tax periods").font(.headline).foregroundColor(Theme.text)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(Finance.quartersText(y)).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.text)
            }
            let methodText = Prefs.bool("method_actual", false) ? "actual vehicle expenses" : "standard mileage rate"
            let basisText = Prefs.bool("basis_online", false) ? "all online miles" : "on-order miles"
            Caption(cat("Due dates move to the next business day when they land on a weekend; holidays are not accounted for. Method in use: ",
                        methodText, ", miles basis: ", basisText,
                        ". Change these in Settings. Under the standard rate, gas, maintenance, car washes and insurance are not deducted again; tolls and parking still are."))
        }
        .card()
        VStack(alignment: .leading, spacing: 8) {
            Text("Odometer log for \(y)").font(.headline).foregroundColor(Theme.text)
            TextField("Odometer on Jan 1 \(y)", text: $odoStart).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            TextField("Odometer on Dec 31 \(y)", text: $odoEnd).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            BigButton(title: "Save odometer") {
                Prefs.setStr("odo_start_\(y)", odoStart.trimmingCharacters(in: .whitespaces))
                Prefs.setStr("odo_end_\(y)", odoEnd.trimmingCharacters(in: .whitespaces))
                NotificationCenter.default.post(name: .dashLensDataChanged, object: nil)
            }
            if let s = Double(odoStart), let e = Double(odoEnd), e > s {
                Caption("Total miles driven: \(Fmt.f("%.0f", e - s)). Business share from tracked miles: \(Fmt.f("%.1f", Finance.bizPct(y)))%.")
            } else {
                Caption("Enter both readings to get your business-use % from the odometer (the tax form asks for total miles).")
            }
        }
        .card()
    }
}

struct Identifiable_String: Identifiable {
    let id: String
}

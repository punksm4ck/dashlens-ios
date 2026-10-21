import SwiftUI

struct OnboardingView: View {
    let done: () -> Void
    @ObservedObject private var tracker = Tracker.shared

    private func bullet(_ s: String) -> some View {
        Text("•  " + s).font(.subheadline).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome to DashLens").font(.largeTitle.bold()).foregroundColor(Theme.text)
                Text("Know in a glance whether an offer is worth your time, and keep your miles, earnings and tax numbers.")
                    .foregroundColor(Theme.muted)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What you get").font(.headline).foregroundColor(Theme.text)
                    bullet("A TAKE / MAYBE / DECLINE card for an offer, with your real net $/hr and $/mile")
                    bullet("It learns your true order times and each merchant's history from your own shifts")
                    bullet("GPS mileage and time log, earnings, expenses with receipts and a tax set-aside")
                    bullet("Best hours and hotspots from your own data")
                }
                .card()

                VStack(alignment: .leading, spacing: 6) {
                    Text("How the offer card works on iPhone").font(.headline).foregroundColor(Theme.amber)
                    Text("iPhone does not let one app read or draw over another app, so DashLens can't watch Dasher live. Instead, you trigger a shortcut (Back Tap or the Action Button) while an offer is on screen. It takes a screenshot, DashLens reads it on the phone, and the verdict card appears.")
                        .font(.subheadline).foregroundColor(Theme.text)
                    bullet("Only screenshots you trigger are read. Nothing is uploaded.")
                    bullet("It never taps, accepts or declines anything for you.")
                    bullet("You tell DashLens when you accept an offer and when an order is done (one tap, or Back Tap), so it can log miles per order.")
                }
                .card()

                Text("Earnings, mileage deduction and tax figures are estimates to help you plan, not tax advice. DashLens is an independent app and is not affiliated with or endorsed by DoorDash.")
                    .font(.caption).foregroundColor(Theme.muted)

                BigButton(title: "Allow location and notifications", prominent: true) {
                    tracker.askLocation()
                    Notifier.requestAuth()
                }
                Caption("Choose \"Allow While Using\" first, then \"Change to Always Allow\" when iOS asks. Always lets miles keep logging while Dasher is on screen.")
                BigButton(title: "I understand. Open DashLens", prominent: true, tint: Theme.blue) { done() }
            }
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

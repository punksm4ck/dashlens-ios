import AppIntents
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The core action. In Shortcuts: "Take Screenshot" -> "Analyze Dasher Offer". Put that shortcut on Back Tap or the Action Button.
struct AnalyzeOfferIntent: AppIntent {
    static let title: LocalizedStringResource = "Analyze Dasher Offer"
    static let description = IntentDescription("Reads a screenshot of a Dasher offer on this iPhone and tells you TAKE, MAYBE or DECLINE. Nothing leaves your phone.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Screenshot")
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Analyze the offer in \(\.$screenshot)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let data = screenshot.data
        let outcome: OfferEngine.Outcome = await Task.detached(priority: .userInitiated) { () -> OfferEngine.Outcome in
            guard let img = UIImage(data: data) else {
                return OfferEngine.process(lines: [], log: false)
            }
            let lines = OfferEngine.recognize(img)
            return OfferEngine.process(lines: lines, log: true)
        }.value

        if let o = outcome.offer, let a = outcome.analysis {
            Feedback.run(a, o)
            let text = OfferEngine.spokenLine(o, a)
            return .result(value: text, dialog: "\(text)", view: OfferCardView(offer: o, analysis: a))
        }
        let msg = "Couldn't read an offer on that screenshot. Run it while the Dasher offer is on screen."
        return .result(value: "NO OFFER", dialog: "\(msg)", view: OfferCardView(offer: nil, analysis: nil, message: msg))
    }
}

struct StartShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Shift"
    static let description = IntentDescription("Starts DashLens mileage and time logging.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = ShiftActions.start()
        return .result(dialog: "\(msg)")
    }
}

struct StopShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Shift"
    static let description = IntentDescription("Stops DashLens mileage and time logging.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = ShiftActions.stop()
        return .result(dialog: "\(msg)")
    }
}

struct AcceptedOfferIntent: AppIntent {
    static let title: LocalizedStringResource = "I Accepted the Offer"
    static let description = IntentDescription("Marks the last analyzed offer as accepted and switches the shift to On order.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = ShiftActions.accepted()
        return .result(dialog: "\(msg)")
    }
}

struct PassedOfferIntent: AppIntent {
    static let title: LocalizedStringResource = "I Passed on the Offer"
    static let description = IntentDescription("Marks the last analyzed offer as passed.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = ShiftActions.passed()
        return .result(dialog: "\(msg)")
    }
}

struct OrderDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Order Done"
    static let description = IntentDescription("Ends the on-order stretch and goes back to Online. DashLens uses it to learn your real order times.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let msg = ShiftActions.orderDone()
        return .result(dialog: "\(msg)")
    }
}

struct TodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Numbers"
    static let description = IntentDescription("Today's estimated income, accepted offers, online time and miles.")
    static let openAppWhenRun: Bool = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let line = ShiftActions.todayLine()
        return .result(value: line, dialog: "\(line)")
    }
}

struct DashLensShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartShiftIntent(),
                    phrases: ["Start a shift in \(.applicationName)"],
                    shortTitle: "Start shift", systemImageName: "play.fill")
        AppShortcut(intent: StopShiftIntent(),
                    phrases: ["Stop my shift in \(.applicationName)"],
                    shortTitle: "Stop shift", systemImageName: "stop.fill")
        AppShortcut(intent: AcceptedOfferIntent(),
                    phrases: ["I accepted the offer in \(.applicationName)"],
                    shortTitle: "Accepted offer", systemImageName: "checkmark.circle.fill")
        AppShortcut(intent: PassedOfferIntent(),
                    phrases: ["I passed the offer in \(.applicationName)"],
                    shortTitle: "Passed offer", systemImageName: "xmark.circle.fill")
        AppShortcut(intent: OrderDoneIntent(),
                    phrases: ["Order done in \(.applicationName)"],
                    shortTitle: "Order done", systemImageName: "flag.checkered")
        AppShortcut(intent: TodayIntent(),
                    phrases: ["Today's numbers in \(.applicationName)"],
                    shortTitle: "Today", systemImageName: "dollarsign.circle")
    }
}

import SwiftUI
import UserNotifications

@main
struct DashLensApp: App {
    @Environment(\.scenePhase) private var phase
    @StateObject private var app = AppState.shared

    init() {
        // If iOS relaunched the app in the middle of a shift (after a memory kill), pick the shift back up.
        Tracker.shared.restore()
        UNUserNotificationCenter.current().delegate = NotifDelegate.shared
        LiveReceiver.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active {
                Tracker.shared.restore()
                OfferLog.resolveStale()
                Summaries.catchUp()
                Notifier.scheduleWeekly()
                LiveReceiver.shared.start()
            } else if newPhase == .background {
                Tracker.shared.flush()
            }
        }
    }
}

struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        if onboarded {
            MainTabs()
        } else {
            OnboardingView { onboarded = true }
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { OffersView() }
                .tabItem { Label("Offers", systemImage: "list.bullet.rectangle") }
            NavigationStack { MoneyView() }
                .tabItem { Label("Money", systemImage: "dollarsign.circle") }
            NavigationStack { InsightsView() }
                .tabItem { Label("Insights", systemImage: "chart.bar") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.green)
    }
}

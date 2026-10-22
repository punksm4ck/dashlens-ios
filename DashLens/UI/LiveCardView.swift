import SwiftUI
import ReplayKit
import UIKit

/// Holds the system broadcast picker so an ordinary button can open it.
final class PickerBox {
    var view: RPSystemBroadcastPickerView?

    func open() {
        guard let v = view else { return }
        for s in v.subviews {
            if let b = s as? UIButton {
                b.sendActions(for: .touchUpInside)
                return
            }
        }
    }
}

struct BroadcastPicker: UIViewRepresentable {
    let box: PickerBox

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        v.preferredExtension = "app.dashlens.broadcast"
        v.showsMicrophoneButton = false
        box.view = v
        return v
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        box.view = uiView
    }
}

/// Home card: starts a shift and the DashLens Live broadcast in one tap.
struct LiveCard: View {
    @ObservedObject private var tracker = Tracker.shared
    @State private var box = PickerBox()
    @State private var message = ""

    private var capturing: Bool { UIScreen.main.isCaptured }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live detection (beta)").font(.headline).foregroundColor(Theme.text)
                Spacer()
                Pill(text: capturing ? "ON" : "OFF", color: capturing ? Theme.green : Theme.muted)
            }
            Caption("DashLens watches the Dasher screen during your shift and shows the verdict as a banner the moment an offer appears, with no taps. iPhone shows a red recording indicator while it runs.")
            ZStack {
                BigButton(title: capturing ? "Live detection is running" : "Start shift + live detection",
                          prominent: !capturing, tint: Theme.green) { startLive() }
                BroadcastPicker(box: box)
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .allowsHitTesting(false)
            }
            if !message.isEmpty { Text(message).font(.footnote.weight(.semibold)).foregroundColor(Theme.amber) }
            Caption("In the list that opens, choose DashLens Live and tap Start Broadcast. To stop, tap the red recording indicator, then Stop Broadcast.")
        }
        .card()
    }

    private func startLive() {
        if !Tracker.shared.running {
            let m = ShiftActions.start()
            if !Tracker.shared.running {
                message = m
                return
            }
        }
        message = ""
        LiveReceiver.shared.start()
        box.open()
    }
}

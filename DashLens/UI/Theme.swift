import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: opacity)
    }
}

enum Theme {
    static let bg = Color(hex: 0x0E1116)
    static let surface = Color(hex: 0x171B22)
    static let text = Color(hex: 0xE8EAED)
    static let muted = Color(hex: 0x9AA0A6)
    static let green = Color(hex: 0x2ECC71)
    static let amber = Color(hex: 0xFFB300)
    static let red = Color(hex: 0xFF4D4D)
    static let blue = Color(hex: 0x4D8DFF)

    static func verdictColor(_ v: String) -> Color {
        switch v {
        case "TAKE": return green
        case "MAYBE": return amber
        default: return red
        }
    }

    static func outcomeColor(_ o: String) -> Color {
        switch o {
        case "ACCEPTED": return green
        case "UNKNOWN", "PENDING": return amber
        default: return muted
        }
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.muted)
            Text(value).font(.system(size: 19, weight: .bold)).foregroundColor(color).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KV: View {
    let label: String
    let value: String
    var color: Color = Theme.text
    var note: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(label).font(.subheadline).foregroundColor(Theme.text)
                Spacer()
                Text(value).font(.subheadline.weight(.bold)).foregroundColor(color)
            }
            if !note.isEmpty { Text(note).font(.caption).foregroundColor(Theme.muted) }
        }
        .padding(.vertical, 3)
    }
}

struct Bar: View {
    let fraction: Double
    var color: Color = Theme.green

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule().fill(color).frame(width: g.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

struct Caption: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View { Text(text).font(.caption).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
}

struct BigButton: View {
    let title: String
    var prominent = false
    var tint: Color = Theme.green
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundColor(prominent ? Color.black : Theme.text)
                .background(RoundedRectangle(cornerRadius: 12).fill(prominent ? tint : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

/// Segmented chips, like the Android tab chips.
struct Chips: View {
    let items: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    selection = i
                } label: {
                    Text(items[i])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundColor(selection == i ? Color.black : Theme.text)
                        .background(Capsule().fill(selection == i ? Theme.green : Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NavRow: View {
    let title: String
    let prev: () -> Void
    let next: () -> Void

    var body: some View {
        HStack {
            Button(action: prev) { Image(systemName: "chevron.left").padding(10) }
            Spacer()
            Text(title).font(.headline).foregroundColor(Theme.text)
            Spacer()
            Button(action: next) { Image(systemName: "chevron.right").padding(10) }
        }
        .foregroundColor(Theme.text)
    }
}

struct Screen<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var rev = 0

    private init() {
        NotificationCenter.default.addObserver(forName: .dashLensDataChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rev += 1
        }
    }
}

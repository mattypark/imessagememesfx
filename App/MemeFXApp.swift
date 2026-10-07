import SwiftUI

@main
struct MemeFXApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

/// The home-screen app: hear the whole board, and learn where it lives in Messages.
struct HomeView: View {
    @StateObject private var player = SoundPlayer()
    @State private var selected: SoundEffect?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Wordmark(size: 40)
                    Text("Sound effects for your group chats. Tap a pad to hear it.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.inkSoft)
                }
                .padding(.top, 24)

                Board(player: player, selected: $selected)

                HowTo()
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .background(Palette.deck.ignoresSafeArea())
    }
}

private struct HowTo: View {
    private let steps = [
        "Open any chat in Messages.",
        "Tap ＋, then More, then MemeFX.",
        "Tap a pad, then Send. Or type its command, like /fah, and hit return.",
        "It lands as an audio message the whole chat can play.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SEND ONE")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Palette.inkSoft)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.onAction)
                        .frame(width: 26, height: 26)
                        .background(Palette.action, in: Circle())
                    Text(step)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Palette.rule, lineWidth: 1.5)
        }
    }
}

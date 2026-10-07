import SwiftUI

/// The whole board: trending clips, then the originals. Tapping a pad plays it and selects it.
struct Board: View {
    @ObservedObject var player: SoundPlayer
    @Binding var selected: SoundEffect?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !SoundEffect.instants.isEmpty {
                section("TRENDING · MYINSTANTS", SoundEffect.instants)
            }
            section("MEMEFX ORIGINALS", SoundEffect.originals)
        }
    }

    private func section(_ title: String, _ effects: [SoundEffect]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Palette.inkSoft)
            PadDeck(player: player, selected: $selected, effects: effects)
        }
    }
}

/// A 4-wide grid of pads.
struct PadDeck: View {
    @ObservedObject var player: SoundPlayer
    @Binding var selected: SoundEffect?
    let effects: [SoundEffect]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Metrics.gap), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.gap) {
            ForEach(effects) { effect in
                Pad(
                    effect: effect,
                    isSelected: selected == effect,
                    playback: player.playback(for: effect)
                ) {
                    selected = effect
                    player.play(effect)
                }
            }
        }
    }
}

/// The MemeFX wordmark: "MEME" in ink, "FX" in a tomato pad chip.
struct Wordmark: View {
    var size: CGFloat = 17

    var body: some View {
        HStack(spacing: size * 0.2) {
            Text("MEME")
                .foregroundStyle(Palette.ink)
            Text("FX")
                .foregroundStyle(PadTint.tomato.label)
                .padding(.horizontal, size * 0.28)
                .padding(.vertical, size * 0.04)
                .background(PadTint.tomato.face, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        }
        .font(.system(size: size, weight: .black, design: .rounded))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("MemeFX"))
    }
}

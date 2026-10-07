import SwiftUI

/// A rubber sampler key: a colored face sitting on a darker lip. Pressing it sinks the face
/// onto the lip; while its sound plays, a lighter band sweeps across it.
struct Pad: View {
    let effect: SoundEffect
    let isSelected: Bool
    let playback: SoundPlayer.Playback?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(effect.emoji)
                    .font(.system(size: 20))
                Spacer(minLength: 4)
                Text(effect.title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(effect.tint.label)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                Text("/\(effect.command)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(effect.tint.label.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(PadStyle(tint: effect.tint, isSelected: isSelected, playback: playback))
        .aspectRatio(0.95, contentMode: .fit)
        .accessibilityLabel(Text(effect.title.capitalized))
        .accessibilityHint(Text("Plays the sound. Command /\(effect.command)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PadStyle: ButtonStyle {
    let tint: PadTint
    let isSelected: Bool
    let playback: SoundPlayer.Playback?

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.padRadius, style: .continuous)
        let sunk = configuration.isPressed

        ZStack(alignment: .top) {
            shape
                .fill(tint.lip)
                .padding(.top, Metrics.padLip)

            configuration.label
                .background {
                    shape.fill(tint.face)
                        .overlay { PlayingSweep(playback: playback).clipShape(shape) }
                }
                .overlay {
                    if isSelected {
                        shape.strokeBorder(tint.label.opacity(0.85), lineWidth: 2.5)
                    }
                }
                .padding(.bottom, Metrics.padLip)
                .offset(y: sunk ? Metrics.padLip - 1 : 0)
        }
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: sunk)
        .sensoryFeedback(.impact(weight: .medium), trigger: sunk) { _, pressed in pressed }
    }
}

/// The band that fills a pad left to right over the length of its sound.
private struct PlayingSweep: View {
    let playback: SoundPlayer.Playback?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let playback {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let progress = min(1, context.date.timeIntervalSince(playback.startedAt) / max(playback.duration, 0.01))
                GeometryReader { box in
                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(width: box.size.width * (reduceMotion ? 1 : progress))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

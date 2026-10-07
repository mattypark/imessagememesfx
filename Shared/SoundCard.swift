import SwiftUI

/// The square that stands for a sound in the chat (send style B): the pad's color, its
/// emoji large, its name, and its command. Rendered to an image for the message bubble.
struct SoundCard: View {
    let effect: SoundEffect

    var body: some View {
        let tint = effect.tint
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(effect.emoji)
                    .font(.system(size: 64))
                Spacer()
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint.label.opacity(0.75))
            }
            Spacer(minLength: 8)
            Text(effect.title)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(tint.label)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                Text("/\(effect.command) · TAP TO PLAY")
            }
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(tint.face)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.label, in: Capsule())
            .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.face)
    }

    /// A still of the card for the message's fallback layout — what people without the app see.
    @MainActor
    static func image(for effect: SoundEffect) -> UIImage? {
        let renderer = ImageRenderer(content: SoundCard(effect: effect).frame(width: 300, height: 300))
        renderer.scale = 2
        return renderer.uiImage
    }
}

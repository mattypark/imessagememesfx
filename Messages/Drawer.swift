import SwiftUI

/// What the drawer shows: which pad is picked. Owned by the view controller so a tapped card
/// in the thread can pick its pad when the drawer opens.
@MainActor
final class DrawerModel: ObservableObject {
    @Published var selected: SoundEffect?
}

/// The MemeFX drawer inside Messages: the board, and a Send bar once a pad is picked.
struct Drawer: View {
    @ObservedObject var player: SoundPlayer
    @ObservedObject var model: DrawerModel
    let send: (SoundEffect, SendStyle) -> Void
    /// Messages has no keyboard in the short drawer, so typing a command asks to go tall.
    let wantsKeyboard: () -> Void

    @AppStorage(SendStyle.storageKey) private var style: SendStyle = .audio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                CommandBar(wantsKeyboard: wantsKeyboard) { effect in
                    model.selected = effect
                    send(effect, style)
                }
                Board(player: player, selected: $model.selected)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let effect = model.selected {
                SendBar(effect: effect, style: style) { send(effect, style) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.selected)
        .background(Palette.deck)
    }

    private var header: some View {
        HStack {
            Wordmark(size: 15)
            Spacer()
            #if DEBUG
            // The A/B switch (rule: both variants ship side by side until a pick).
            Picker("Send as", selection: $style) {
                Text("A · Audio").tag(SendStyle.audio)
                Text("B · Card").tag(SendStyle.card)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .controlSize(.small)
            #endif
        }
    }
}

/// Slack-style slash commands: type "/fa", see FAHHH, FAAAH, FAIL…, hit return to send the
/// first, or tap any of them.
private struct CommandBar: View {
    let wantsKeyboard: () -> Void
    let send: (SoundEffect) -> Void

    @State private var typed = ""
    @FocusState private var focused: Bool

    private var matches: [SoundEffect] { SoundEffect.matching(typed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("/")
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundStyle(PadTint.tomato.face)
                TextField("fah, boom, bruh…", text: $typed)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($focused)
                    .onSubmit { fire(matches.first) }
                    .accessibilityLabel(Text("Sound command"))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focused ? Palette.ink : Palette.rule, lineWidth: 1.5)
            }

            if !typed.isEmpty {
                suggestions
            }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused { wantsKeyboard() }
        }
        .animation(.easeOut(duration: 0.15), value: typed.isEmpty)
    }

    @ViewBuilder
    private var suggestions: some View {
        if matches.isEmpty {
            Text("No sound called /\(typed.lowercased())")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.inkSoft)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(matches.prefix(12).enumerated()), id: \.element.id) { index, effect in
                        Button { fire(effect) } label: {
                            HStack(spacing: 6) {
                                Text(effect.emoji)
                                Text("/\(effect.command)")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                if index == 0 {
                                    Image(systemName: "return")
                                        .font(.system(size: 11, weight: .heavy))
                                }
                            }
                            .foregroundStyle(effect.tint.label)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(effect.tint.face, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Send \(effect.title.capitalized)"))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func fire(_ effect: SoundEffect?) {
        guard let effect else { return }
        typed = ""
        focused = false
        send(effect)
    }
}

private struct SendBar: View {
    let effect: SoundEffect
    let style: SendStyle
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(effect.emoji) \(effect.title)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(style.hint)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: action) {
                HStack(spacing: 6) {
                    Text("Send")
                    Image(systemName: "arrow.up")
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.onAction)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Palette.action, in: Capsule())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: effect)
            .accessibilityLabel(Text("Send \(effect.title.capitalized)"))
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 10)
        .background {
            Palette.deck
                .overlay(alignment: .top) { Rectangle().fill(Palette.rule).frame(height: 1) }
                .ignoresSafeArea()
        }
    }
}

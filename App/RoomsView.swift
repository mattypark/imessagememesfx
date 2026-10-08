import SwiftUI

/// Rooms: make one, share the code, and blast a pad so everyone in it hears the sound on their
/// own phone. The payoff of the whole app — no tapping on the other end.
struct RoomsView: View {
    @ObservedObject var backend: Backend
    @ObservedObject var push: PushManager
    @ObservedObject var player: SoundPlayer

    @State private var joinCode = ""
    @State private var newRoomName = ""
    @State private var showingNewRoom = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if backend.baseIsOff {
                        offCard
                    } else if push.permission != .allowed {
                        permissionCard
                    } else {
                        rooms
                        joinRow
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 20)
            }
            .background(Palette.deck.ignoresSafeArea())
            .navigationTitle("Rooms")
            .toolbar {
                if backend.isReady && push.permission == .allowed {
                    Button { showingNewRoom = true } label: { Image(systemName: "plus") }
                        .tint(Palette.ink)
                }
            }
            .task { await backend.refreshRooms() }
            .alert("New room", isPresented: $showingNewRoom) {
                TextField("Name", text: $newRoomName)
                Button("Create") { Task { await backend.createRoom(name: newRoomName); newRoomName = "" } }
                Button("Cancel", role: .cancel) { newRoomName = "" }
            } message: {
                Text("You'll get a code to share. Anyone who joins hears what anyone sends.")
            }
        }
    }

    private var rooms: some View {
        VStack(alignment: .leading, spacing: 12) {
            if backend.rooms.isEmpty {
                Text("No rooms yet. Make one and share the code with your group chat.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.inkSoft)
            }
            ForEach(backend.rooms) { room in
                NavigationLink {
                    BlastBoard(room: room, backend: backend, player: player)
                } label: {
                    RoomRow(room: room)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var joinRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("JOIN WITH A CODE")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Palette.inkSoft)
            HStack(spacing: 10) {
                TextField("K7P2QX", text: $joinCode)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.rule, lineWidth: 1.5) }
                Button("Join") {
                    Task { await backend.joinRoom(code: joinCode); joinCode = "" }
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.onAction)
                .padding(.horizontal, 20)
                .frame(height: 48)
                .background(Palette.action, in: Capsule())
                .disabled(joinCode.isEmpty)
            }
        }
    }

    private var permissionCard: some View {
        SetupCard(
            icon: "bell.badge.fill",
            title: "Turn on sounds",
            message: "MemeFX plays a sound on your phone when a friend sends one. Allow notifications to hear them.",
            button: "Allow notifications"
        ) { Task { await push.enable() } }
    }

    private var offCard: some View {
        SetupCard(
            icon: "wifi.slash",
            title: "Rooms aren't live yet",
            message: "The MemeFX server isn't switched on in this build. The soundboard and iMessage sending still work.",
            button: nil
        ) {}
    }
}

private struct RoomRow: View {
    let room: Backend.Room

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text("\(room.code) · \(room.members) \(room.members == 1 ? "person" : "people")")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Palette.inkSoft)
        }
        .padding(16)
        .background(PadTint.sun.face.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The blast board: tap a pad, everyone in the room hears it. A small local echo so you know it
/// fired.
private struct BlastBoard: View {
    let room: Backend.Room
    @ObservedObject var backend: Backend
    @ObservedObject var player: SoundPlayer
    @State private var selected: SoundEffect?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tap a pad — everyone in \(room.name) hears it.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.inkSoft)
                Board(player: player, selected: $selected)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 16)
        }
        .background(Palette.deck.ignoresSafeArea())
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selected) { _, effect in
            guard let effect else { return }
            player.play(effect)                           // local echo
            Task { await backend.send(effect, roomId: room.id) }
        }
        .overlay(alignment: .top) {
            ShareHint(code: room.code)
        }
    }
}

private struct ShareHint: View {
    let code: String
    var body: some View {
        Text("Share code \(code)")
            .font(.system(size: 13, weight: .heavy, design: .monospaced))
            .foregroundStyle(Palette.onAction)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Palette.action, in: Capsule())
            .padding(.top, 4)
    }
}

private struct SetupCard: View {
    let icon: String
    let title: String
    let message: String
    let button: String?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(PadTint.tomato.face)
            Text(title)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(button, action: action)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.onAction)
                    .padding(.horizontal, 20).frame(height: 48)
                    .background(Palette.action, in: Capsule())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.rule, lineWidth: 1.5) }
    }
}

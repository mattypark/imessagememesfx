import Foundation
import os

/// Talks to the MemeFX Worker. Holds the user's identity (an opaque id that is also the bearer
/// token) in the shared app group, so both the app and the extension can send.
@MainActor
final class Backend: ObservableObject {
    struct Room: Identifiable, Hashable, Codable {
        let id: String
        let code: String
        let name: String
        var members: Int
    }

    /// Flip this to the deployed Worker once it's up. Empty means "backend off": the app still
    /// works as a soundboard and over iMessage, it just can't blast to rooms yet.
    static let baseURL = URL(string: "https://memefx.workers.dev")

    @Published private(set) var userId: String?
    @Published private(set) var rooms: [Room] = []
    @Published var lastError: String?

    private let defaults = UserDefaults(suiteName: "group.com.matthewpark.memefx") ?? .standard
    private let log = Logger(subsystem: "com.matthewpark.memefx", category: "backend")

    var isReady: Bool { Backend.baseURL != nil && userId != nil }
    var baseIsOff: Bool { Backend.baseURL == nil }

    init() {
        userId = defaults.string(forKey: "userId")
    }

    // MARK: - Identity

    /// Makes the user on the server the first time, then keeps the id. Safe to call on launch.
    func ensureUser(name: String) async {
        guard Backend.baseURL != nil else { return }
        if userId != nil { return }
        do {
            let reply: [String: String] = try await post("/v1/users", ["name": name], authed: false)
            if let id = reply["userId"] {
                userId = id
                defaults.set(id, forKey: "userId")
            }
        } catch {
            report(error)
        }
    }

    func registerPush(token: String, sandbox: Bool) async {
        guard isReady else { return }
        do {
            let _: [String: Bool] = try await post("/v1/register", ["token": token, "env": sandbox ? "sandbox" : "production"])
        } catch {
            report(error)
        }
    }

    // MARK: - Rooms

    func refreshRooms() async {
        guard isReady else { return }
        do {
            let reply: RoomList = try await post("/v1/rooms/list", [:])
            rooms = reply.rooms
        } catch {
            report(error)
        }
    }

    @discardableResult
    func createRoom(name: String) async -> Room? {
        await call("/v1/rooms", ["name": name]) { (room: Room) in room }
    }

    @discardableResult
    func joinRoom(code: String) async -> Room? {
        await call("/v1/rooms/join", ["code": code]) { (reply: JoinReply) in
            Room(id: reply.roomId, code: reply.code ?? code, name: reply.name, members: reply.members ?? 1)
        }
    }

    /// Accept a friend's invite link (memefx://invite?code=…). Links the two of you.
    func acceptInvite(code: String) async {
        guard isReady else { return }
        do {
            let _: [String: String] = try await post("/v1/invite/accept", ["code": code])
        } catch {
            report(error)
        }
    }

    func leaveRoom(_ room: Room) async {
        guard isReady else { return }
        let _: [String: Bool]? = try? await post("/v1/rooms/leave", ["roomId": room.id])
        await refreshRooms()
    }

    // MARK: - Sending

    /// Blast a sound to everyone in a room (or, with roomId nil, every linked friend).
    func send(_ effect: SoundEffect, roomId: String?) async {
        guard isReady else { return }
        var payload: [String: String] = ["sound": effect.notificationSound, "title": "\(effect.emoji) \(effect.title.capitalized)"]
        if let roomId { payload["roomId"] = roomId }
        do {
            let _: SendReply = try await post("/v1/send", payload)
        } catch {
            report(error)
        }
    }

    // MARK: - plumbing

    private struct RoomList: Codable { let rooms: [Room] }
    private struct JoinReply: Codable { let roomId: String; let name: String; let code: String?; let members: Int? }
    private struct SendReply: Codable { let sent: Int; let recipients: Int }

    private func call<Reply: Decodable, T>(_ path: String, _ body: [String: String], _ map: (Reply) -> T) async -> T? {
        guard isReady else { return nil }
        do {
            let reply: Reply = try await post(path, body)
            await refreshRooms()
            return map(reply)
        } catch {
            report(error)
            return nil
        }
    }

    private func post<Reply: Decodable>(_ path: String, _ body: [String: String], authed: Bool = true) async throws -> Reply {
        guard let base = Backend.baseURL else { throw BackendError.off }
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authed {
            guard let userId else { throw BackendError.noUser }
            request.setValue("Bearer \(userId)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.network }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw BackendError.server(message ?? "Couldn't reach MemeFX.")
        }
        return try JSONDecoder().decode(Reply.self, from: data)
    }

    private func report(_ error: Error) {
        let message = (error as? BackendError)?.message ?? "Couldn't reach MemeFX."
        log.error("\(message, privacy: .public)")
        lastError = message
    }
}

enum BackendError: Error {
    case off, noUser, network, server(String)
    var message: String {
        switch self {
        case .off: "MemeFX sharing isn't set up yet."
        case .noUser: "Open MemeFX to finish setup."
        case .network: "No connection."
        case .server(let message): message
        }
    }
}

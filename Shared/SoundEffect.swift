import Foundation
import os

/// One pad on the board. `command` is what you type after "/" to send it.
struct SoundEffect: Identifiable, Hashable {
    enum Source: Hashable {
        /// Synthesized by scripts/make-sounds.py; ours to ship.
        case original
        /// A myinstants.com clip from scripts/fetch-instants.py; personal builds only.
        case instant
    }

    let command: String
    let title: String
    let emoji: String
    let tint: PadTint
    let file: String
    let source: Source

    var id: String { command }
    var fileURL: URL? { Bundle.main.url(forResource: file, withExtension: nil) }

    /// The bundled .caf iOS plays when a push names it (same stem as `file`).
    var notificationSound: String { (file as NSString).deletingPathExtension + ".caf" }

    /// The name the attachment carries in the chat, e.g. "Vine Boom.m4a".
    var attachmentName: String { "\(title.capitalized).m4a" }

    static func named(_ command: String) -> SoundEffect? {
        all.first { $0.command == command }
    }

    /// Trending clips first (they're what people reach for), then the originals.
    static let all: [SoundEffect] = instants + originals

    /// Pads are colored by position so no two neighbours, across or down, match.
    private static let tintCycle: [PadTint] = [.tomato, .sun, .sky, .grape, .mint, .bubblegum, .lime, .night]

    static let instants: [SoundEffect] = {
        struct Entry: Decodable { let command, title, emoji, file: String }
        guard let url = Bundle.main.url(forResource: "instants", withExtension: "json") else { return [] }
        do {
            let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
            return entries.enumerated().map { index, entry in
                SoundEffect(
                    command: entry.command, title: entry.title, emoji: entry.emoji,
                    tint: tintCycle[index % tintCycle.count], file: entry.file, source: .instant
                )
            }
        } catch {
            Logger(subsystem: "com.matthewpark.memefx", category: "board")
                .error("instants.json unreadable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }()

    static let originals: [SoundEffect] = [
        ("kaboom", "BOOM", "💥", "boom"),
        ("airhorn", "AIR HORN", "📯", "airhorn"),
        ("badumtss", "BA DUM TSS", "🥁", "rimshot"),
        ("wahwah", "WAH WAH", "🎺", "sad-trombone"),
        ("crickets", "CRICKETS", "🦗", "crickets"),
        ("ding", "DING", "🔔", "ding"),
        ("wrong", "WRONG", "❌", "buzzer"),
        ("scratch", "SCRATCH", "💿", "record-scratch"),
        ("dundun", "DUN DUN", "😱", "dun-dun-dun"),
        ("bonk", "BONK", "🔨", "bonk"),
        ("pfft", "PFFT", "💨", "fart"),
        ("whoosh", "WHOOSH", "🌪️", "whoosh"),
        ("clap", "CLAP", "👏", "applause"),
        ("drumroll", "DRUMROLL", "🥁", "drumroll"),
        ("boing", "BOING", "🌀", "boing"),
        ("coin", "COIN", "🪙", "coin"),
    ].enumerated().map { index, entry in
        SoundEffect(
            command: entry.0, title: entry.1, emoji: entry.2,
            tint: tintCycle[index % tintCycle.count], file: "\(entry.3).m4a", source: .original
        )
    }

    /// Slash-command lookup: exact match first, then commands that start with what's typed,
    /// then titles that contain it. "/fa" → FAHHH, FAAAH, FART, FAIL…
    static func matching(_ typed: String) -> [SoundEffect] {
        let query = typed.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespaces))
        guard !query.isEmpty else { return [] }
        let exact = all.filter { $0.command == query }
        let prefix = all.filter { $0.command != query && $0.command.hasPrefix(query) }
        let loose = all.filter {
            !$0.command.hasPrefix(query) && $0.title.lowercased().replacingOccurrences(of: " ", with: "").contains(query)
        }
        return exact + prefix + loose
    }
}

/// How a sound travels to the chat — the A/B under test.
enum SendStyle: String, CaseIterable {
    /// A: the sound itself, as an audio message. Everyone in the chat can play it, app or not.
    case audio = "a"
    /// B: a MemeFX card. Tapping it opens MemeFX and plays the sound.
    case card = "b"

    static let storageKey = "debug.send.variant"

    var hint: String {
        switch self {
        case .audio: "Sends as audio · anyone can play it"
        case .card: "Sends as a card · tap to play"
        }
    }
}

/// The link a card carries, so the receiving side knows which sound to play.
enum SoundLink {
    static func url(for effect: SoundEffect) -> URL? {
        var parts = URLComponents()
        parts.scheme = "memefx"
        parts.host = "play"
        parts.queryItems = [URLQueryItem(name: "sfx", value: effect.command)]
        return parts.url
    }

    static func effect(from url: URL?) -> SoundEffect? {
        guard let url,
              let command = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "sfx" })?.value
        else { return nil }
        return SoundEffect.named(command)
    }
}

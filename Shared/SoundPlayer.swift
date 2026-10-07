import AVFoundation
import Foundation
import os

/// Plays one pad at a time. Tapping a new pad cuts the last one off, like a real sampler.
@MainActor
final class SoundPlayer: ObservableObject {
    struct Playback: Equatable {
        let id: SoundEffect.ID
        let startedAt: Date
        let duration: TimeInterval
    }

    @Published private(set) var playback: Playback?

    private var player: AVAudioPlayer?
    private var finish: Task<Void, Never>?
    private let log = Logger(subsystem: "com.matthewpark.memefx", category: "player")

    func play(_ effect: SoundEffect) {
        guard let url = effect.fileURL else {
            log.error("missing sound file: \(effect.id, privacy: .public)")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)

            let next = try AVAudioPlayer(contentsOf: url)
            player?.stop()
            next.play()
            player = next
            playback = Playback(id: effect.id, startedAt: .now, duration: next.duration)
            scheduleFinish(after: next.duration)
        } catch {
            log.error("couldn't play \(effect.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        player?.stop()
        finish?.cancel()
        playback = nil
    }

    func playback(for effect: SoundEffect) -> Playback? {
        playback?.id == effect.id ? playback : nil
    }

    private func scheduleFinish(after seconds: TimeInterval) {
        finish?.cancel()
        finish = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.playback = nil
        }
    }
}

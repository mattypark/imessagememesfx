import Messages
import SwiftUI
import os

/// The extension's entry point: hosts the drawer, sends sounds, and plays one when someone
/// taps a MemeFX card in the thread.
final class MessagesViewController: MSMessagesAppViewController {
    private let player = SoundPlayer()
    private let model = DrawerModel()
    private var host: UIHostingController<Drawer>?
    private let log = Logger(subsystem: "com.matthewpark.memefx", category: "messages")

    override func viewDidLoad() {
        super.viewDidLoad()
        let drawer = Drawer(
            player: player,
            model: model,
            send: { [weak self] effect, style in self?.send(effect, as: style) },
            wantsKeyboard: { [weak self] in self?.requestPresentationStyle(.expanded) }
        )
        let host = UIHostingController(rootView: drawer)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        self.host = host
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        if let message = conversation.selectedMessage {
            playIncoming(message)
        }
    }

    override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
        player.stop()
    }

    /// Someone tapped a MemeFX card while the drawer was open: pick its pad and play it.
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        playIncoming(message)
    }

    private func playIncoming(_ message: MSMessage) {
        guard let effect = SoundLink.effect(from: message.url) else { return }
        model.selected = effect
        player.play(effect)
    }

    // MARK: - Sending

    private func send(_ effect: SoundEffect, as style: SendStyle) {
        guard let conversation = activeConversation else { return }
        // Fire straight into the chat. When Messages won't send for us (no iMessage account,
        // SMS-only chat), stage it in the compose box instead so one tap on ↑ sends it.
        switch style {
        case .audio:
            guard let url = shareableCopy(of: effect) else { return }
            let name = effect.attachmentName
            conversation.sendAttachment(url, withAlternateFilename: name) { [weak self] error in
                guard let error else { return }
                self?.report(error, effect: effect, step: "send")
                DispatchQueue.main.async {
                    conversation.insertAttachment(url, withAlternateFilename: name) { error in
                        self?.report(error, effect: effect, step: "insert")
                    }
                }
            }
        case .card:
            let message = cardMessage(for: effect, in: conversation)
            conversation.send(message) { [weak self] error in
                guard let error else { return }
                self?.report(error, effect: effect, step: "send")
                DispatchQueue.main.async {
                    conversation.insert(message) { error in
                        self?.report(error, effect: effect, step: "insert")
                    }
                }
            }
        }
        player.stop()
        requestPresentationStyle(.compact)
    }

    /// Messages reads attachments from outside our bundle more reliably than from inside it,
    /// so hand it a copy in the extension's temporary folder.
    private func shareableCopy(of effect: SoundEffect) -> URL? {
        guard let source = effect.fileURL else {
            log.error("missing sound file: \(effect.id, privacy: .public)")
            return nil
        }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(effect.attachmentName)
        do {
            if FileManager.default.fileExists(atPath: copy.path) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: source, to: copy)
            return copy
        } catch {
            log.error("couldn't stage \(effect.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func cardMessage(for effect: SoundEffect, in conversation: MSConversation) -> MSMessage {
        let layout = MSMessageTemplateLayout()
        layout.image = SoundCard.image(for: effect)
        layout.caption = "\(effect.emoji) \(effect.title.capitalized)"
        layout.subcaption = "/\(effect.command) · tap to play"

        let message = MSMessage(session: MSSession())
        message.url = SoundLink.url(for: effect)
        message.summaryText = "\(effect.emoji) \(effect.title.capitalized)"
        message.layout = layout
        return message
    }

    private func report(_ error: Error?, effect: SoundEffect, step: String) {
        guard let error else { return }
        log.error("\(step, privacy: .public) failed for \(effect.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

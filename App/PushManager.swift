import SwiftUI
import UserNotifications
import os

/// Asks for notification permission, registers for remote pushes, and hands the APNs token to
/// the backend. Owns the one piece of state the Rooms screen needs: whether pushes are allowed.
@MainActor
final class PushManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    enum Permission { case unknown, allowed, denied }

    @Published private(set) var permission: Permission = .unknown

    private let backend: Backend
    private let log = Logger(subsystem: "com.matthewpark.memefx", category: "push")

    init(backend: Backend) {
        self.backend = backend
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permission = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        default: .unknown
        }
    }

    /// Ask, and on a yes register for remote notifications. Sounds play on their own, so we need
    /// the .sound and .alert options.
    func enable() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            permission = granted ? .allowed : .denied
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            log.error("authorization failed: \(error.localizedDescription, privacy: .public)")
            permission = .denied
        }
    }

    func didRegister(tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        Task { await backend.registerPush(token: token, sandbox: isSandboxBuild) }
    }

    func didFailToRegister(_ error: Error) {
        log.error("remote registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Show our own sound even when MemeFX is in the foreground, so a blast you receive while the
    /// app is open still plays.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// TestFlight and App Store builds talk to Apple's production push server; a cabled debug
    /// build talks to sandbox. The embedded provisioning profile tells them apart.
    private var isSandboxBuild: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
            && (try? String(contentsOf: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")!, encoding: .isoLatin1))?
                .contains("<key>aps-environment</key>\n\t\t<string>development</string>") == true
        #endif
    }
}

/// Bridges UIKit's app-delegate push callbacks into SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var push: PushManager?

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in AppDelegate.push?.didRegister(tokenData: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in AppDelegate.push?.didFailToRegister(error) }
    }
}

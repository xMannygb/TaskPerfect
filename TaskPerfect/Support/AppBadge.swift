import Foundation
import UserNotifications

/// The number on the app icon.
///
/// iOS treats the badge as a notification capability, so it needs the same
/// authorization prompt — asking only when the setting is switched on, rather
/// than at launch, means the request arrives with an obvious reason attached.
public enum AppBadge {

    /// Ask for badge permission. Returns false if the user declines, which the
    /// caller uses to switch the setting back off rather than leaving it on and
    /// silently doing nothing.
    @discardableResult
    public static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized { return true }
        if settings.authorizationStatus == .denied { return false }
        return (try? await center.requestAuthorization(options: [.badge])) ?? false
    }

    public static func set(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(max(0, count))
    }

    public static func clear() async {
        await set(0)
    }

    /// Apply or remove the badge to match the current setting.
    public static func apply(count: Int, enabled: Bool) async {
        guard enabled else { await clear(); return }
        await set(count)
    }
}

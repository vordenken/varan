import Combine
import Foundation
import UserNotifications

struct NotificationDestination: Hashable, Identifiable {
  enum Kind: String, Hashable { case alert, update }

  let profileID: UUID
  let kind: Kind
  let itemID: String

  var id: String { "\(profileID.uuidString):\(kind.rawValue):\(itemID)" }

  init(profileID: UUID, kind: Kind, itemID: String) {
    self.profileID = profileID
    self.kind = kind
    self.itemID = itemID
  }

  init?(userInfo: [AnyHashable: Any]) {
    guard let profile = userInfo["profileID"] as? String,
          let profileID = UUID(uuidString: profile),
          let rawKind = userInfo["kind"] as? String,
          let kind = Kind(rawValue: rawKind),
          let itemID = userInfo["itemID"] as? String,
          !itemID.isEmpty else { return nil }
    self.init(profileID: profileID, kind: kind, itemID: itemID)
  }

  var userInfo: [String: String] {
    ["profileID": profileID.uuidString, "kind": kind.rawValue, "itemID": itemID]
  }
}

@MainActor
final class NotificationRouteCenter: ObservableObject {
  static let shared = NotificationRouteCenter()
  @Published var pendingDestination: NotificationDestination?

  private init() {}
}

@MainActor
final class SystemNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  static let shared = SystemNotificationDelegate()

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    guard let destination = NotificationDestination(
      userInfo: response.notification.request.content.userInfo
    ) else { return }
    await MainActor.run {
      NotificationRouteCenter.shared.pendingDestination = destination
    }
  }
}

@MainActor
final class SystemNotificationService {
  static let shared = SystemNotificationService()
  private let center = UNUserNotificationCenter.current()

  private init() {}

  func requestPermission() async -> Bool {
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional:
      return true
#if os(iOS)
    case .ephemeral:
      return true
#endif
    case .denied:
      return false
    case .notDetermined:
      return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    @unknown default:
      return false
    }
  }

  func deliver(title: String, body: String, destination: NotificationDestination) async {
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized
      || settings.authorizationStatus == .provisional else { return }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.userInfo = destination.userInfo
    let request = UNNotificationRequest(
      identifier: destination.id, content: content, trigger: nil
    )
    try? await center.add(request)
  }
}

struct NotificationCandidateTracker {
  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  func newIDs(
    profileID: UUID, kind: NotificationDestination.Kind, currentIDs: Set<String>
  ) -> Set<String> {
    let key = "notifications.system.known.\(kind.rawValue).\(profileID.uuidString)"
    let previous = defaults.stringArray(forKey: key).map(Set.init)
    defaults.set(Array(currentIDs), forKey: key)
    return previous.map { currentIDs.subtracting($0) } ?? []
  }
}

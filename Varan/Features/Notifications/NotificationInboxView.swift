import Combine
import SwiftUI

enum InboxItem: Identifiable {
  case alert(KomodoAlert)
  case update(KomodoUpdateListItem)

  var id: String {
    switch self {
    case .alert(let alert): "alert:\(alert.id)"
    case .update(let update): "update:\(update.id)"
    }
  }

  var date: Date {
    let timestamp: Int64
    switch self {
    case .alert(let alert): timestamp = alert.timestamp
    case .update(let update): timestamp = update.startTimestamp
    }
    return Date(timeIntervalSince1970: TimeInterval(timestamp) / 1_000)
  }
}

@MainActor
final class NotificationInboxStore: ObservableObject {
  @Published private(set) var alerts: [KomodoAlert] = []
  @Published private(set) var updates: [KomodoUpdateListItem] = []
  @Published private(set) var alertsNextPage: Int?
  @Published private(set) var updatesNextPage: Int?
  @Published private(set) var alertsError: String?
  @Published private(set) var updatesError: String?
  @Published private(set) var isLoading = false
  @Published private(set) var isLoadingMore = false
  @Published private(set) var hasAttemptedInitialLoad = false
  @Published private(set) var unreadCount = 0
  @Published private(set) var openAlertCount = 0

  private let defaults: UserDefaults
  private let candidateTracker: NotificationCandidateTracker
  private let clientFactory: @MainActor (ServerProfile, KeychainStore) async throws -> KomodoAPIClient
  private var profileID: UUID?
  private var currentProfile: ServerProfile?
  private var keychainStore: KeychainStore?
  private var notificationSettings: AppSettings?
  private var client: KomodoAPIClient?
  private var alertsLoadedPages = 0
  private var updatesLoadedPages = 0
  private var readIDs: Set<String> = []
  private var openAlertIDs: Set<String> = []
  private var failedUpdateIDs: Set<String> = []
  private var refreshPending = false
  private var liveRefreshTask: Task<Void, Never>?

  init(
    defaults: UserDefaults = .standard,
    clientFactory: @escaping @MainActor (ServerProfile, KeychainStore) async throws -> KomodoAPIClient
      = makeKomodoClient
  ) {
    self.defaults = defaults
    candidateTracker = NotificationCandidateTracker(defaults: defaults)
    self.clientFactory = clientFactory
  }

  func monitor(
    profile: ServerProfile, keychainStore: KeychainStore, settings: AppSettings? = nil
  ) async {
    configure(profile: profile, keychainStore: keychainStore, settings: settings)
    var cycle = 0
    do {
      while !Task.isCancelled {
        if isLoading || isLoadingMore {
          try await Task.sleep(for: .milliseconds(100))
          continue
        }
        await refresh(includeUpdates: cycle.isMultiple(of: 4) || client == nil)
        cycle += 1
        try await Task.sleep(for: .seconds(15))
      }
    } catch {
      return
    }
  }

  func loadIfNeeded(
    profile: ServerProfile, keychainStore: KeychainStore, settings: AppSettings? = nil
  ) async {
    configure(profile: profile, keychainStore: keychainStore, settings: settings)
    while !hasAttemptedInitialLoad && profileID == profile.id && !Task.isCancelled {
      if isLoading || isLoadingMore {
        try? await Task.sleep(for: .milliseconds(100))
      } else {
        await refresh()
      }
    }
  }

  func connectionDidChange(profile: ServerProfile) async {
    guard profileID == profile.id else { return }
    currentProfile = profile
    client = nil
    await refresh()
  }

  private func configure(
    profile: ServerProfile, keychainStore: KeychainStore, settings: AppSettings?
  ) {
    if profileID != profile.id {
      profileID = profile.id
      client = nil
      alertsLoadedPages = 0
      updatesLoadedPages = 0
      alerts = []
      updates = []
      alertsNextPage = nil
      updatesNextPage = nil
      alertsError = nil
      updatesError = nil
      isLoading = false
      isLoadingMore = false
      hasAttemptedInitialLoad = false
      openAlertIDs = []
      failedUpdateIDs = []
      openAlertCount = 0
      refreshPending = false
      liveRefreshTask?.cancel()
      liveRefreshTask = nil
      readIDs = Set(defaults.stringArray(forKey: readKey(profile.id)) ?? [])
      updateUnreadCount()
    }
    currentProfile = profile
    self.keychainStore = keychainStore
    notificationSettings = settings
  }

  func refresh(includeUpdates: Bool = true) async {
    guard profileID != nil else { return }
    guard !isLoading, !isLoadingMore else {
      refreshPending = true
      return
    }
    let currentProfileID = profileID
    isLoading = true
    defer {
      if profileID == currentProfileID {
        isLoading = false
        if !Task.isCancelled { hasAttemptedInitialLoad = true }
        if refreshPending {
          refreshPending = false
          Task { await refresh() }
        }
      }
    }
    guard let currentProfile, let keychainStore else { return }
    let client: KomodoAPIClient
    do {
      client = try await clientFactory(currentProfile, keychainStore)
      guard !Task.isCancelled, profileID == currentProfileID else { return }
      self.client = client
    } catch {
      guard !Task.isCancelled, profileID == currentProfileID else { return }
      self.client = nil
      alertsError = error.localizedDescription
      updatesError = error.localizedDescription
      return
    }
    do {
      var page = try await client.listAlerts()
      guard !Task.isCancelled, profileID == currentProfileID else { return }
      var refreshedAlerts = page.alerts
      var loadedPages = 1
      while loadedPages < alertsLoadedPages, let nextPage = page.nextPage {
        page = try await client.listAlerts(page: nextPage)
        guard !Task.isCancelled, profileID == currentProfileID else { return }
        refreshedAlerts.append(contentsOf: page.alerts.filter { item in
          !refreshedAlerts.contains { $0.id == item.id }
        })
        loadedPages += 1
      }
      alerts = refreshedAlerts
      alertsNextPage = page.nextPage
      alertsLoadedPages = loadedPages
      alertsError = nil
      initializeVisibleReadStateIfNeeded(kind: "alerts", ids: refreshedAlerts.map { "alert:\($0.id)" })
    } catch {
      guard !Task.isCancelled, profileID == currentProfileID else { return }
      alertsError = error.localizedDescription
    }
    if includeUpdates {
      do {
        var page = try await client.listUpdates()
        guard !Task.isCancelled, profileID == currentProfileID else { return }
        var refreshedUpdates = page.updates
        var loadedPages = 1
        while loadedPages < updatesLoadedPages, let nextPage = page.nextPage {
          page = try await client.listUpdates(page: nextPage)
          guard !Task.isCancelled, profileID == currentProfileID else { return }
          refreshedUpdates.append(contentsOf: page.updates.filter { item in
            !refreshedUpdates.contains { $0.id == item.id }
          })
          loadedPages += 1
        }
        updates = refreshedUpdates
        updatesNextPage = page.nextPage
        updatesLoadedPages = loadedPages
        updatesError = nil
        initializeVisibleReadStateIfNeeded(kind: "updates", ids: refreshedUpdates.flatMap { update in
          update.status == "Complete" && !update.success
            ? ["update:\(update.id)", "failure:\(update.id)"] : ["update:\(update.id)"]
        })
      } catch {
        guard !Task.isCancelled, profileID == currentProfileID else { return }
        updatesError = error.localizedDescription
      }
    }
    await refreshBadgeCounts(
      client: client, profileID: currentProfileID, includeUpdates: includeUpdates
    )
  }

  func refreshForLiveEvent(profileID: UUID) {
    guard self.profileID == profileID else { return }
    liveRefreshTask?.cancel()
    liveRefreshTask = Task {
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      await refresh()
    }
  }

  func loadMore() async {
    guard let client, !isLoading, !isLoadingMore else { return }
    let currentProfileID = profileID
    isLoadingMore = true
    defer { if profileID == currentProfileID { isLoadingMore = false } }
    if let alertsNextPage {
      do {
        let page = try await client.listAlerts(page: alertsNextPage)
        guard !Task.isCancelled, profileID == currentProfileID else { return }
        alerts.append(contentsOf: page.alerts.filter { item in !alerts.contains { $0.id == item.id } })
        self.alertsNextPage = page.nextPage
        alertsLoadedPages += 1
        alertsError = nil
        rememberHistorical(ids: page.alerts.filter {
          !openAlertIDs.contains("alert:\($0.id)")
        }.map { "alert:\($0.id)" })
      } catch {
        guard profileID == currentProfileID else { return }
        alertsError = error.localizedDescription
      }
    }
    if let updatesNextPage {
      do {
        let page = try await client.listUpdates(page: updatesNextPage)
        guard !Task.isCancelled, profileID == currentProfileID else { return }
        updates.append(contentsOf: page.updates.filter { item in !updates.contains { $0.id == item.id } })
        self.updatesNextPage = page.nextPage
        updatesLoadedPages += 1
        updatesError = nil
        rememberHistorical(ids: page.updates.filter {
          !($0.status == "Complete" && !$0.success)
        }.map { "update:\($0.id)" })
      } catch {
        guard profileID == currentProfileID else { return }
        updatesError = error.localizedDescription
      }
    }
    if refreshPending && !Task.isCancelled {
      refreshPending = false
      Task { await refresh() }
    }
  }

  func isRead(_ item: InboxItem) -> Bool {
    switch item {
    case .alert: readIDs.contains(item.id)
    case .update(let update):
      update.status == "Complete" && !update.success
        ? readIDs.contains("failure:\(update.id)") : readIDs.contains(item.id)
    }
  }

  func markRead(_ item: InboxItem) {
    guard let profileID else { return }
    readIDs.insert(item.id)
    if case .update(let update) = item, update.status == "Complete" && !update.success {
      readIDs.insert("failure:\(update.id)")
    }
    defaults.set(Array(readIDs), forKey: readKey(profileID))
    updateUnreadCount()
  }

  func markAllRead() {
    guard let profileID else { return }
    readIDs.formUnion(openAlertIDs)
    readIDs.formUnion(failedUpdateIDs)
    readIDs.formUnion(alerts.map { "alert:\($0.id)" })
    for update in updates {
      readIDs.insert("update:\(update.id)")
      if update.status == "Complete" && !update.success {
        readIDs.insert("failure:\(update.id)")
      }
    }
    defaults.set(Array(readIDs), forKey: readKey(profileID))
    updateUnreadCount()
  }

  func serverSummary(idOrName: String) async throws -> ServerListItem? {
    guard let client else { throw KomodoAPIError.connectionFailed }
    return try await client.listAllServers().first {
      $0.id == idOrName || $0.name == idOrName
    }
  }

  func stackSummary(idOrName: String) async throws -> StackListItem? {
    guard let client else { throw KomodoAPIError.connectionFailed }
    let pageSize = 50
    var page = 0
    while true {
      try Task.checkCancellation()
      let batch = try await client.listStacks(page: page, limit: pageSize)
      if let match = batch.first(where: { $0.id == idOrName || $0.name == idOrName }) {
        return match
      }
      if batch.count < pageSize { return nil }
      page += 1
    }
  }

  func alertDetail(id: String) async throws -> KomodoAlert {
    guard let client else { throw KomodoAPIError.connectionFailed }
    return try await client.getAlert(id: id)
  }

  func updateDetail(id: String) async throws -> KomodoUpdateDetail {
    guard let client else { throw KomodoAPIError.connectionFailed }
    return try await client.getUpdate(id: id)
  }

  private func refreshBadgeCounts(
    client: KomodoAPIClient, profileID: UUID?, includeUpdates: Bool
  ) async {
    guard let profileID else { return }
    do {
      var ids: Set<String> = []
      var criticalAlerts: [KomodoAlert] = []
      var page = 0
      while true {
        let result = try await client.listOpenAlerts(page: page)
        guard !Task.isCancelled, self.profileID == profileID else { return }
        ids.formUnion(result.alerts.filter { !$0.resolved }.map { "alert:\($0.id)" })
        criticalAlerts.append(contentsOf: result.alerts.filter {
          !$0.resolved && $0.level.uppercased() == "CRITICAL"
        })
        guard let nextPage = result.nextPage else { break }
        guard nextPage > page else { throw KomodoAPIError.invalidResponse }
        page = nextPage
      }
      let visibleUnread = Set(alerts.filter { !$0.resolved && !readIDs.contains("alert:\($0.id)") }
        .map { "alert:\($0.id)" })
      initializeReadStateIfNeeded(kind: "alerts", ids: ids, preserving: visibleUnread)
      openAlertIDs = ids
      openAlertCount = ids.count
      updateUnreadCount()
      let newIDs = candidateTracker.newIDs(
        profileID: profileID, kind: .alert,
        currentIDs: Set(criticalAlerts.map(\.id))
      )
      if notificationSettings?.systemNotificationsEnabled == true,
         notificationSettings?.criticalAlertNotificationsEnabled == true,
         let profileName = currentProfile?.name {
        for alert in criticalAlerts where newIDs.contains(alert.id) {
          await SystemNotificationService.shared.deliver(
            title: String(localized: "notifications.system.criticalTitle"),
            body: "\(profileName): \(alert.data.data?.message ?? alert.data.data?.name ?? alert.data.type.readableIdentifier)",
            destination: NotificationDestination(
              profileID: profileID, kind: .alert, itemID: alert.id
            )
          )
        }
      }
    } catch {
      guard !Task.isCancelled, self.profileID == profileID else { return }
      alertsError = error.localizedDescription
    }

    guard includeUpdates else { return }
    do {
      var ids: Set<String> = []
      var failedUpdates: [KomodoUpdateListItem] = []
      var page = 0
      while true {
        let result = try await client.listFailedUpdates(page: page)
        guard !Task.isCancelled, self.profileID == profileID else { return }
        ids.formUnion(result.updates.filter { $0.status == "Complete" && !$0.success }
          .map { "failure:\($0.id)" })
        failedUpdates.append(contentsOf: result.updates.filter {
          $0.status == "Complete" && !$0.success
        })
        guard let nextPage = result.nextPage else { break }
        guard nextPage > page else { throw KomodoAPIError.invalidResponse }
        page = nextPage
      }
      let visibleUnread = Set(updates.filter {
        $0.status == "Complete" && !$0.success && !readIDs.contains("failure:\($0.id)")
      }.map { "failure:\($0.id)" })
      initializeReadStateIfNeeded(kind: "updates", ids: ids, preserving: visibleUnread)
      failedUpdateIDs = ids
      updateUnreadCount()
      let newIDs = candidateTracker.newIDs(
        profileID: profileID, kind: .update,
        currentIDs: Set(failedUpdates.map(\.id))
      )
      if notificationSettings?.systemNotificationsEnabled == true,
         notificationSettings?.failedUpdateNotificationsEnabled == true,
         let profileName = currentProfile?.name {
        for update in failedUpdates where newIDs.contains(update.id) {
          await SystemNotificationService.shared.deliver(
            title: String(localized: "notifications.system.failedTitle"),
            body: "\(profileName): \(localizedOperation(update.operation))",
            destination: NotificationDestination(
              profileID: profileID, kind: .update, itemID: update.id
            )
          )
        }
      }
    } catch {
      guard !Task.isCancelled, self.profileID == profileID else { return }
      updatesError = error.localizedDescription
    }
  }

  private func initializeReadStateIfNeeded(
    kind: String, ids: Set<String>, preserving visibleUnreadIDs: Set<String>
  ) {
    guard let profileID else { return }
    let key = baselineKey(profileID, kind: "full.\(kind)")
    guard !defaults.bool(forKey: key) else { return }
    let preserved = defaults.bool(forKey: baselineKey(profileID, kind: kind))
      ? visibleUnreadIDs : []
    readIDs.formUnion(ids.subtracting(preserved))
    defaults.set(Array(readIDs), forKey: readKey(profileID))
    defaults.set(true, forKey: key)
  }

  private func initializeVisibleReadStateIfNeeded(kind: String, ids: [String]) {
    guard let profileID else { return }
    let key = baselineKey(profileID, kind: kind)
    guard !defaults.bool(forKey: key) else { return }
    readIDs.formUnion(ids)
    defaults.set(Array(readIDs), forKey: readKey(profileID))
    defaults.set(true, forKey: key)
  }

  private func rememberHistorical(ids: [String]) {
    guard let profileID, !ids.isEmpty else { return }
    readIDs.formUnion(ids)
    defaults.set(Array(readIDs), forKey: readKey(profileID))
  }

  private func updateUnreadCount() {
    unreadCount = openAlertIDs.subtracting(readIDs).count
      + failedUpdateIDs.subtracting(readIDs).count
  }

  private func readKey(_ id: UUID) -> String { "notifications.read.\(id.uuidString)" }
  private func baselineKey(_ id: UUID, kind: String) -> String {
    "notifications.initialized.\(kind).\(id.uuidString)"
  }
}

private enum InboxFilter: String, CaseIterable, Identifiable {
  case all, alerts, updates

  var id: Self { self }
  var title: LocalizedStringKey {
    switch self {
    case .all: "notifications.filter.all"
    case .alerts: "notifications.filter.alerts"
    case .updates: "notifications.filter.updates"
    }
  }
}

private enum InboxStatusFilter: String, CaseIterable, Identifiable {
  case all, open, resolved, running, succeeded, failed

  var id: Self { self }
  var title: LocalizedStringKey {
    switch self {
    case .all: "notifications.filter.all"
    case .open: "notifications.open"
    case .resolved: "notifications.resolved"
    case .running: "notifications.running"
    case .succeeded: "notifications.succeeded"
    case .failed: "notifications.failed"
    }
  }

  func matches(_ item: InboxItem) -> Bool {
    switch (self, item) {
    case (.all, _): true
    case (.open, .alert(let alert)): !alert.resolved
    case (.resolved, .alert(let alert)): alert.resolved
    case (.running, .update(let update)): update.status != "Complete"
    case (.succeeded, .update(let update)): update.status == "Complete" && update.success
    case (.failed, .update(let update)): update.status == "Complete" && !update.success
    default: false
    }
  }

  static func available(for kind: InboxFilter) -> [Self] {
    switch kind {
    case .all: allCases
    case .alerts: [.all, .open, .resolved]
    case .updates: [.all, .running, .succeeded, .failed]
    }
  }
}

private enum InboxSeverityFilter: String, CaseIterable, Identifiable {
  case all, critical, warning, ok

  var id: Self { self }
  var title: LocalizedStringKey {
    switch self {
    case .all: "notifications.filter.all"
    case .critical: "notifications.severity.critical"
    case .warning: "notifications.severity.warning"
    case .ok: "notifications.severity.ok"
    }
  }

  func matches(_ alert: KomodoAlert) -> Bool {
    self == .all || rawValue.uppercased() == alert.level.uppercased()
  }
}

struct NotificationInboxView: View {
  @ObservedObject private var routeCenter = NotificationRouteCenter.shared
  @ObservedObject var store: NotificationInboxStore
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings
  @State private var filter: InboxFilter = .all
  @State private var statusFilter: InboxStatusFilter = .all
  @State private var severityFilter: InboxSeverityFilter = .all
  @State private var linkedDestination: NotificationDestination?

  private var items: [InboxItem] {
    let alerts = filter == .updates ? [] : store.alerts.map(InboxItem.alert)
    let updates = filter == .alerts ? [] : store.updates.map(InboxItem.update)
    return (alerts + updates)
      .filter { item in
        guard statusFilter.matches(item) else { return false }
        if case .alert(let alert) = item, filter == .alerts {
          return severityFilter.matches(alert)
        }
        return true
      }
      .sorted { $0.date > $1.date }
  }

  private var hasUnreadItems: Bool {
    store.unreadCount > 0
      || store.alerts.map(InboxItem.alert).contains { !store.isRead($0) }
      || store.updates.map(InboxItem.update).contains { !store.isRead($0) }
  }

  var body: some View {
    List {
      Section {
        Picker("notifications.filter", selection: $filter) {
          ForEach(InboxFilter.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        Picker("notifications.filter.status", selection: $statusFilter) {
          ForEach(InboxStatusFilter.available(for: filter)) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        if filter == .alerts {
          Picker("notifications.filter.severity", selection: $severityFilter) {
            ForEach(InboxSeverityFilter.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.menu)
        }
        HStack {
          Label("notifications.openAlerts", systemImage: "exclamationmark.triangle")
          Spacer()
          Text(store.openAlertCount, format: .number)
        }
        HStack {
          Label("notifications.runningUpdates", systemImage: "progress.indicator")
          Spacer()
          Text(store.updates.filter { $0.status != "Complete" }.count, format: .number)
        }
      } header: {
        Text(profile.name)
      }

      if (store.isLoading || !store.hasAttemptedInitialLoad) && items.isEmpty {
        ProgressView("notifications.loading")
      } else if items.isEmpty && store.alertsError == nil && store.updatesError == nil {
        ContentUnavailableView(
          store.alerts.isEmpty && store.updates.isEmpty
            ? "notifications.empty" : "notifications.emptyFiltered",
          systemImage: "bell.slash"
        )
      }

      if let alertsError = store.alertsError, filter != .updates {
        Label(alertsError, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.secondary)
      }
      if let updatesError = store.updatesError, filter != .alerts {
        Label(updatesError, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.secondary)
      }

      ForEach(items) { item in
        NavigationLink {
          NotificationDetailView(
            item: item, store: store, profile: profile,
            keychainStore: keychainStore, appSettings: appSettings
          )
        } label: {
          InboxRow(item: item, isUnread: !store.isRead(item))
        }
      }

      if store.alertsNextPage != nil || store.updatesNextPage != nil {
        Button("notifications.loadMore") { Task { await store.loadMore() } }
          .disabled(store.isLoadingMore)
      }
    }
    .navigationTitle("title.notifications")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("notifications.markAllRead", systemImage: "checkmark.circle") {
          store.markAllRead()
        }
        .disabled(!hasUnreadItems)
      }
      ToolbarItem(placement: .primaryAction) {
        Button("action.refresh", systemImage: "arrow.clockwise") {
          Task { await store.refresh() }
        }
        .disabled(store.isLoading)
      }
    }
    .refreshable { await store.refresh() }
    .navigationDestination(item: $linkedDestination) { destination in
      NotificationLinkedItemView(
        destination: destination, store: store, profile: profile,
        keychainStore: keychainStore, appSettings: appSettings
      )
    }
    .task(id: profile.id) {
      await store.loadIfNeeded(
        profile: profile, keychainStore: keychainStore, settings: appSettings
      )
      openPendingDestination()
    }
    .onReceive(routeCenter.$pendingDestination.compactMap { $0 }) { _ in
      openPendingDestination()
    }
    .onChange(of: filter) { _, _ in
      statusFilter = .all
      severityFilter = .all
    }
  }

  private func openPendingDestination() {
    guard let destination = routeCenter.pendingDestination,
          destination.profileID == profile.id else { return }
    linkedDestination = destination
    routeCenter.pendingDestination = nil
  }
}

private struct NotificationLinkedItemView: View {
  let destination: NotificationDestination
  @ObservedObject var store: NotificationInboxStore
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings
  @State private var item: InboxItem?
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if let item {
        NotificationDetailView(
          item: item, store: store, profile: profile,
          keychainStore: keychainStore, appSettings: appSettings
        )
      } else if let errorMessage {
        ContentUnavailableView(
          "notifications.unavailable", systemImage: "bell.slash",
          description: Text(errorMessage)
        )
      } else {
        ProgressView("notifications.loading")
      }
    }
    .task(id: destination.id) {
      await store.loadIfNeeded(
        profile: profile, keychainStore: keychainStore, settings: appSettings
      )
      do {
        switch destination.kind {
        case .alert:
          item = .alert(try await store.alertDetail(id: destination.itemID))
        case .update:
          let detail = try await store.updateDetail(id: destination.itemID)
          item = .update(KomodoUpdateListItem(
            id: detail.id, operation: detail.operation,
            startTimestamp: detail.startTimestamp, success: detail.success,
            username: nil, target: detail.target, status: detail.status
          ))
        }
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct InboxRow: View {
  let item: InboxItem
  let isUnread: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .foregroundStyle(color)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(title).fontWeight(isUnread ? .semibold : .regular)
          Spacer()
          if isUnread { Circle().fill(.tint).frame(width: 7, height: 7) }
        }
        switch item {
        case .alert(let alert):
          HStack(spacing: 7) {
            Text(alert.data.data?.name ?? alert.target.type)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            Text(AlertSeverity(alert.level).title)
              .font(.caption.weight(.semibold))
              .foregroundStyle(AlertSeverity(alert.level).color)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(AlertSeverity(alert.level).color.opacity(0.12), in: Capsule())
              .fixedSize()
            Text(String(localized: alert.resolved ? "notifications.resolved" : "notifications.open"))
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize()
          }
        case .update(let update):
          Text(updateSubtitle(update))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Text(item.date, format: .dateTime.day().month().hour().minute())
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 3)
  }

  private var title: String {
    switch item {
    case .alert(let alert): return alert.data.data?.message ?? alert.data.type.readableIdentifier
    case .update(let update): return localizedOperation(update.operation)
    }
  }

  private func updateSubtitle(_ update: KomodoUpdateListItem) -> String {
    "\(update.target.type) · \(localizedUpdateStatus(update.status, success: update.success))"
  }

  private var symbol: String {
    switch item {
    case .alert(let alert): return alert.resolved ? "checkmark.circle" : AlertSeverity(alert.level).symbol
    case .update(let update): return update.status != "Complete" ? "progress.indicator" : (update.success ? "checkmark.circle" : "xmark.circle.fill")
    }
  }

  private var color: Color {
    switch item {
    case .alert(let alert): return alert.resolved ? .secondary : AlertSeverity(alert.level).color
    case .update(let update): return update.status != "Complete" ? .blue : (update.success ? .green : .red)
    }
  }
}

private struct NotificationDetailView: View {
  let item: InboxItem
  @ObservedObject var store: NotificationInboxStore
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings
  @State private var alert: KomodoAlert?
  @State private var update: KomodoUpdateDetail?
  @State private var errorMessage: String?

  var body: some View {
    List {
      switch item {
      case .alert(let summary):
        let value = alert ?? summary
        Section("notifications.alert") {
          LabeledContent("notifications.type", value: value.data.type.readableIdentifier)
          LabeledContent("field.status", value: String(localized: value.resolved ? "notifications.resolved" : "notifications.open"))
          LabeledContent("notifications.severity") {
            Text(AlertSeverity(value.level).title)
              .foregroundStyle(AlertSeverity(value.level).color)
          }
          resourceField(value.target, name: value.data.data?.name)
          LabeledContent("notifications.started", value: Date(timeIntervalSince1970: TimeInterval(value.timestamp) / 1_000).formatted())
          if let resolved = value.resolvedTimestamp {
            LabeledContent("notifications.resolvedAt", value: Date(timeIntervalSince1970: TimeInterval(resolved) / 1_000).formatted())
          }
          if let message = value.data.data?.message, !message.isEmpty { Text(message) }
          if let details = value.data.data?.details, !details.isEmpty { Text(details) }
          if let service = value.data.data?.service { LabeledContent("notifications.service", value: service) }
          if let image = value.data.data?.image { LabeledContent("notifications.image", value: image) }
        }
      case .update(let summary):
        Section("notifications.update") {
          LabeledContent("notifications.operation", value: localizedOperation(summary.operation))
          LabeledContent("field.status", value: localizedUpdateStatus(update?.status ?? summary.status, success: update?.success ?? summary.success))
          resourceField(summary.target)
          LabeledContent("notifications.started", value: Date(timeIntervalSince1970: TimeInterval(summary.startTimestamp) / 1_000).formatted())
          if let end = update?.endTimestamp {
            LabeledContent("notifications.ended", value: Date(timeIntervalSince1970: TimeInterval(end) / 1_000).formatted())
          }
          if let actor = summary.actorDisplayName {
            LabeledContent("notifications.actor", value: actor)
          }
        }
        if let update, !update.logs.isEmpty {
          Section("notifications.stages") {
            ForEach(Array(update.logs.enumerated()), id: \.offset) { _, stage in
              Label(localizedStage(stage.stage), systemImage: stage.success ? "checkmark.circle" : "xmark.circle")
            }
          }
        }
      }
      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("title.notifications")
    .task(id: item.id) {
      store.markRead(item)
      do {
        switch item {
        case .alert(let value): alert = try await store.alertDetail(id: value.id)
        case .update(let value): update = try await store.updateDetail(id: value.id)
        }
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  @ViewBuilder
  private func resourceField(_ target: KomodoNoticeTarget, name: String? = nil) -> some View {
    if !target.id.isEmpty && (target.type == "Server" || target.type == "Stack") {
      NavigationLink {
        NotificationResourceDestinationView(
          target: target, store: store, profile: profile,
          keychainStore: keychainStore, appSettings: appSettings
        )
      } label: {
        LabeledContent("notifications.resource", value: resourceDescription(target, name: name))
      }
    } else {
      LabeledContent("notifications.resource", value: resourceDescription(target, name: name))
    }
  }
}

private struct NotificationResourceDestinationView: View {
  let target: KomodoNoticeTarget
  @ObservedObject var store: NotificationInboxStore
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings
  @State private var server: ServerListItem?
  @State private var stack: StackListItem?
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if let server {
        ServerDetailView(
          summary: server, profile: profile, keychainStore: keychainStore,
          appSettings: appSettings
        )
      } else if let stack {
        StackDetailView(
          summary: stack, profile: profile, keychainStore: keychainStore,
          appSettings: appSettings
        )
      } else if isLoading {
        ProgressView("notifications.loadingResource")
      } else {
        ContentUnavailableView {
          Label("notifications.resourceUnavailable", systemImage: "questionmark.square.dashed")
        } description: {
          if let errorMessage { Text(errorMessage) }
        }
      }
    }
    .task(id: "\(target.type):\(target.id)") {
      isLoading = true
      errorMessage = nil
      server = nil
      stack = nil
      do {
        if target.type == "Server" {
          server = try await store.serverSummary(idOrName: target.id)
        } else if target.type == "Stack" {
          stack = try await store.stackSummary(idOrName: target.id)
        }
      } catch {
        errorMessage = error.localizedDescription
      }
      isLoading = false
    }
  }
}

private enum AlertSeverity {
  case ok
  case warning
  case critical
  case unknown(String)

  init(_ rawValue: String) {
    switch rawValue.uppercased() {
    case "OK": self = .ok
    case "WARNING": self = .warning
    case "CRITICAL": self = .critical
    default: self = .unknown(rawValue)
    }
  }

  var title: String {
    switch self {
    case .ok: String(localized: "notifications.severity.ok")
    case .warning: String(localized: "notifications.severity.warning")
    case .critical: String(localized: "notifications.severity.critical")
    case .unknown(let value): value.readableIdentifier
    }
  }

  var color: Color {
    switch self {
    case .ok: .green
    case .warning: .orange
    case .critical: .red
    case .unknown: .secondary
    }
  }

  var symbol: String {
    switch self {
    case .ok: "info.circle"
    case .warning: "exclamationmark.triangle.fill"
    case .critical: "exclamationmark.octagon.fill"
    case .unknown: "bell.fill"
    }
  }
}

private func localizedUpdateStatus(_ status: String, success: Bool) -> String {
  switch status {
  case "Complete":
    return String(localized: success ? "notifications.succeeded" : "notifications.failed")
  case "Queued":
    return String(localized: "notifications.queued")
  case "InProgress":
    return String(localized: "notifications.running")
  default:
    return status.readableIdentifier
  }
}

private func localizedOperation(_ operation: String) -> String {
  switch operation {
  case "StartStack": String(localized: "action.startStack")
  case "DeployStack": String(localized: "action.deploy")
  case "PullStack": String(localized: "action.pullImages")
  case "RestartStack": String(localized: "action.restart")
  case "PauseStack": String(localized: "action.pause")
  case "ResumeStack": String(localized: "action.resume")
  case "StopStack": String(localized: "action.stopStack")
  case "DestroyStack": String(localized: "action.destroy")
  case "StartAllContainers": String(localized: "action.startAllContainers")
  case "RestartAllContainers": String(localized: "action.restartAllContainers")
  case "PauseAllContainers": String(localized: "action.pauseAllContainers")
  case "ResumeAllContainers": String(localized: "action.resumeAllContainers")
  case "StopAllContainers": String(localized: "action.stopAllContainers")
  case "PruneBuildx": String(localized: "action.pruneBuildx")
  case "PruneSystem": String(localized: "action.pruneSystem")
  case "StartContainer": String(localized: "action.start")
  case "RestartContainer": String(localized: "action.restart")
  case "PauseContainer": String(localized: "action.pause")
  case "ResumeContainer": String(localized: "action.resume")
  case "StopContainer": String(localized: "action.stop")
  case "DestroyContainer": String(localized: "action.removeContainer")
  case "RotateAllServerKeys": String(localized: "notifications.operation.rotateAllServerKeys")
  default: operation.readableIdentifier
  }
}

private func localizedStage(_ stage: String) -> String {
  switch stage {
  case "Deploy": String(localized: "action.deploy")
  case "Pull Images": String(localized: "action.pullImages")
  case "Start": String(localized: "action.start")
  case "Restart": String(localized: "action.restart")
  case "Pause": String(localized: "action.pause")
  case "Resume": String(localized: "action.resume")
  case "Stop": String(localized: "action.stop")
  case "Rotate Server Keys": String(localized: "notifications.stage.rotateServerKeys")
  default: stage
  }
}

private func resourceDescription(_ target: KomodoNoticeTarget, name: String? = nil) -> String {
  let label = name ?? target.id
  if label.isEmpty || label.caseInsensitiveCompare(target.type) == .orderedSame {
    return target.type.readableIdentifier
  }
  return "\(target.type.readableIdentifier) · \(label)"
}

private extension String {
  var readableIdentifier: String {
    replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
      .replacingOccurrences(of: "_", with: " ")
      .capitalized
  }
}

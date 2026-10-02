import Charts
import SwiftUI

enum ResourceSection: String, CaseIterable, Identifiable {
  case servers
  case stacks
  case containers

  var id: Self { self }
  var title: LocalizedStringKey {
    switch self {
    case .servers: "title.servers"
    case .stacks: "title.stacks"
    case .containers: "title.containers"
    }
  }
}

struct ResourceBrowserView: View {
  @Environment(\.scenePhase) private var scenePhase
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings
  @State private var section: ResourceSection
  @StateObject private var liveUpdates = KomodoLiveUpdateController()

  init(profile: ServerProfile, keychainStore: KeychainStore, appSettings: AppSettings) {
    self.profile = profile
    self.keychainStore = keychainStore
    self.appSettings = appSettings
    _section = State(
      initialValue: ResourceSection(rawValue: appSettings.defaultResourceSection.rawValue) ?? .stacks
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      Picker("resource.section", selection: $section) {
        ForEach(ResourceSection.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      .padding()
      Divider()

      Group {
        switch section {
        case .servers:
          ServerListView(
            profile: profile,
            keychainStore: keychainStore,
            appSettings: appSettings
          )
        case .stacks:
          StackListView(
            profile: profile,
            keychainStore: keychainStore,
            appSettings: appSettings
          )
        case .containers:
          ContainerListView(
            profile: profile,
            keychainStore: keychainStore,
            appSettings: appSettings
          )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .environmentObject(liveUpdates)
    .task(id: profile.id) {
      guard scenePhase == .active else { return }
      await connectLiveUpdates()
    }
    .task(id: refreshScheduleID) { configureRefreshIntervals() }
    .onChange(of: scenePhase) { _, newPhase in
      guard appSettings.liveUpdatesEnabled else {
        liveUpdates.stop()
        return
      }
      if newPhase == .active {
        Task { await connectLiveUpdates() }
      } else {
        liveUpdates.stop()
      }
    }
    .onChange(of: appSettings.liveUpdatesEnabled) { _, enabled in
      if enabled, scenePhase == .active {
        Task { await connectLiveUpdates() }
      } else {
        liveUpdates.stop()
      }
    }
    .onDisappear {
      liveUpdates.stop()
      liveUpdates.stopRefreshIntervals()
    }
  }

  private var refreshScheduleID: String {
    "\(scenePhase)-\(appSettings.metricsAutoRefresh)-\(appSettings.metricsRefreshInterval.rawValue)-\(appSettings.logRefreshInterval.rawValue)"
  }

  @MainActor private func configureRefreshIntervals() {
    liveUpdates.configureRefreshIntervals(
      metricsSeconds: scenePhase == .active && appSettings.metricsAutoRefresh
        ? appSettings.metricsRefreshInterval.rawValue : nil,
      logsSeconds: scenePhase == .active ? appSettings.logRefreshInterval.seconds : nil
    )
  }

  @MainActor
  private func connectLiveUpdates() async {
    guard appSettings.liveUpdatesEnabled else {
      liveUpdates.stop()
      return
    }
    do {
      guard let credentials = try await keychainStore.credentials(
        for: profile.credentialAccount
      ), credentials.authenticationKind == profile.authenticationKind else {
        throw KeychainStoreError.invalidCredentialData
      }
      liveUpdates.start(
        address: try profile.address,
        authentication: credentials.authentication
      )
    } catch {
      liveUpdates.stop()
    }
  }
}

struct LiveConnectionStatusButton: View {
  @EnvironmentObject private var liveUpdates: KomodoLiveUpdateController
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings

  @State private var isPresented = false
  @State private var retryError: String?

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: symbol)
        .foregroundStyle(color)
    }
    .accessibilityLabel(title)
    .popover(isPresented: $isPresented) {
      VStack(alignment: .leading, spacing: 12) {
        Label(title, systemImage: symbol)
          .font(.headline)
          .foregroundStyle(color)
        Text(profile.name)
          .font(.subheadline)
        if !appSettings.liveUpdatesEnabled {
          Text("status.liveUpdatesDisabled")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        LabeledContent(
          "settings.section.metrics",
          value: appSettings.metricsAutoRefresh
            ? appSettings.metricsRefreshInterval.title : String(localized: "settings.refresh.onEvents")
        )
        LabeledContent(
          "settings.section.logs",
          value: appSettings.logRefreshInterval.title
        )
        if let retryError {
          Text(retryError)
            .font(.caption)
            .foregroundStyle(.red)
        } else if liveUpdates.loginRejected {
          Text("status.loginRejected")
            .font(.caption)
            .foregroundStyle(.red)
        }
        Button("action.reconnect", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
          Task { await reconnect() }
        }
        .disabled(!appSettings.liveUpdatesEnabled || liveUpdates.status == .connecting)
      }
      .padding()
      .frame(minWidth: 260)
      .presentationCompactAdaptation(.popover)
    }
  }

  private var title: LocalizedStringKey {
    switch liveUpdates.status {
    case .connecting: "status.connecting"
    case .live: "status.live"
    case .offline: "status.offline"
    }
  }

  private var symbol: String {
    switch liveUpdates.status {
    case .connecting: "circle.dotted"
    case .live: "circle.fill"
    case .offline: "exclamationmark.circle.fill"
    }
  }

  private var color: Color {
    switch liveUpdates.status {
    case .connecting: .orange
    case .live: .green
    case .offline: .red
    }
  }

  @MainActor
  private func reconnect() async {
    do {
      guard let credentials = try await keychainStore.credentials(
        for: profile.credentialAccount
      ), credentials.authenticationKind == profile.authenticationKind else {
        throw KeychainStoreError.invalidCredentialData
      }
      liveUpdates.reconnect(
        address: try profile.address,
        authentication: credentials.authentication
      )
      retryError = nil
    } catch {
      retryError = error.localizedDescription
    }
  }
}

struct ResourceListRow: View {
  let title: String
  let subtitle: String?
  let status: String?
  let symbol: String
  let symbolColor: Color

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .foregroundStyle(symbolColor)
        .frame(width: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer()

      if let status, !status.isEmpty {
        Text(status)
          .font(.caption.weight(.semibold).monospacedDigit())
          .foregroundStyle(symbolColor)
      }
    }
  }
}

func localizedResourceState(_ rawState: String) -> String {
  switch rawState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
  case "running", "healthy": String(localized: "state.running")
  case "paused": String(localized: "state.paused")
  case "stopped", "exited": String(localized: "state.stopped")
  case "created": String(localized: "state.created")
  case "restarting": String(localized: "state.restarting")
  case "deploying": String(localized: "state.deploying")
  case "removing": String(localized: "state.removing")
  case "unhealthy": String(localized: "state.unhealthy")
  case "dead": String(localized: "state.dead")
  case "down": String(localized: "state.down")
  case "failed": String(localized: "state.failed")
  case "error": String(localized: "state.error")
  default: String(localized: "state.unknown")
  }
}

func resourceStateSymbol(_ rawState: String) -> String {
  switch ResourceStateCategory(rawState) {
  case .running: "checkmark.circle.fill"
  case .paused, .stopped: "pause.circle.fill"
  case .attention: "exclamationmark.triangle.fill"
  case .transitioning: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
  case .other: "questionmark.circle.fill"
  }
}

func resourceStateColor(_ rawState: String) -> Color {
  switch ResourceStateCategory(rawState) {
  case .running: .green
  case .attention: .red
  case .transitioning: .blue
  case .paused, .stopped, .other: .secondary
  }
}

enum ResourceStateCategory {
  case running
  case paused
  case stopped
  case attention
  case transitioning
  case other

  init(_ rawState: String) {
    switch rawState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "running", "healthy": self = .running
    case "paused": self = .paused
    case "stopped", "exited", "created": self = .stopped
    case "failed", "error", "unhealthy", "dead", "down": self = .attention
    case "deploying", "restarting", "removing": self = .transitioning
    default: self = .other
    }
  }
}

struct ResourceOverviewCounts: Equatable {
  let total: Int
  let active: Int
  let problems: Int

  init<S: Sequence>(states: S) where S.Element == String {
    var total = 0
    var active = 0
    var problems = 0
    for state in states {
      total += 1
      switch ResourceStateCategory(state) {
      case .running: active += 1
      case .attention: problems += 1
      case .paused, .stopped, .transitioning, .other: break
      }
    }
    self.total = total
    self.active = active
    self.problems = problems
  }
}

struct ResourceStatusSummary: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let counts: ResourceOverviewCounts
  let isStale: Bool
  let showTotal: () -> Void
  let showActive: () -> Void
  let showProblems: () -> Void

  var body: some View {
    VStack(alignment: .center, spacing: 6) {
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: 8),
          count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
        ),
        alignment: .center,
        spacing: 8
      ) {
        Button(action: showTotal) {
          metric(counts.total, title: "summary.total", symbol: "square.stack.3d.up", color: .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overview-total")
        Button(action: showActive) {
          metric(counts.active, title: "summary.active", symbol: "checkmark.circle.fill", color: .green)
        }
        .buttonStyle(.plain)
        .disabled(counts.active == 0)
        .accessibilityIdentifier("overview-active")
        Button(action: showProblems) {
          metric(
            counts.problems,
            title: "summary.problems",
            symbol: "exclamationmark.triangle.fill",
            color: counts.problems > 0 ? .red : .secondary
          )
        }
        .buttonStyle(.plain)
        .disabled(counts.problems == 0)
        .accessibilityIdentifier("overview-problems")
      }
      if isStale {
        Label("summary.refreshFailed", systemImage: "clock.badge.exclamationmark")
          .font(.caption)
          .foregroundStyle(Color.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .foregroundStyle(.primary)
  }

  private func metric(
    _ value: Int,
    title: LocalizedStringKey,
    symbol: String,
    color: Color
  ) -> some View {
    VStack(alignment: .center, spacing: 2) {
      HStack(spacing: 5) {
        Image(systemName: symbol)
          .foregroundStyle(color)
          .accessibilityHidden(true)
        Text(value.formatted())
          .foregroundStyle(color)
          .font(.headline.monospacedDigit())
      }
      Text(title)
        .font(.caption)
        .foregroundStyle(Color.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

@MainActor
func makeKomodoClient(profile: ServerProfile, keychainStore: KeychainStore) async throws
  -> KomodoAPIClient
{
#if DEBUG
  if ScreenshotDemo.enabled {
    return ScreenshotDemo.makeClient()
  }
#endif
  guard let credentials = try await keychainStore.credentials(for: profile.credentialAccount),
        credentials.authenticationKind == profile.authenticationKind else {
    throw KeychainStoreError.invalidCredentialData
  }
  return KomodoAPIClient(address: try profile.address, authentication: credentials.authentication)
}

private enum ServerStateFilter: String, CaseIterable, Identifiable {
  case all
  case online
  case unavailable
  case disabled

  var id: Self { self }
  var title: LocalizedStringKey {
    switch self {
    case .all: "filter.allServers"
    case .online: "serverState.ok"
    case .unavailable: "filter.unavailableServers"
    case .disabled: "serverState.disabled"
    }
  }

  func includes(_ state: KomodoServerState) -> Bool {
    switch (self, state) {
    case (.all, _), (.online, .ok), (.unavailable, .notOk), (.disabled, .disabled):
      true
    case (.unavailable, .unknown(_)):
      true
    default:
      false
    }
  }
}

private enum ServerResourceFilter: String, CaseIterable, Identifiable {
  case all
  case stacks
  case containers

  var id: Self { self }
  var title: LocalizedStringKey {
    switch self {
    case .all: "filter.allServers"
    case .stacks: "filter.serversWithStacks"
    case .containers: "filter.serversWithContainers"
    }
  }
}

struct ServerListView: View {
  @EnvironmentObject private var liveUpdates: KomodoLiveUpdateController
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings
  @State private var servers: [ServerListItem] = []
  @State private var searchText = ""
  @State private var stateFilter: ServerStateFilter = .all
  @State private var resourceFilter: ServerResourceFilter = .all
  @State private var selectedTags: Set<String> = []
  @State private var stackCountsByServer: [String: Int]?
  @State private var containerCountsByServer: [String: Int]?
  @State private var errorMessage: String?
  @State private var isLoading = true
  @State private var showingCreate = false

  var body: some View {
    Group {
      if isLoading, servers.isEmpty { ProgressView("status.loadingServers") }
      else if let errorMessage, servers.isEmpty {
        ContentUnavailableView {
          Label("title.serversUnavailable", systemImage: "exclamationmark.triangle")
        } description: { Text(errorMessage) } actions: {
          Button("action.retry") { Task { await load() } }
        }
      } else {
        List {
          if filteredServers.isEmpty {
            if searchText.isEmpty, stateFilter == .all, resourceFilter == .all, selectedTags.isEmpty {
              ContentUnavailableView(
                "message.noServers",
                systemImage: "server.rack",
                description: Text("message.noServers.description")
              )
            } else if !searchText.isEmpty {
              ContentUnavailableView.search(text: searchText)
            } else {
              ContentUnavailableView(
                "message.noServersMatchFilters",
                systemImage: "line.3.horizontal.decrease.circle"
              )
            }
          } else {
            ForEach(filteredServers) { server in
              NavigationLink {
                ServerDetailView(
                  summary: server,
                  profile: profile,
                  keychainStore: keychainStore,
                  appSettings: appSettings
                )
                  .environmentObject(liveUpdates)
              } label: {
                ServerSummaryRow(
                  server: server,
                  stackCount: stackCountsByServer.map { $0[server.name] ?? 0 },
                  containerCount: containerCountsByServer.map {
                    $0[server.id] ?? $0[server.name] ?? 0
                  }
                )
              }
            }
          }
          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.secondary)
          }
        }
        .refreshable { await load() }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("title.servers")
    .searchable(text: $searchText, prompt: "action.searchServers")
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Menu {
          Picker("filter.serverState", selection: $stateFilter) {
            ForEach(ServerStateFilter.allCases) { filter in
              Text(filter.title).tag(filter)
            }
          }
          if stackCountsByServer != nil, containerCountsByServer != nil {
            Picker("filter.relatedResources", selection: $resourceFilter) {
              ForEach(ServerResourceFilter.allCases) { filter in
                Text(filter.title).tag(filter)
              }
            }
          }
          if !availableTags.isEmpty {
            Section("filter.tags") {
              ForEach(availableTags, id: \.self) { tag in
                Button {
                  if selectedTags.contains(tag) {
                    selectedTags.remove(tag)
                  } else {
                    selectedTags.insert(tag)
                  }
                } label: {
                  if selectedTags.contains(tag) {
                    Label(tag, systemImage: "checkmark")
                  } else {
                    Text(tag)
                  }
                }
              }
              if !selectedTags.isEmpty {
                Button("filter.clearTags") { selectedTags.removeAll() }
              }
            }
          }
          if hasActiveFilters {
            Button("filter.reset") { resetFilters() }
          }
        } label: {
          Label(
            "filter.servers",
            systemImage: hasActiveFilters
              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
          )
        }
        Button("action.addServer", systemImage: "plus") { showingCreate = true }
        LiveConnectionStatusButton(
          profile: profile,
          keychainStore: keychainStore,
          appSettings: appSettings
        )
        #if os(macOS)
        Button("action.refresh", systemImage: "arrow.clockwise") { Task { await load() } }
          .disabled(isLoading)
          .keyboardShortcut("r", modifiers: .command)
        #endif
      }
    }
    .sheet(isPresented: $showingCreate) {
      NavigationStack {
        ServerEditorView(profile: profile, keychainStore: keychainStore) {
          showingCreate = false
          Task { await load() }
        }
      }
    }
    .task(id: profile.id) { await load() }
    .onChange(of: liveUpdates.metricsRefreshGeneration) { _, _ in
      if !isLoading { Task { await refreshServerSummaries() } }
    }
    .onReceive(liveUpdates.$latestEvent.compactMap { $0 }) { event in
      if event.affects(.server) || event.affects(.stack) || event.affects(.deployment) {
        Task { await load() }
      }
    }
    .onChange(of: liveUpdates.refreshGeneration) { _, _ in
      Task { await load() }
    }
  }

  private var filteredServers: [ServerListItem] {
    servers.filter { server in
      stateFilter.includes(server.info.state)
        && includesRelatedResources(server)
        && selectedTags.isSubset(of: Set(server.tags))
        && (searchText.isEmpty
          || server.name.localizedCaseInsensitiveContains(searchText)
          || server.info.region.localizedCaseInsensitiveContains(searchText)
          || (server.info.address?.localizedCaseInsensitiveContains(searchText) == true)
          || (server.info.externalAddress?.localizedCaseInsensitiveContains(searchText) == true)
          || server.tags.contains { $0.localizedCaseInsensitiveContains(searchText) })
    }
  }

  private func includesRelatedResources(_ server: ServerListItem) -> Bool {
    switch resourceFilter {
    case .all:
      true
    case .stacks:
      (stackCountsByServer?[server.name] ?? 0) > 0
    case .containers:
      (containerCountsByServer?[server.id] ?? containerCountsByServer?[server.name] ?? 0) > 0
    }
  }

  private var availableTags: [String] {
    Array(Set(servers.flatMap(\.tags)).union(selectedTags)).sorted {
      $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }
  }

  private var hasActiveFilters: Bool {
    stateFilter != .all || resourceFilter != .all || !selectedTags.isEmpty
  }

  private func resetFilters() {
    stateFilter = .all
    resourceFilter = .all
    selectedTags.removeAll()
  }

  @MainActor private func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      async let loadedServers = client.listAllServers()
      async let loadedStacks = loadAllStacks(using: client)
      async let loadedContainers = loadAllContainers(using: client)
      servers = try await loadedServers
      stackCountsByServer = await loadedStacks
      containerCountsByServer = await loadedContainers
      if (resourceFilter == .stacks && stackCountsByServer == nil)
        || (resourceFilter == .containers && containerCountsByServer == nil) {
        resourceFilter = .all
      }
      errorMessage = nil
    } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
  }

  @MainActor private func refreshServerSummaries() async {
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      servers = try await client.listAllServers()
      errorMessage = nil
    } catch is CancellationError {} catch {
      errorMessage = error.localizedDescription
    }
  }

  private func loadAllStacks(using client: KomodoAPIClient) async -> [String: Int]? {
    do {
      var result: [StackListItem] = []
      var page = 0
      repeat {
        let next = try await client.listStacks(page: page, limit: 100)
        result.append(contentsOf: next)
        page += 1
        if next.count < 100 { break }
      } while !Task.isCancelled
      return result.reduce(into: [String: Int]()) { counts, stack in
        guard !stack.info.serverName.isEmpty else { return }
        counts[stack.info.serverName, default: 0] += 1
      }
    } catch {
      return nil
    }
  }

  private func loadAllContainers(using client: KomodoAPIClient) async -> [String: Int]? {
    do {
      var result: [ContainerListItem] = []
      var page = 0
      repeat {
        let next = try await client.listAllContainers(page: page, limit: 100)
        result.append(contentsOf: next)
        page += 1
        if next.count < 100 { break }
      } while !Task.isCancelled
      return result.reduce(into: [String: Int]()) { counts, container in
        for identifier in Set([container.serverID, container.serverName].compactMap { $0 }) {
          counts[identifier, default: 0] += 1
        }
      }
    } catch {
      return nil
    }
  }
}

private struct ServerSummaryRow: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  let server: ServerListItem
  let stackCount: Int?
  let containerCount: Int?

  private var currentStats: MinimalSystemStats? {
    server.info.state == .ok ? server.info.stats : nil
  }

  private var status: (title: LocalizedStringKey, color: Color) {
    switch server.info.state {
    case .ok: ("serverState.ok", .green)
    case .notOk: ("serverState.notOk", .red)
    case .disabled: ("serverState.disabled", .secondary)
    case .unknown: ("serverState.unavailable", .orange)
    }
  }

  private var location: String {
    [server.info.region, server.info.address ?? ""]
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
  }

  private var footer: String {
    ([server.info.version.map { "Komodo \($0)" }] + server.tags.map { "#\($0)" })
      .compactMap { $0 }
      .joined(separator: " · ")
  }

  private var cpuValue: String? {
    guard let currentStats, currentStats.availableFields.contains("cpu_perc") else { return nil }
    return currentStats.cpuPercent.formatted(.number.precision(.fractionLength(1))) + " %"
  }

  private var memoryValue: String? {
    guard let currentStats,
      currentStats.availableFields.isSuperset(of: ["mem_used_gb", "mem_total_gb"]),
      currentStats.memoryTotalGB > 0
    else { return nil }
    let used = currentStats.memoryUsedGB.formatted(.number.precision(.fractionLength(1)))
    let total = currentStats.memoryTotalGB.formatted(.number.precision(.fractionLength(0...1)))
    return String(format: String(localized: "server.summary.memoryValue"), used, total)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 10) {
        Image(systemName: "server.rack")
          .foregroundStyle(status.color)
          .frame(width: 24)
          .accessibilityHidden(true)
        Text(server.name)
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Spacer(minLength: 4)
        HStack(spacing: 5) {
          Circle()
            .fill(status.color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
          Text(status.title)
        }
        .font(.caption)
        .foregroundStyle(status.color)
        .fixedSize(horizontal: true, vertical: false)
      }

      if !location.isEmpty {
        Text(location)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.leading, 34)
      }

      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), alignment: .leading),
          count: horizontalSizeClass == .compact ? 2 : 4
        ),
        alignment: .leading,
        spacing: 9
      ) {
        metric("field.cpu", value: cpuValue)
        metric("server.summary.ram", value: memoryValue)
        metric("title.stacks", value: stackCount.map(String.init))
        metric("title.containers", value: containerCount.map(String.init))
      }
      .padding(.leading, 34)

      if !footer.isEmpty {
        Text(footer)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.leading, 34)
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private func metric(_ title: LocalizedStringKey, value: String?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value ?? "—")
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityLabel(value ?? String(localized: "metrics.unavailable"))
    }
  }
}

private enum ServerResourceAction: String, Identifiable {
  case startAll
  case restartAll
  case pauseAll
  case resumeAll
  case stopAll
  case pruneBuildx
  case pruneSystem
  case deleteDefinition

  var id: String { rawValue }

  var title: String {
    switch self {
    case .startAll: String(localized: "action.startAllContainers")
    case .restartAll: String(localized: "action.restartAllContainers")
    case .pauseAll: String(localized: "action.pauseAllContainers")
    case .resumeAll: String(localized: "action.resumeAllContainers")
    case .stopAll: String(localized: "action.stopAllContainers")
    case .pruneBuildx: String(localized: "action.pruneBuildx")
    case .pruneSystem: String(localized: "action.pruneSystem")
    case .deleteDefinition: String(localized: "action.deleteServer")
    }
  }

  var symbol: String {
    switch self {
    case .startAll, .resumeAll: "play.fill"
    case .restartAll: "arrow.clockwise"
    case .pauseAll: "pause.fill"
    case .stopAll: "stop.fill"
    case .pruneBuildx: "hammer"
    case .pruneSystem, .deleteDefinition: "trash"
    }
  }

  var isDestructive: Bool {
    self == .stopAll || self == .pruneSystem || self == .deleteDefinition
  }
}

struct ServerDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var liveUpdates: KomodoLiveUpdateController
  let summary: ServerListItem
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings
  @State private var server: ServerDetail?
  @State private var serverState: KomodoServerState?
  @State private var stats: SystemStats?
  @State private var history: [SystemStatsRecord] = []
  @State private var containers: [ContainerListItem] = []
  @State private var stacks: [StackListItem] = []
  @State private var errorMessage: String?
  @State private var metricsErrorMessage: String?
  @State private var stacksErrorMessage: String?
  @State private var containersErrorMessage: String?
  @State private var historyErrorMessage: String?
  @State private var isLoadingDetails = true
  @State private var isLoadingMetrics = true
  @State private var isLoadingStacks = true
  @State private var isLoadingContainers = true
  @State private var isLoadingHistory = true
  @State private var editingServer: ServerDetail?
  @State private var pendingAction: ServerResourceAction?
  @State private var activeAction: ServerResourceAction?
  @State private var actionError: String?
  @State private var actionNotice: String?
  @State private var showsAllStacks = false
  @State private var showsAllContainers = false
  @State private var granularity = "15-min"

  var body: some View {
    List {
      if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
      Section("section.overview") {
        if let actionNotice {
          Label(actionNotice, systemImage: "paperplane")
            .foregroundStyle(.secondary)
        }
        LabeledContent("field.status", value: localizedServerState(serverState ?? summary.info.state))
        if let version = summary.info.version { LabeledContent("field.version", value: version) }
        if let overviewAddress { LabeledContent("field.address", value: overviewAddress) }
        if let publicIP = nonEmpty(summary.info.publicIP) {
          LabeledContent("field.publicIP", value: publicIP)
        }
        if let overviewRegion { LabeledContent("field.region", value: overviewRegion) }
        NavigationLink {
          if let server {
            ServerConfigurationView(configuration: server.config.displayConfiguration)
          }
        } label: {
          Label("title.configuration", systemImage: "slider.horizontal.3")
        }
        .disabled(server == nil)
        .accessibilityIdentifier("server-configuration-link")
      }
      if let stats {
        Section("section.currentMetrics") {
          if let metricsErrorMessage {
            Label(metricsErrorMessage, systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if stats.availableFields.contains("cpu_perc") {
            MetricRow(title: "field.cpu", value: stats.cpuPercent, unit: "%")
          } else {
            LabeledContent("field.cpu", value: String(localized: "metrics.unavailable"))
          }
          if stats.availableFields.contains("mem_used_gb"), stats.availableFields.contains("mem_total_gb") {
            MetricRow(title: "field.memory", value: stats.memoryUsedGB, total: stats.memoryTotalGB, unit: "GB")
          } else {
            LabeledContent("field.memory", value: String(localized: "metrics.unavailable"))
          }
          if stats.availableFields.contains("load_average") {
            LabeledContent("field.loadAverage", value: String(format: "%.2f · %.2f · %.2f", stats.loadAverage.one, stats.loadAverage.five, stats.loadAverage.fifteen))
          } else {
            LabeledContent("field.loadAverage", value: String(localized: "metrics.unavailable"))
          }
          if stats.availableFields.contains("network_ingress_bytes") {
            LabeledContent("field.networkIn", value: ByteCountFormatter.string(fromByteCount: stats.networkIngressBytes, countStyle: .file))
          } else {
            LabeledContent("field.networkIn", value: String(localized: "metrics.unavailable"))
          }
          if stats.availableFields.contains("network_egress_bytes") {
            LabeledContent("field.networkOut", value: ByteCountFormatter.string(fromByteCount: stats.networkEgressBytes, countStyle: .file))
          } else {
            LabeledContent("field.networkOut", value: String(localized: "metrics.unavailable"))
          }
          if stats.availableFields.contains("disks") {
            ForEach(stats.disks) { disk in
              MetricRow(title: LocalizedStringKey(disk.mount), value: disk.usedGB, total: disk.totalGB, unit: "GB")
            }
          } else {
            LabeledContent("field.disk", value: String(localized: "metrics.unavailable"))
          }
          if statsAreStale(stats) {
            Label("message.metricsStale", systemImage: "clock.badge.exclamationmark")
              .font(.caption)
              .foregroundStyle(.secondary)
            if stats.refreshTimestamp > 0 {
              LabeledContent("field.lastMeasurement", value: measurementDate(stats.refreshTimestamp).formatted(date: .abbreviated, time: .standard))
            }
          }
        }
      } else if !isLoadingMetrics {
        Section("section.currentMetrics") {
          Text(metricsErrorMessage ?? String(localized: "message.metricsUnavailable"))
            .foregroundStyle(.secondary)
        }
      } else {
        Section("section.currentMetrics") { CenteredLoadingRow("status.loadingMetrics") }
      }
      Section("section.history") {
        Picker("field.granularity", selection: $granularity) {
          Text("metrics.fifteenMinutes").tag("15-min")
          Text("metrics.oneHour").tag("1-hr")
          Text("metrics.oneDay").tag("1-day")
        }
        .pickerStyle(.segmented)

        if isLoadingHistory, history.isEmpty {
          CenteredLoadingRow("status.loadingHistory")
        } else if history.isEmpty {
          Text(historyErrorMessage ?? String(localized: "message.historyUnavailable"))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
        } else {
          if historyContainsCPU {
            Chart(history) { point in
              if point.availableFields.contains("cpu_perc"), point.availableFields.contains("ts") {
                LineMark(x: .value("Time", measurementDate(point.timestamp)),
                         y: .value("CPU", point.cpuPercent))
                  .foregroundStyle(.green)
              }
            }
            .chartYAxisLabel("CPU %")
            .frame(minHeight: 180)
          } else {
            LabeledContent("field.cpu", value: String(localized: "metrics.unavailable"))
          }
          if historyIsStale {
            Label("message.metricsStale", systemImage: "clock.badge.exclamationmark")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if isLoadingHistory {
            ProgressView()
              .controlSize(.small)
              .frame(maxWidth: .infinity, alignment: .center)
              .accessibilityLabel("status.loadingHistory")
          } else if let historyErrorMessage {
            Label(historyErrorMessage, systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      Section("title.stacks") {
        if isLoadingStacks, stacks.isEmpty {
          CenteredLoadingRow("status.loadingStacks")
        } else if let stacksErrorMessage, stacks.isEmpty {
          Label(stacksErrorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        } else if stacks.isEmpty {
          Text("message.noStacks").foregroundStyle(.secondary)
        }
        ForEach(stacks.prefix(showsAllStacks ? stacks.count : 3)) { stack in
          NavigationLink {
            StackDetailView(
              summary: stack,
              profile: profile,
              keychainStore: keychainStore,
              appSettings: appSettings
            )
              .environmentObject(liveUpdates)
          } label: { Text(stack.name) }
        }
        if stacks.count > 3 {
          Button {
            withAnimation { showsAllStacks.toggle() }
          } label: {
            Label(
              showsAllStacks ? "action.showFewerStacks" : "action.showMoreStacks",
              systemImage: showsAllStacks ? "chevron.up" : "chevron.down"
            )
          }
          .accessibilityIdentifier("server-stacks-toggle")
        }
        if let stacksErrorMessage, !stacks.isEmpty {
          Label(stacksErrorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        }
      }
      Section("title.containers") {
        if isLoadingContainers, containers.isEmpty {
          CenteredLoadingRow("status.loadingContainers")
        } else if let containersErrorMessage, containers.isEmpty {
          Label(containersErrorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        } else if containers.isEmpty {
          Text("message.noContainers").foregroundStyle(.secondary)
        }
        ForEach(containers.prefix(showsAllContainers ? containers.count : 3)) { container in
          NavigationLink {
            ContainerDetailView(
              container: container,
              profile: profile,
              keychainStore: keychainStore,
              appSettings: appSettings
            )
              .environmentObject(liveUpdates)
          } label: { ContainerRow(container: container) }
        }
        if containers.count > 3 {
          Button {
            withAnimation { showsAllContainers.toggle() }
          } label: {
            Label(
              showsAllContainers ? "action.showFewerContainers" : "action.showMoreContainers",
              systemImage: showsAllContainers ? "chevron.up" : "chevron.down"
            )
          }
          .accessibilityIdentifier("server-containers-toggle")
        }
        if let containersErrorMessage, !containers.isEmpty {
          Label(containersErrorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        }
      }
    }
    .refreshable { await load() }
    .navigationTitle(server?.name ?? summary.name)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        ServerActionMenu(
          containerActions: availableContainerActions,
          canOperate: !isLoadingContainers && containersErrorMessage == nil
            && (serverState ?? summary.info.state) == .ok,
          canMaintain: (serverState ?? summary.info.state) == .ok,
          isEnabled: server != nil && !isLoadingDetails && !isLoadingStacks && !isLoadingContainers,
          activeAction: activeAction,
          edit: { editingServer = server },
          perform: { pendingAction = $0 }
        )
        LiveConnectionStatusButton(
          profile: profile,
          keychainStore: keychainStore,
          appSettings: appSettings
        )
        #if os(macOS)
        Button("action.refresh", systemImage: "arrow.clockwise") { Task { await load() } }
          .disabled(isLoading || activeAction != nil)
          .keyboardShortcut("r", modifiers: .command)
        #endif
      }
    }
    .confirmationDialog(
      pendingAction?.title ?? String(localized: "title.serverActions"),
      isPresented: confirmsAction,
      titleVisibility: .visible,
      presenting: pendingAction
    ) { action in
      Button(action.title, role: action.isDestructive ? .destructive : nil) {
        Task { await runAction(action) }
      }
      Button("action.cancel", role: .cancel) {}
    } message: { action in
      Text(confirmationMessage(for: action))
    }
    .alert("alert.actionFailed", isPresented: showsActionError) {
      Button("action.ok") { actionError = nil }
    } message: {
      Text(actionError ?? String(localized: "error.unknown"))
    }
    .sheet(item: $editingServer) { selectedServer in
      NavigationStack {
        ServerEditorView(profile: profile, keychainStore: keychainStore, server: selectedServer, summary: summary) {
          editingServer = nil
          Task { await load() }
        }
      }
    }
    .task(id: summary.id) { await load() }
    .task(id: granularity) { await loadHistory() }
    .onChange(of: liveUpdates.metricsRefreshGeneration) { _, _ in
      Task { await refreshMetrics() }
    }
    .onReceive(liveUpdates.$latestEvent.compactMap { $0 }) { event in
      if event.affects(.server, id: summary.id) { Task { await load(showProgress: false) } }
    }
    .onChange(of: liveUpdates.refreshGeneration) { _, _ in
      Task { await load(showProgress: false) }
    }
  }

  private var overviewAddress: String? {
    nonEmpty(server?.config.address) ?? nonEmpty(summary.info.address)
  }

  private var overviewRegion: String? {
    nonEmpty(server?.config.region) ?? nonEmpty(summary.info.region)
  }

  private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else { return nil }
    return trimmed
  }

  @MainActor private func load(showProgress: Bool = true) async {
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      if showProgress {
        isLoadingDetails = true
        isLoadingMetrics = true
        isLoadingStacks = true
        isLoadingContainers = true
      }
      async let details: Void = loadDetails(using: client)
      async let metrics: Void = loadMetrics(using: client)
      async let relatedStacks: Void = loadStacks(using: client)
      async let relatedContainers: Void = loadContainers(using: client)
      async let historyResult: Void = loadHistory(using: client, showProgress: showProgress)
      _ = await (details, metrics, relatedStacks, relatedContainers, historyResult)
    } catch is CancellationError {} catch {
      errorMessage = error.localizedDescription
      isLoadingDetails = false
      isLoadingMetrics = false
      isLoadingStacks = false
      isLoadingContainers = false
      isLoadingHistory = false
      if stats == nil { metricsErrorMessage = error.localizedDescription }
      if stacks.isEmpty { stacksErrorMessage = error.localizedDescription }
      if containers.isEmpty { containersErrorMessage = error.localizedDescription }
      if history.isEmpty { historyErrorMessage = error.localizedDescription }
    }
  }

  @MainActor private func refreshMetrics() async {
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      async let current: Void = loadMetrics(using: client)
      async let historical: Void = loadHistory(using: client, showProgress: false)
      _ = await (current, historical)
    } catch is CancellationError {} catch {
      metricsErrorMessage = error.localizedDescription
      historyErrorMessage = error.localizedDescription
    }
  }

  @MainActor private func loadDetails(using client: KomodoAPIClient) async {
    defer { isLoadingDetails = false }
    do {
      async let loadedServer = client.getServer(idOrName: summary.id)
      async let loadedState = client.getServerState(idOrName: summary.id)
      server = try await loadedServer
      serverState = (try? await loadedState.status) ?? summary.info.state
      errorMessage = nil
    } catch is CancellationError {} catch {
      errorMessage = error.localizedDescription
      server = nil
      serverState = summary.info.state
    }
  }

  @MainActor private func loadMetrics(using client: KomodoAPIClient) async {
    defer { isLoadingMetrics = false }
    do {
      stats = try await client.getSystemStats(server: summary.id)
      metricsErrorMessage = nil
    } catch is CancellationError {
      return
    } catch {
      metricsErrorMessage = error.localizedDescription
    }
  }

  @MainActor private func loadStacks(using client: KomodoAPIClient) async {
    defer { isLoadingStacks = false }
    do {
      let allStacks = try await client.listStacks()
      stacks = allStacks.filter { $0.info.serverName == summary.name }
      stacksErrorMessage = nil
    } catch is CancellationError {
      return
    } catch {
      stacksErrorMessage = error.localizedDescription
    }
  }

  @MainActor private func loadContainers(using client: KomodoAPIClient) async {
    defer { isLoadingContainers = false }
    do {
      containers = try await client.listContainers(server: summary.id)
      containersErrorMessage = nil
    } catch is CancellationError {
      return
    } catch {
      containersErrorMessage = error.localizedDescription
    }
  }

  @MainActor private func loadHistory(
    using client: KomodoAPIClient,
    showProgress: Bool = true
  ) async {
    let requestedGranularity = granularity
    if showProgress { isLoadingHistory = true }
    defer {
      if requestedGranularity == granularity {
        isLoadingHistory = false
      }
    }
    do {
      let response = try await client.getHistoricalServerStats(
        server: summary.id,
        granularity: requestedGranularity
      )
      guard requestedGranularity == granularity else { return }
      history = response.stats
      historyErrorMessage = nil
    } catch is CancellationError {
      return
    } catch {
      guard requestedGranularity == granularity else { return }
      historyErrorMessage = error.localizedDescription
    }
  }

  @MainActor private func loadHistory() async {
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      await loadHistory(using: client)
    } catch is CancellationError {} catch {
      isLoadingHistory = false
      historyErrorMessage = error.localizedDescription
    }
  }

  private func measurementDate(_ timestamp: Int64) -> Date {
    MetricFreshness.measurementDate(for: timestamp)
  }

  private func statsAreStale(_ stats: SystemStats) -> Bool {
    let staleAfter = max(300, appSettings.metricsRefreshInterval.rawValue * 3)
    return MetricFreshness.isStale(
      timestamp: stats.refreshTimestamp,
      after: TimeInterval(staleAfter)
    )
  }

  private var historyContainsCPU: Bool {
    history.contains {
      $0.availableFields.contains("cpu_perc") && $0.availableFields.contains("ts")
    }
  }

  private var historyIsStale: Bool {
    guard let latestTimestamp = history
      .filter({ $0.availableFields.contains("cpu_perc") && $0.availableFields.contains("ts") })
      .map(\.timestamp)
      .max() else { return false }
    let expectedInterval: TimeInterval = switch granularity {
    case "1-hr": 3_600
    case "1-day": 86_400
    default: 900
    }
    return MetricFreshness.isStale(timestamp: latestTimestamp, after: max(300, expectedInterval * 2))
  }

  private var isLoading: Bool {
    isLoadingDetails || isLoadingMetrics || isLoadingStacks || isLoadingContainers
  }

  private var availableContainerActions: [ServerResourceAction] {
    let states = Set(containers.map { $0.state.lowercased() })
    let hasRunning = !states.isDisjoint(with: ["running", "healthy", "unhealthy", "restarting"])
    let hasPaused = states.contains("paused")
    let hasStopped = !states.isDisjoint(with: ["created", "exited", "stopped", "dead"])
    var actions: [ServerResourceAction] = []
    if hasRunning || hasPaused { actions.append(.restartAll) }
    if hasRunning { actions.append(.pauseAll) }
    if hasPaused { actions.append(.resumeAll) }
    if hasRunning || hasPaused { actions.append(.stopAll) }
    if hasStopped { actions.append(.startAll) }
    return actions
  }

  private var confirmsAction: Binding<Bool> {
    Binding(
      get: { pendingAction != nil },
      set: { if !$0 { pendingAction = nil } }
    )
  }

  private var showsActionError: Binding<Bool> {
    Binding(
      get: { actionError != nil },
      set: { if !$0 { actionError = nil } }
    )
  }

  private func confirmationMessage(for action: ServerResourceAction) -> String {
    let name = server?.name ?? summary.name
    return switch action {
    case .stopAll:
      String(format: String(localized: "confirm.stopAllContainers.message"), name, containers.count)
    case .pruneBuildx:
      String(format: String(localized: "confirm.pruneBuildx.message"), name)
    case .pruneSystem:
      String(format: String(localized: "confirm.pruneSystem.message"), name)
    case .deleteDefinition:
      String(format: String(localized: "confirm.deleteServer.message"), stacks.count, containers.count)
    default:
      String(format: String(localized: "confirm.serverContainerAction.message"), name, containers.count)
    }
  }

  @MainActor private func runAction(_ action: ServerResourceAction) async {
    pendingAction = nil
    guard activeAction == nil else { return }
    actionNotice = nil
    activeAction = action
    defer { activeAction = nil }
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      switch action {
      case .startAll: _ = try await client.startAllContainers(server: summary.id)
      case .restartAll: _ = try await client.restartAllContainers(server: summary.id)
      case .pauseAll: _ = try await client.pauseAllContainers(server: summary.id)
      case .resumeAll: _ = try await client.unpauseAllContainers(server: summary.id)
      case .stopAll: _ = try await client.stopAllContainers(server: summary.id)
      case .pruneBuildx: _ = try await client.pruneBuildx(server: summary.id)
      case .pruneSystem: _ = try await client.pruneSystem(server: summary.id)
      case .deleteDefinition:
        _ = try await client.deleteServer(idOrName: summary.id)
        liveUpdates.requestRefresh()
        dismiss()
        return
      }
      actionNotice = String(format: String(localized: "status.serverActionSubmitted"), action.title)
      liveUpdates.requestRefresh()
      await load(showProgress: false)
    } catch {
      actionError = error.localizedDescription
    }
  }

  private func localizedServerState(_ state: KomodoServerState) -> String {
    switch state {
    case .ok: String(localized: "serverState.ok")
    case .notOk: String(localized: "serverState.notOk")
    case .disabled: String(localized: "serverState.disabled")
    case .unknown: String(localized: "serverState.unavailable")
    }
  }
}

private struct ServerActionMenu: View {
  let containerActions: [ServerResourceAction]
  let canOperate: Bool
  let canMaintain: Bool
  let isEnabled: Bool
  let activeAction: ServerResourceAction?
  let edit: () -> Void
  let perform: (ServerResourceAction) -> Void

  var body: some View {
    Menu {
      Button("action.edit", systemImage: "pencil", action: edit)
        .accessibilityIdentifier("server-edit-button")

      if !containerActions.isEmpty {
        Section("section.operationActions") {
          ForEach(containerActions) { action in
            actionButton(action)
              .disabled(!canOperate)
          }
        }
      }

      Section("section.maintenanceActions") {
        actionButton(.pruneBuildx)
          .disabled(!canMaintain)
        actionButton(.pruneSystem)
          .disabled(!canMaintain)
      }

      Section("section.destructiveActions") {
        actionButton(.deleteDefinition)
      }
    } label: {
      if let activeAction {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel(activeAction.title)
      } else {
        Label("title.serverActions", systemImage: "ellipsis.circle")
      }
    }
    .disabled(!isEnabled || activeAction != nil)
    .accessibilityLabel(activeAction?.title ?? String(localized: "title.serverActions"))
    .accessibilityIdentifier("server-actions-menu")
  }

  private func actionButton(_ action: ServerResourceAction) -> some View {
    Button(role: action.isDestructive ? .destructive : nil) {
      perform(action)
    } label: {
      Label(action.title, systemImage: action.symbol)
    }
  }
}

struct CenteredLoadingRow: View {
  private let title: LocalizedStringKey

  init(_ title: LocalizedStringKey) {
    self.title = title
  }

  var body: some View {
    HStack(spacing: 10) {
      Spacer(minLength: 0)
      ProgressView()
        .controlSize(.small)
      Text(title)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
  }
}

struct MetricRow: View {
  let title: LocalizedStringKey
  let value: Double
  var total: Double? = nil
  let unit: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      LabeledContent(title) {
        if let total { Text("\(value, specifier: "%.1f") / \(total, specifier: "%.1f") \(unit)") }
        else { Text("\(value, specifier: "%.1f") \(unit)") }
      }
      if let total, total > 0 { ProgressView(value: value, total: total) }
    }
  }
}

private enum ContainerStateFilter: String, CaseIterable, Identifiable {
  case all
  case running
  case paused
  case stopped
  case attention
  case other

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .all: "filter.allStates"
    case .running: "state.running"
    case .paused: "state.paused"
    case .stopped: "state.stopped"
    case .attention: "filter.attention"
    case .other: "filter.otherStates"
    }
  }

  func includes(_ state: String) -> Bool {
    switch self {
    case .all: return true
    case .running: return ResourceStateCategory(state) == .running
    case .paused: return ResourceStateCategory(state) == .paused
    case .stopped: return ResourceStateCategory(state) == .stopped
    case .attention: return ResourceStateCategory(state) == .attention
    case .other:
      let category = ResourceStateCategory(state)
      return category == .other || category == .transitioning
    }
  }
}

private struct ContainerServerOption: Identifiable {
  let id: String
  let name: String
}

struct ContainerListView: View {
  @EnvironmentObject private var liveUpdates: KomodoLiveUpdateController
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings
  @State private var containers: [ContainerListItem] = []
  @State private var searchText = ""
  @State private var stateFilter: ContainerStateFilter = .all
  @State private var selectedServerID = ""
  @State private var publishedPortsOnly = false
  @State private var loadGeneration = 0
  @State private var errorMessage: String?
  @State private var isLoading = true

  private let pageSize = 100

  var body: some View {
    Group {
      if isLoading, containers.isEmpty { ProgressView("status.loadingContainers") }
      else if let errorMessage, containers.isEmpty {
        ContentUnavailableView {
          Label("title.containersUnavailable", systemImage: "exclamationmark.triangle")
        } description: {
          Text(errorMessage)
        } actions: {
          Button("action.retry") { Task { await load() } }
        }
      } else {
        List {
          Section {
            if filteredContainers.isEmpty {
              if containers.isEmpty {
                ContentUnavailableView(
                  "message.noContainers",
                  systemImage: "shippingbox",
                  description: Text("message.noContainers.description")
                )
              } else if hasActiveFilters {
                ContentUnavailableView {
                  Label("message.noContainersMatchFilters", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                  Button(emptyResetTitle) {
                    resetFilters()
                    searchText = ""
                  }
                }
              } else {
                ContentUnavailableView.search(text: searchText)
              }
            } else {
              ForEach(filteredContainers) { container in
                NavigationLink {
                  ContainerDetailView(
                    container: container,
                    profile: profile,
                    keychainStore: keychainStore,
                    appSettings: appSettings
                  )
                    .environmentObject(liveUpdates)
                } label: { ContainerRow(container: container) }
                  .accessibilityIdentifier("container-list-item-\(container.id ?? container.name)")
              }
            }
            if let errorMessage {
              Label(errorMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            }
          } header: {
            ResourceStatusSummary(
              counts: overviewCounts,
              isStale: errorMessage != nil,
              showTotal: { selectOverviewFilter(.all) },
              showActive: { selectOverviewFilter(.running) },
              showProblems: { selectOverviewFilter(.attention) }
            )
            .textCase(nil)
          }
        }
        .refreshable { await load() }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("title.containers")
    .searchable(text: $searchText, prompt: "action.searchContainers")
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Menu {
          Picker("filter.resourceState", selection: $stateFilter) {
            ForEach(ContainerStateFilter.allCases) { filter in
              Text(filter.title).tag(filter)
            }
          }
          if !availableServers.isEmpty {
            Picker("field.server", selection: $selectedServerID) {
              Text("filter.allServers").tag("")
              ForEach(availableServers) { server in
                Text(server.name).tag(server.id)
              }
            }
          }
          Toggle("filter.publishedPorts", isOn: $publishedPortsOnly)
          if hasActiveFilters {
            Button("filter.reset") { resetFilters() }
          }
        } label: {
          Label(
            "filter.containers",
            systemImage: hasActiveFilters
              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
          )
        }
        LiveConnectionStatusButton(
          profile: profile,
          keychainStore: keychainStore,
          appSettings: appSettings
        )
        #if os(macOS)
        Button("action.refresh", systemImage: "arrow.clockwise") { Task { await load() } }
          .disabled(isLoading)
          .keyboardShortcut("r", modifiers: .command)
        #endif
      }
    }
    .task(id: profile.id) {
      containers = []
      resetFilters()
      await load()
    }
    .onReceive(liveUpdates.$latestEvent.compactMap { $0 }) { event in
      if event.affects(.stack) || event.affects(.server) || event.affects(.deployment) {
        Task { await load() }
      }
    }
    .onChange(of: liveUpdates.refreshGeneration) { _, _ in
      Task { await load() }
    }
  }

  private var filteredContainers: [ContainerListItem] {
    containers.filter { container in
      stateFilter.includes(container.state)
        && (selectedServerID.isEmpty || serverKey(for: container) == selectedServerID)
        && (!publishedPortsOnly || container.ports.contains { $0.publicPort != nil })
        && (searchText.isEmpty
          || container.name.localizedCaseInsensitiveContains(searchText)
          || (container.image?.localizedCaseInsensitiveContains(searchText) == true)
          || (container.serverName?.localizedCaseInsensitiveContains(searchText) == true))
    }
  }

  private var overviewCounts: ResourceOverviewCounts {
    ResourceOverviewCounts(states: containers.map(\.state))
  }

  private func selectOverviewFilter(_ filter: ContainerStateFilter) {
    searchText = ""
    resetFilters()
    stateFilter = filter
  }

  private var availableServers: [ContainerServerOption] {
    var namesByID: [String: String] = [:]
    for container in containers {
      let id = serverKey(for: container)
      if !id.isEmpty {
        namesByID[id] = container.serverName.flatMap { $0.isEmpty ? nil : $0 } ?? id
      }
    }
    if !selectedServerID.isEmpty, namesByID[selectedServerID] == nil {
      namesByID[selectedServerID] = selectedServerID
    }
    return namesByID.map { ContainerServerOption(id: $0.key, name: $0.value) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private var hasActiveFilters: Bool {
    stateFilter != .all || !selectedServerID.isEmpty || publishedPortsOnly
  }

  private var emptyResetTitle: LocalizedStringKey {
    searchText.isEmpty ? "filter.reset" : "filter.resetAll"
  }

  private func serverKey(for container: ContainerListItem) -> String {
    if let serverID = container.serverID, !serverID.isEmpty { return serverID }
    return container.serverName ?? ""
  }

  private func resetFilters() {
    stateFilter = .all
    selectedServerID = ""
    publishedPortsOnly = false
  }

  @MainActor private func load() async {
    loadGeneration += 1
    let generation = loadGeneration
    isLoading = true
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      var loadedContainers: [ContainerListItem] = []
      var page = 0
      while true {
        guard generation == loadGeneration else { return }
        let batch = try await client.listAllContainers(page: page, limit: pageSize)
        try Task.checkCancellation()
        guard generation == loadGeneration else { return }
        loadedContainers.append(contentsOf: batch)
        if batch.count < pageSize { break }
        page += 1
      }
      guard generation == loadGeneration else { return }
      containers = loadedContainers
      errorMessage = nil
    } catch is CancellationError {
      return
    } catch {
      guard generation == loadGeneration else { return }
      errorMessage = error.localizedDescription
    }
    if generation == loadGeneration { isLoading = false }
  }
}

struct ContainerRow: View {
  let container: ContainerListItem
  var body: some View {
    ResourceListRow(
      title: container.name,
      subtitle: [container.image ?? "", container.serverName ?? ""]
        .filter { !$0.isEmpty }
        .joined(separator: " · "),
      status: localizedResourceState(container.state),
      symbol: resourceStateSymbol(container.state),
      symbolColor: resourceStateColor(container.state)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(container.name))
    .accessibilityValue(Text(localizedResourceState(container.state)))
  }
}

private enum ContainerResourceAction: String, Identifiable {
  case start
  case restart
  case pause
  case resume
  case stop
  case destroy

  var id: String { rawValue }

  var title: String {
    switch self {
    case .start: String(localized: "action.start")
    case .restart: String(localized: "action.restart")
    case .pause: String(localized: "action.pause")
    case .resume: String(localized: "action.resume")
    case .stop: String(localized: "action.stop")
    case .destroy: String(localized: "action.removeContainer")
    }
  }

  var symbol: String {
    switch self {
    case .start, .resume: "play.fill"
    case .restart: "arrow.clockwise"
    case .pause: "pause.fill"
    case .stop: "stop.fill"
    case .destroy: "trash"
    }
  }

  var isDestructive: Bool { self == .stop || self == .destroy }
  var isRemoval: Bool { self == .destroy }
}

struct ContainerDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var liveUpdates: KomodoLiveUpdateController
  let container: ContainerListItem
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings
  var ownerStack: StackDetail? = nil
  @State private var showingStackEditor = false
  @State private var updatedContainer: ContainerListItem?
  @State private var activeAction: ContainerResourceAction?
  @State private var pendingAction: ContainerResourceAction?
  @State private var actionError: String?
  @State private var showsAllPorts = false

  var body: some View {
    List {
      Section("section.overview") {
        LabeledContent("field.status", value: displayedContainer.status ?? displayedContainer.state)
        if let image = displayedContainer.image { LabeledContent("field.image", value: image) }
        if let server = displayedContainer.serverName { LabeledContent("field.server", value: server) }
        if let mode = displayedContainer.networkMode { LabeledContent("field.networkMode", value: mode) }
      }
      if let stats = displayedContainer.stats {
        Section("section.currentMetrics") {
          if stats.availableFields.contains("cpu_perc") {
            LabeledContent("field.cpu") {
              Text(String(
                format: String(localized: "metrics.cpuWithCores"),
                stats.cpuPercent,
                stats.cpuCoreEquivalent
              ))
            }
          } else {
            LabeledContent("field.cpu", value: String(localized: "metrics.unavailable"))
          }
          LabeledContent(
            "field.memory",
            value: stats.availableFields.contains("mem_usage")
              ? stats.memoryUsage : String(localized: "metrics.unavailable")
          )
          if stats.availableFields.contains("mem_perc") {
            LabeledContent(
              "field.memoryPercent",
              value: String(format: "%.1f %%", stats.memoryPercent)
            )
          } else {
            LabeledContent("field.memoryPercent", value: String(localized: "metrics.unavailable"))
          }
          LabeledContent(
            "field.networkIO",
            value: stats.availableFields.contains("net_io")
              ? stats.networkIO : String(localized: "metrics.unavailable")
          )
          LabeledContent(
            "field.blockIO",
            value: stats.availableFields.contains("block_io")
              ? stats.blockIO : String(localized: "metrics.unavailable")
          )
          LabeledContent(
            "field.processes",
            value: stats.availableFields.contains("pids")
              ? String(stats.processCount) : String(localized: "metrics.unavailable")
          )
        }
      }
      if !displayedContainer.ports.isEmpty {
        Section("section.ports") {
          ForEach(
            Array(displayedContainer.ports.prefix(showsAllPorts ? displayedContainer.ports.count : 3).enumerated()),
            id: \.offset
          ) { _, port in
            LabeledContent("\(port.type.uppercased()) \(port.privatePort)", value: port.publicPort.map(String.init) ?? "—")
          }
          if displayedContainer.ports.count > 3 {
            Button {
              withAnimation { showsAllPorts.toggle() }
            } label: {
              Label(
                showsAllPorts ? "action.showFewerPorts" : "action.showMorePorts",
                systemImage: showsAllPorts ? "chevron.up" : "chevron.down"
              )
            }
            .accessibilityIdentifier("container-ports-toggle")
          }
        }
      }
      if !displayedContainer.networks.isEmpty { Section("section.networks") { ForEach(displayedContainer.networks, id: \.self, content: Text.init) } }
      if !displayedContainer.volumes.isEmpty { Section("section.volumes") { ForEach(displayedContainer.volumes, id: \.self, content: Text.init) } }
      Section("section.observability") {
        if let logSource {
          NavigationLink {
            LogViewerView(
              profile: profile,
              keychainStore: keychainStore,
              source: logSource,
              appSettings: appSettings
            )
            .environmentObject(liveUpdates)
          } label: {
            Label("action.openContainerLogs", systemImage: "doc.text.magnifyingglass")
          }
          .accessibilityIdentifier("container-logs-link")
        } else {
          Label("message.logsUnavailable", systemImage: "doc.text.magnifyingglass")
            .foregroundStyle(.secondary)
        }
      }
    }
    .refreshable { await loadMetrics() }
    .navigationTitle(displayedContainer.name)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        ContainerActionMenu(
          state: displayedContainer.state,
          isEnabled: displayedContainer.serverID != nil,
          activeAction: activeAction,
          canEdit: ownerStack != nil,
          edit: { showingStackEditor = true },
          perform: handleAction
        )
        LiveConnectionStatusButton(
          profile: profile,
          keychainStore: keychainStore,
          appSettings: appSettings
        )
        #if os(macOS)
        Button("action.refresh", systemImage: "arrow.clockwise") {
          Task { await loadMetrics() }
        }
        .disabled(activeAction != nil)
        .keyboardShortcut("r", modifiers: .command)
        #endif
      }
    }
    .confirmationDialog(
      pendingAction?.title ?? String(localized: "title.containerActions"),
      isPresented: confirmsAction,
      titleVisibility: .visible,
      presenting: pendingAction
    ) { action in
      Button(action.title, role: action.isDestructive ? .destructive : nil) {
        Task { await runAction(action) }
      }
      Button("action.cancel", role: .cancel) {}
    } message: { action in
      Text(confirmationMessage(for: action))
    }
    .alert("alert.actionFailed", isPresented: showsActionError) {
      Button("action.ok") { actionError = nil }
    } message: {
      Text(actionError ?? String(localized: "error.unknown"))
    }
    .sheet(isPresented: $showingStackEditor) {
      if let ownerStack {
        NavigationStack {
          StackEditorView(profile: profile, keychainStore: keychainStore, stack: ownerStack) {
            showingStackEditor = false
          }
        }
      }
    }
    .task(id: container.id) { await loadMetrics() }
    .onChange(of: liveUpdates.metricsRefreshGeneration) { _, _ in
      Task { await loadMetrics() }
    }
    .onReceive(liveUpdates.$latestEvent.compactMap { $0 }) { event in
      if event.affects(.stack) || event.affects(.server) || event.affects(.deployment) {
        Task { await loadMetrics() }
      }
    }
    .onChange(of: liveUpdates.refreshGeneration) { _, _ in
      Task { await loadMetrics() }
    }
  }

  private var displayedContainer: ContainerListItem {
    updatedContainer ?? container
  }

  private var logSource: LogSource? {
    guard let serverID = displayedContainer.serverID else { return nil }
    return .container(serverID: serverID, name: displayedContainer.name)
  }

  private var confirmsAction: Binding<Bool> {
    Binding(
      get: { pendingAction != nil },
      set: { if !$0 { pendingAction = nil } }
    )
  }

  private var showsActionError: Binding<Bool> {
    Binding(
      get: { actionError != nil },
      set: { if !$0 { actionError = nil } }
    )
  }

  private func handleAction(_ action: ContainerResourceAction) {
    switch action {
    case .stop, .destroy:
      pendingAction = action
    default:
      Task { await runAction(action) }
    }
  }

  private func confirmationMessage(for action: ContainerResourceAction) -> String {
    let name = displayedContainer.name
    return switch action {
    case .destroy where ownerStack != nil:
      String(format: String(localized: "confirm.removeOwnedContainer.message"), name)
    case .destroy:
      String(format: String(localized: "confirm.removeContainer.message"), name)
    case .stop:
      String(format: String(localized: "confirm.stopContainer.message"), name)
    default:
      String(format: String(localized: "confirm.containerAction.message"), name)
    }
  }

  @MainActor
  private func runAction(_ action: ContainerResourceAction) async {
    pendingAction = nil
    guard let serverID = displayedContainer.serverID else {
      actionError = String(localized: "error.container.serverMissing")
      return
    }
    activeAction = action
    defer { activeAction = nil }
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      switch action {
      case .start:
        _ = try await client.startContainer(server: serverID, container: displayedContainer.name)
      case .restart:
        _ = try await client.restartContainer(server: serverID, container: displayedContainer.name)
      case .pause:
        _ = try await client.pauseContainer(server: serverID, container: displayedContainer.name)
      case .resume:
        _ = try await client.unpauseContainer(server: serverID, container: displayedContainer.name)
      case .stop:
        _ = try await client.stopContainer(server: serverID, container: displayedContainer.name)
      case .destroy:
        _ = try await client.destroyContainer(server: serverID, container: displayedContainer.name)
        liveUpdates.requestRefresh()
        dismiss()
        return
      }
      await loadMetrics()
    } catch {
      actionError = error.localizedDescription
    }
  }

  @MainActor private func loadMetrics() async {
    do {
      let containers = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
        .listAllContainers()
      updatedContainer = containers.first {
        $0.id == container.id
          || ($0.name == container.name && $0.serverID == container.serverID)
      }
    } catch is CancellationError {} catch {
      // Keep the most recent metrics while transient polling fails.
    }
  }
}

private struct ContainerActionMenu: View {
  let state: String
  let isEnabled: Bool
  let activeAction: ContainerResourceAction?
  let canEdit: Bool
  let edit: () -> Void
  let perform: (ContainerResourceAction) -> Void

  var body: some View {
    Menu {
      if canEdit {
        Button("action.editContainerConfiguration", systemImage: "pencil", action: edit)
      }

      Section("section.operationActions") {
        ForEach(actions.filter { !$0.isRemoval }) { action in
          actionButton(action)
        }
      }

      if actions.contains(where: \.isRemoval) {
        Section("section.destructiveActions") {
          ForEach(actions.filter(\.isRemoval)) { action in
            actionButton(action)
          }
        }
      }
    } label: {
      if let activeAction {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel(activeAction.title)
      } else {
        Label("title.containerActions", systemImage: "ellipsis.circle")
      }
    }
    .disabled(!isEnabled || activeAction != nil)
    .accessibilityLabel(activeAction?.title ?? String(localized: "title.containerActions"))
    .accessibilityIdentifier("container-actions-menu")
  }

  private func actionButton(_ action: ContainerResourceAction) -> some View {
    Button(role: action.isDestructive ? .destructive : nil) {
      perform(action)
    } label: {
      Label(action.title, systemImage: action.symbol)
    }
  }

  private var actions: [ContainerResourceAction] {
    switch state.lowercased() {
    case "running": [.restart, .pause, .stop, .destroy]
    case "paused": [.resume, .stop, .restart, .destroy]
    case "created", "exited", "stopped", "dead": [.start, .destroy]
    default: [.start, .restart, .destroy]
    }
  }
}

@MainActor
final class EditorSaveGate: ObservableObject {
  @Published private(set) var isSaving = false

  func perform(_ operation: () async throws -> Void) async throws {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    try await operation()
  }
}

struct ServerEditorView: View {
  let profile: ServerProfile
  let keychainStore: KeychainStore
  let server: ServerDetail?
  let summary: ServerListItem?
  let onSaved: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var address: String
  @State private var externalAddress: String
  @State private var region: String
  @State private var enabled: Bool
  @State private var insecureTLS: Bool
  @State private var autoPrune: Bool
  @State private var monitoringDraft: ServerMonitoringDraft
  @State private var alertDraft: ServerAlertDraft
  @State private var showingReview = false
  @StateObject private var saveGate = EditorSaveGate()
  @State private var errorMessage: String?

  init(profile: ServerProfile, keychainStore: KeychainStore, server: ServerDetail? = nil, summary: ServerListItem? = nil, onSaved: @escaping () -> Void) {
    self.profile = profile; self.keychainStore = keychainStore; self.server = server; self.summary = summary; self.onSaved = onSaved
    _name = State(initialValue: server?.name ?? "")
    _address = State(initialValue: Self.originalAddress(server: server, summary: summary))
    _externalAddress = State(initialValue: Self.originalExternalAddress(server: server, summary: summary))
    _region = State(initialValue: Self.originalRegion(server: server, summary: summary))
    _enabled = State(initialValue: server?.config.enabled ?? true)
    _insecureTLS = State(initialValue: server?.config.insecureTLS ?? false)
    _autoPrune = State(initialValue: server?.config.autoPrune ?? false)
    _monitoringDraft = State(initialValue: ServerMonitoringDraft(original: server?.config.displayConfiguration))
    _alertDraft = State(initialValue: ServerAlertDraft(original: server?.config.displayConfiguration))
  }

  var body: some View {
    Form {
      Section {
        ConfigurationTextField("field.name", text: $name).disabled(server != nil)
        ConfigurationTextField("field.address", text: $address, explanation: "configuration.help.address", identifier: "server-editor-address-field")
        ConfigurationTextField("field.externalAddress", text: $externalAddress, explanation: "configuration.help.externalAddress", identifier: "server-editor-external-address-field")
        ConfigurationTextField("field.region", text: $region, identifier: "server-editor-region-field")
      } header: {
        Text("section.identity")
      } footer: {
        if server != nil, externalAddress.isEmpty, summary?.info.publicIP != nil {
          Text("message.serverPublicIPIsNotExternalAddress")
        }
      }
      Section("section.behavior") {
        Toggle("field.enabled", isOn: $enabled)
        ConfigurationToggle(title: "field.autoPrune", isOn: $autoPrune, explanation: "configuration.help.autoPrune")
        ConfigurationToggle(title: "field.insecureTLS", isOn: $insecureTLS, explanation: "configuration.help.insecureTLS")
      }
      monitoringSection
      ServerAlertEditorSection(draft: $alertDraft)
      if !hasEditableConfiguration { Text("message.serverConfigurationIncomplete").foregroundStyle(.secondary) }
      if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
    }
    .disabled(saveGate.isSaving)
    .accessibilityIdentifier("server-editor-form")
    .navigationTitle(server == nil ? "title.newServer" : "title.editServer")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() }.disabled(saveGate.isSaving) }
      ToolbarItem(placement: .confirmationAction) { Button("action.reviewChanges") { showingReview = true }.disabled(!canSave || saveGate.isSaving) }
    }
    .confirmationDialog("confirm.saveChanges.title", isPresented: $showingReview, titleVisibility: .visible) {
      Button("action.save") { Task { await save() } }
      Button("action.cancel", role: .cancel) {}
    } message: { Text(String(format: String(localized: "confirm.saveChanges.fields"), changedFields.joined(separator: ", "))) }
    .overlay { if saveGate.isSaving { ProgressView("status.saving").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
  }

  private var monitoringSection: some View {
    Section("configuration.group.monitoring") {
      if let value = monitoringDraft.statsMonitoring {
        ConfigurationToggle(title: "field.statsMonitoring", isOn: Binding(
          get: { monitoringDraft.statsMonitoring ?? value },
          set: { monitoringDraft.statsMonitoring = $0 }
        ), explanation: "configuration.help.statsMonitoring", identifier: "server-editor-stats-monitoring")
      } else {
        LabeledContent("field.statsMonitoring") { Text("configuration.value.unavailable") }
      }
      if let value = monitoringDraft.ignoreMountsText {
        ConfigurationEditorField("configuration.field.ignoreMounts", explanation: "server.monitoring.mounts.help") {
          TextEditor(text: Binding(
            get: { monitoringDraft.ignoreMountsText ?? value },
            set: { monitoringDraft.ignoreMountsText = $0 }
          ))
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 80, maxHeight: 160)
          .autocorrectionDisabled()
          #if os(iOS)
          .textInputAutocapitalization(.never)
          #endif
          .accessibilityLabel("configuration.field.ignoreMounts")
          .accessibilityIdentifier("server-editor-ignore-mounts")
        }
      } else {
        LabeledContent("configuration.field.ignoreMounts") { Text("configuration.value.unavailable") }
      }
      if let message = monitoringDraft.validationMessageKey {
        Text(LocalizedStringKey(message)).foregroundStyle(.red)
      }
    }
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty
      && isValidConnectionAddress
      && hasEditableConfiguration
      && monitoringDraft.validationMessageKey == nil
      && alertDraft.validationMessageKey == nil
      && !changedFields.isEmpty
  }

  private var isValidConnectionAddress: Bool {
    let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if server != nil && value.isEmpty { return true }
    let secureURL = value.hasPrefix("wss://")
      ? "https://" + String(value.dropFirst(6)) : value
    let normalizedURL = secureURL.hasPrefix("ws://")
      ? "http://" + String(secureURL.dropFirst(5)) : secureURL
    return (try? ServerAddress(normalizedURL)) != nil
  }

  private var hasEditableConfiguration: Bool {
    guard let server else { return true }
    let fields = server.config.availableFields
    let behaviorFields: Set<String> = ["enabled", "insecure_tls", "auto_prune"]
    return behaviorFields.isSubset(of: fields)
      && (fields.contains("external_address") || summary?.info.externalAddress != nil)
  }

  private static func originalAddress(server: ServerDetail?, summary: ServerListItem?) -> String {
    guard let server else { return "https://" }
    return server.config.availableFields.contains("address")
      ? server.config.address : summary?.info.address ?? ""
  }

  private static func originalExternalAddress(server: ServerDetail?, summary: ServerListItem?) -> String {
    guard let server else { return "" }
    return server.config.availableFields.contains("external_address")
      ? server.config.externalAddress : summary?.info.externalAddress ?? ""
  }

  private static func originalRegion(server: ServerDetail?, summary: ServerListItem?) -> String {
    guard let server else { return "" }
    return server.config.availableFields.contains("region")
      ? server.config.region : summary?.info.region ?? ""
  }

  private var changedFields: [String] {
    guard let old = server?.config else {
      return ["field.name", "field.address", "field.externalAddress", "field.region", "section.behavior"].map { String(localized: String.LocalizationValue($0)) } + monitoringDraft.changedFields + alertDraft.changedFields
    }
    return [
      Self.originalAddress(server: server, summary: summary) == address ? nil : String(localized: "field.address"),
      Self.originalExternalAddress(server: server, summary: summary) == externalAddress ? nil : String(localized: "field.externalAddress"),
      Self.originalRegion(server: server, summary: summary) == region ? nil : String(localized: "field.region"),
      old.enabled == enabled ? nil : String(localized: "field.enabled"),
      old.insecureTLS == insecureTLS ? nil : String(localized: "field.insecureTLS"),
      old.autoPrune == autoPrune ? nil : String(localized: "field.autoPrune")
    ].compactMap { $0 } + monitoringDraft.changedFields + alertDraft.changedFields
  }

  private var patch: ServerConfigPatch {
    let old = server?.config
    var patch = ServerConfigPatch(
      address: Self.originalAddress(server: server, summary: summary) == address ? nil : address,
      externalAddress: Self.originalExternalAddress(server: server, summary: summary) == externalAddress ? nil : externalAddress,
      region: Self.originalRegion(server: server, summary: summary) == region ? nil : region,
      enabled: old?.enabled == enabled ? nil : enabled,
      insecureTLS: old?.insecureTLS == insecureTLS ? nil : insecureTLS,
      autoPrune: old?.autoPrune == autoPrune ? nil : autoPrune
    )
    monitoringDraft.apply(to: &patch)
    alertDraft.apply(to: &patch)
    return patch
  }

  @MainActor private func save() async {
    guard canSave else { return }
    do {
      try await saveGate.perform {
        let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
        let saved = if let server { try await client.updateServer(id: server.id, config: patch) }
          else { try await client.createServer(name: name, config: patch) }
        _ = try await client.getServer(idOrName: saved.id)
        onSaved()
      }
    } catch { errorMessage = error.localizedDescription }
  }
}

struct StackEditorView: View {
  let profile: ServerProfile
  let keychainStore: KeychainStore
  let stack: StackDetail?
  let onSaved: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var serverID: String
  @State private var projectName: String
  @State private var composeDraft = StackComposeDraft()
  @State private var isLoadingCompose = false
  @State private var composeLoadError: String?
  @State private var autoPull: Bool
  @State private var pollForUpdates: Bool
  @State private var autoUpdate: Bool
  @State private var servers: [ServerListItem] = []
  @State private var isLoadingServers = true
  @State private var serverLoadError: String?
  @State private var showingReview = false
  @StateObject private var saveGate = EditorSaveGate()
  @State private var errorMessage: String?

  init(profile: ServerProfile, keychainStore: KeychainStore, stack: StackDetail? = nil, onSaved: @escaping () -> Void) {
    self.profile = profile; self.keychainStore = keychainStore; self.stack = stack; self.onSaved = onSaved
    _name = State(initialValue: stack?.name ?? ""); _serverID = State(initialValue: stack?.config.serverID ?? "")
    _projectName = State(initialValue: stack?.config.projectName ?? "")
    _isLoadingCompose = State(initialValue: stack != nil)
    _autoPull = State(initialValue: stack?.config.autoPull ?? false)
    _pollForUpdates = State(initialValue: stack?.config.pollForUpdates ?? false); _autoUpdate = State(initialValue: stack?.config.autoUpdate ?? false)
  }

  var body: some View {
    Form {
      Section("section.identity") {
        ConfigurationTextField("field.name", text: $name).disabled(stack != nil)
        serverPicker
        ConfigurationTextField("field.project", text: $projectName, explanation: "configuration.help.projectName")
      }
      if isLoadingCompose {
        Section("configuration.group.files") { ProgressView("stack.compose.loading") }
      } else if let composeLoadError {
        Section("configuration.group.files") {
          Text(composeLoadError).foregroundStyle(.red)
          Button("action.retry") { Task { await loadComposeConfiguration() } }
        }
      } else {
        if composeDraft.source == .git || composeDraft.source == .linkedRepo || composeDraft.source == .unknown {
          Section("section.repository") {
            if composeDraft.source != .linkedRepo {
              ConfigurationTextField("field.repository", text: $composeDraft.repository, explanation: "configuration.help.repository")
            }
            ConfigurationTextField("field.branch", text: $composeDraft.branch,
              explanation: "configuration.help.branch", identifier: "stack-editor-branch-field")
            if composeDraft.source == .git {
              ConfigurationTextField("configuration.field.gitProvider", text: $composeDraft.gitProvider,
                explanation: "configuration.help.gitProvider", identifier: "stack-editor-gitProvider")
              ConfigurationTextField("configuration.field.gitAccount", text: $composeDraft.gitAccount,
                explanation: "configuration.help.gitAccount", identifier: "stack-editor-gitAccount")
            }
          }
        }
        StackComposeEditorSection(draft: $composeDraft)
      }
      Section("section.behavior") {
        ConfigurationToggle(title: "field.autoPull", isOn: $autoPull, explanation: "configuration.help.autoPull")
        ConfigurationToggle(title: "field.pollForUpdates", isOn: $pollForUpdates, explanation: "configuration.help.pollForUpdates")
        ConfigurationToggle(title: "field.autoUpdate", isOn: $autoUpdate, explanation: "configuration.help.autoUpdate")
      }
      if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
    }
    .disabled(saveGate.isSaving)
    .task(id: profile.id) {
      async let servers: Void = loadServers()
      async let compose: Void = loadComposeConfiguration()
      _ = await (servers, compose)
    }
    .onDisappear { composeDraft = StackComposeDraft() }
    .navigationTitle(stack == nil ? "title.newStack" : "title.editStack")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() }.disabled(saveGate.isSaving) }
      ToolbarItem(placement: .confirmationAction) { Button("action.reviewChanges") { showingReview = true }.disabled(!canSave || saveGate.isSaving) }
    }
    .confirmationDialog("confirm.saveChanges.title", isPresented: $showingReview, titleVisibility: .visible) {
      Button("action.save") { Task { await save() } }; Button("action.cancel", role: .cancel) {}
    } message: { Text(reviewMessage) }
    .overlay { if saveGate.isSaving { ProgressView("status.saving").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
  }

  private var serverPicker: some View {
    Group {
      ConfigurationEditorField("field.server", explanation: "configuration.help.serverID") {
        Picker("field.server", selection: $serverID) {
          Text("stack.server.select").tag("")
          if !serverID.isEmpty && !servers.contains(where: { selectionValue(for: $0) == serverID }) {
            Text(String(format: String(localized: "stack.server.unavailable"), serverID))
              .tag(serverID)
          }
          ForEach(servers) { server in
            Text(server.name).tag(selectionValue(for: server))
          }
        }
        .accessibilityIdentifier("stack-editor-server-picker")
        .labelsHidden()
        .accessibilityLabel("field.server")
        .disabled(isLoadingServers || saveGate.isSaving || servers.isEmpty)
      }
      if isLoadingServers {
        ProgressView("stack.server.loading")
      } else if let serverLoadError {
        Text(serverLoadError).foregroundStyle(.red)
        Button("action.retry") { Task { await loadServers() } }
          .disabled(saveGate.isSaving)
      } else if servers.isEmpty {
        Text("stack.server.empty").foregroundStyle(.secondary)
      }
    }
  }

  private func selectionValue(for server: ServerListItem) -> String {
    // Preserve an existing name-based reference until the user changes the target.
    if let original = stack?.config.serverID, original == server.id || original == server.name {
      return original
    }
    return server.id
  }

  @MainActor private func loadServers() async {
    guard !saveGate.isSaving else { return }
    isLoadingServers = true
    serverLoadError = nil
    defer { isLoadingServers = false }
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      let loaded = try await client.listAllServers()
      try Task.checkCancellation()
      servers = loaded.filter { !$0.template }.sorted {
        let order = $0.name.localizedStandardCompare($1.name)
        return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
      }
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      serverLoadError = error.localizedDescription
    }
  }

  @MainActor private func loadComposeConfiguration() async {
    guard let stack else { return }
    isLoadingCompose = true
    composeLoadError = nil
    defer { isLoadingCompose = false }
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      let configuration = try await client.getStackComposeConfiguration(idOrName: stack.id)
      try Task.checkCancellation()
      composeDraft = StackComposeDraft(original: configuration)
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      composeLoadError = error.localizedDescription
    }
  }

  private var canSave: Bool {
    !isLoadingCompose && composeLoadError == nil && composeDraft.validationMessageKey == nil
      && !name.trimmingCharacters(in: .whitespaces).isEmpty
      && !serverID.trimmingCharacters(in: .whitespaces).isEmpty
      && !changedFields.isEmpty
  }

  private var changedFields: [String] {
    guard let old = stack?.config else {
      return ["field.name", "field.server", "field.project"].map { String(localized: String.LocalizationValue($0)) }
        + composeDraft.changedFields
    }
    return [
      old.serverID == serverID ? nil : String(localized: "field.server"),
      old.projectName == projectName ? nil : String(localized: "field.project"),
      old.autoPull == autoPull ? nil : String(localized: "field.autoPull"),
      old.pollForUpdates == pollForUpdates ? nil : String(localized: "field.pollForUpdates"),
      old.autoUpdate == autoUpdate ? nil : String(localized: "field.autoUpdate")
    ].compactMap { $0 } + composeDraft.changedFields
  }

  private var reviewMessage: String {
    let fields = String(format: String(localized: "confirm.saveChanges.fields"), changedFields.joined(separator: ", "))
    guard composeDraft.sourceChanged, let original = composeDraft.original else { return fields }
    let sourceMessage = String(format: String(localized: "stack.compose.review.source"),
      String(localized: String.LocalizationValue(original.source.localizationKey)),
      String(localized: String.LocalizationValue(composeDraft.source.localizationKey)))
    guard composeDraft.clearsInlineContents else { return fields + "\n\n" + sourceMessage }
    return fields + "\n\n" + sourceMessage + "\n\n"
      + String(localized: "stack.compose.review.clearsInlineContents")
  }

  private var patch: StackConfigPatch {
    let old = stack?.config
    var patch = composeDraft.patch
    patch.serverID = old?.serverID == serverID ? nil : serverID
    patch.projectName = old?.projectName == projectName ? nil : projectName
    patch.autoPull = old?.autoPull == autoPull ? nil : autoPull
    patch.pollForUpdates = old?.pollForUpdates == pollForUpdates ? nil : pollForUpdates
    patch.autoUpdate = old?.autoUpdate == autoUpdate ? nil : autoUpdate
    return patch
  }

  @MainActor private func save() async {
    guard canSave else { return }
    do {
      try await saveGate.perform {
        let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
        let saved = if let stack { try await client.updateStack(id: stack.id, config: patch) }
          else { try await client.createStack(name: name, config: patch) }
        _ = try await client.getStack(idOrName: saved.id)
        onSaved()
      }
    } catch { errorMessage = error.localizedDescription }
  }
}

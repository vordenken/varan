import SwiftUI

private enum StackResourceAction: String, Identifiable {
  case deploy
  case pull
  case start
  case restart
  case pause
  case resume
  case stop
  case destroy
  case deleteDefinition

  var id: String { rawValue }

  var title: String {
    switch self {
    case .deploy: String(localized: "action.deploy")
    case .pull: String(localized: "action.pullImages")
    case .start: String(localized: "action.start")
    case .restart: String(localized: "action.restart")
    case .pause: String(localized: "action.pause")
    case .resume: String(localized: "action.resume")
    case .stop: String(localized: "action.stop")
    case .destroy: String(localized: "action.destroy")
    case .deleteDefinition: String(localized: "action.deleteStack")
    }
  }

  var symbol: String {
    switch self {
    case .deploy: "paperplane.fill"
    case .pull: "arrow.down.circle"
    case .start: "play.fill"
    case .restart: "arrow.clockwise"
    case .pause: "pause.fill"
    case .resume: "play.fill"
    case .stop: "stop.fill"
    case .destroy, .deleteDefinition: "trash"
    }
  }

  var isDestructive: Bool {
    self == .stop || self == .destroy || self == .deleteDefinition
  }

  var isRemoval: Bool { self == .destroy || self == .deleteDefinition }
}

struct StackDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var liveUpdates: KomodoLiveUpdateController
  private enum LoadState: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  private enum StopTarget: Identifiable {
    case stack
    case service(StackService)

    var id: String {
      switch self {
      case .stack: "stack"
      case .service(let service): service.id
      }
    }
  }

  let summary: StackListItem
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings

  @State private var detail: StackDetail?
  @State private var services: [StackService] = []
  @State private var loadState = LoadState.loading
  @State private var activeActionID: String?
  @State private var stopTarget: StopTarget?
  @State private var actionError: String?
  @State private var showingEditor = false
  @State private var pendingAction: StackResourceAction?
  @State private var logDestination: LogSource?

  var body: some View {
    Group {
      switch loadState {
      case .loading where detail == nil:
        ProgressView("status.loadingStack")
      case .failed(let message) where detail == nil:
        ContentUnavailableView {
          Label("title.stackUnavailable", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("action.retry") {
            Task { await loadContent() }
          }
        }
      default:
        content
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle(detail?.name ?? summary.name)
    .toolbar {
      ToolbarItemGroup {
        LiveConnectionStatusButton(
          profile: profile,
          keychainStore: keychainStore,
          appSettings: appSettings
        )
        Button("action.refresh", systemImage: "arrow.clockwise") {
          Task { await loadContent() }
        }
        .disabled(isBusy)
        StackActionMenu(
          state: effectiveState,
          updateAvailable: updateAvailable,
          isEnabled: detail != nil,
          activeAction: activeStackAction,
          edit: { showingEditor = true },
          perform: handleStackAction
        )
      }
    }
    .refreshable {
      await loadContent()
    }
    .task(id: summary.id) {
      await loadContent()
    }
    .task(id: "\(appSettings.metricsAutoRefresh)-\(appSettings.metricsRefreshInterval.rawValue)-\(scenePhase)") {
      while appSettings.metricsAutoRefresh, scenePhase == .active, !Task.isCancelled {
        try? await Task.sleep(for: .seconds(appSettings.metricsRefreshInterval.rawValue))
        guard !Task.isCancelled else { return }
        await loadContent(showProgress: false)
      }
    }
    .onReceive(liveUpdates.$latestEvent.compactMap { $0 }) { event in
      if event.affects(.stack, id: summary.id) || event.affects(.server) {
        Task { await loadContent(showProgress: false) }
      }
    }
    .onChange(of: liveUpdates.refreshGeneration) { _, _ in
      Task { await loadContent(showProgress: false) }
    }
    .confirmationDialog(
      stopTitle,
      isPresented: confirmsStop,
      titleVisibility: .visible,
      presenting: stopTarget
    ) { target in
      Button("action.stop", role: .destructive) {
        Task { await confirmStop(target) }
      }
      Button("action.cancel", role: .cancel) {}
    } message: { target in
      Text(stopMessage(for: target))
    }
    .confirmationDialog(
      pendingActionTitle,
      isPresented: confirmsStackAction,
      titleVisibility: .visible,
      presenting: pendingAction
    ) { action in
      Button(action.title, role: action.isDestructive ? .destructive : nil) {
        Task { await runStackAction(action) }
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
    .sheet(isPresented: $showingEditor) {
      if let detail {
        NavigationStack {
          StackEditorView(
            profile: profile,
            keychainStore: keychainStore,
            stack: detail
          ) {
            showingEditor = false
            Task { await loadContent() }
          }
        }
      }
    }
    .navigationDestination(item: $logDestination) { source in
      LogViewerView(
        profile: profile,
        keychainStore: keychainStore,
        source: source,
        appSettings: appSettings
      )
      .environmentObject(liveUpdates)
    }
  }

  private var content: some View {
    List {
      Section("section.overview") {
        LabeledContent("field.status", value: localizedState)
        if !hostName.isEmpty {
          LabeledContent("field.host", value: hostName)
        }
        if let projectName = detail?.config.projectName, !projectName.isEmpty {
          LabeledContent("field.project", value: projectName)
        }
        if let repository = detail?.config.repository, !repository.isEmpty {
          LabeledContent("field.repository", value: repository)
        }
      }

      Section("section.services") {
        if services.isEmpty {
          Text("message.noServices")
            .foregroundStyle(.secondary)
        } else {
          ForEach(services) { service in
            NavigationLink {
              if let container = service.container {
                ContainerDetailView(
                  container: container,
                  profile: profile,
                  keychainStore: keychainStore,
                  appSettings: appSettings,
                  ownerStack: detail
                )
                .environmentObject(liveUpdates)
              } else {
                LogViewerView(
                  profile: profile,
                  keychainStore: keychainStore,
                  source: logSource(for: service),
                  appSettings: appSettings
                )
                .environmentObject(liveUpdates)
              }
            } label: {
              StackServiceRow(
                service: service,
                isBusy: activeActionID == service.id,
                updateAvailable: summary.info.services.first {
                  $0.service == service.service
                }?.updateAvailable == true
              )
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button("action.stop", systemImage: "stop.fill", role: .destructive) {
                stopTarget = .service(service)
              }
              .disabled(isBusy)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
              Button("action.start", systemImage: "play.fill") {
                Task { await runServiceAction(service, start: true) }
              }
              .tint(.green)
              .disabled(isBusy)
            }
            .contextMenu {
              Button("action.openLogs", systemImage: "doc.text.magnifyingglass") {
                logDestination = logSource(for: service)
              }
              Button("action.start", systemImage: "play.fill") {
                Task { await runServiceAction(service, start: true) }
              }
              Button("action.stop", systemImage: "stop.fill", role: .destructive) {
                stopTarget = .service(service)
              }
            }
          }
        }

        if case .failed(let message) = loadState {
          Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        }
      }

      Section("section.observability") {
        NavigationLink {
          LogViewerView(
            profile: profile,
            keychainStore: keychainStore,
            source: allStackLogsSource,
            appSettings: appSettings
          )
          .environmentObject(liveUpdates)
        } label: {
          Label("action.openStackLogs", systemImage: "doc.text.magnifyingglass")
        }
      }

      let containerStats = services.compactMap(\.container?.stats)
      if !containerStats.isEmpty {
        Section("section.currentMetrics") {
          let cpuPercent = containerStats.reduce(0) { $0 + $1.cpuPercent }
          LabeledContent("field.cpu") {
            Text(String(
              format: String(localized: "metrics.cpuWithCores"),
              cpuPercent,
              cpuPercent / 100
            ))
          }
          if let memory = ContainerMemoryUsage.aggregate(containerStats) {
            LabeledContent("field.memory", value: memory.formatted)
            if let percentage = memory.percentage {
              LabeledContent(
                "field.memoryPercent",
                value: String(format: "%.1f %%", percentage)
              )
            }
          } else {
            ForEach(Array(containerStats.enumerated()), id: \.offset) { _, stats in
              LabeledContent(
                stats.name.isEmpty ? String(localized: "field.memory") : stats.name,
                value: stats.memoryUsage
              )
            }
          }
          Text("message.stackMetricsAggregate")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var isBusy: Bool {
    loadState == .loading || activeActionID != nil
  }

  private var activeStackAction: StackResourceAction? {
    guard activeActionID == summary.id else { return nil }
    return currentAction
  }

  @State private var currentAction: StackResourceAction?

  private var updateAvailable: Bool {
    summary.info.services.contains(where: \.updateAvailable)
  }

  private var hostName: String {
    summary.info.swarmName.isEmpty ? summary.info.serverName : summary.info.swarmName
  }

  private var effectiveState: String {
    guard !services.isEmpty else { return summary.info.state }
    let states = Set(services.map { $0.state.lowercased() })
    if states == ["running"] || states == ["healthy"] {
      return "running"
    }
    if states == ["paused"] {
      return "paused"
    }
    if states.isSubset(of: ["stopped", "exited", "created", "down"]) {
      return "stopped"
    }
    if states.contains("unhealthy") || states.contains("dead") {
      return "unhealthy"
    }
    return summary.info.state
  }

  private var localizedState: String {
    switch effectiveState {
    case "running": String(localized: "state.running")
    case "paused": String(localized: "state.paused")
    case "stopped": String(localized: "state.stopped")
    case "created": String(localized: "state.created")
    case "restarting": String(localized: "state.restarting")
    case "deploying": String(localized: "state.deploying")
    case "unhealthy", "dead": String(localized: "state.unhealthy")
    case "down": String(localized: "state.down")
    default: String(localized: "state.unknown")
    }
  }

  private var stopTitle: String {
    switch stopTarget {
    case .service(let service):
      String(format: String(localized: "confirm.stopService.title"), service.service)
    default: String(localized: "confirm.stopStack.title")
    }
  }

  private var confirmsStop: Binding<Bool> {
    Binding(
      get: { stopTarget != nil },
      set: { if !$0 { stopTarget = nil } }
    )
  }

  private var showsActionError: Binding<Bool> {
    Binding(
      get: { actionError != nil },
      set: { if !$0 { actionError = nil } }
    )
  }

  private var confirmsStackAction: Binding<Bool> {
    Binding(
      get: { pendingAction != nil },
      set: { if !$0 { pendingAction = nil } }
    )
  }

  private var pendingActionTitle: String {
    guard let pendingAction else { return String(localized: "title.stackActions") }
    return pendingAction.title
  }

  private var allStackLogsSource: LogSource {
    .stack(
      id: summary.id,
      name: detail?.name ?? summary.name,
      services: services.map(\.service),
      selectedServices: []
    )
  }

  private func logSource(for service: StackService) -> LogSource {
    .stack(
      id: summary.id,
      name: service.service,
      services: services.map(\.service),
      selectedServices: [service.service]
    )
  }

  private func confirmationMessage(for action: StackResourceAction) -> String {
    let name = detail?.name ?? summary.name
    return switch action {
    case .stop:
      String(localized: "confirm.stopAllServices")
    case .destroy:
      String(format: String(localized: "confirm.destroyStack.message"), name)
    case .deleteDefinition:
      String(format: String(localized: "confirm.deleteStack.message"), name)
    default:
      String(format: String(localized: "confirm.stackAction.message"), name)
    }
  }

  private func handleStackAction(_ action: StackResourceAction) {
    switch action {
    case .stop, .destroy, .deleteDefinition:
      pendingAction = action
    default:
      Task { await runStackAction(action) }
    }
  }

  private func stopMessage(for target: StopTarget) -> String {
    switch target {
    case .stack:
      String(localized: "confirm.stopAllServices")
    case .service(let service):
      String(format: String(localized: "confirm.stopService"), service.service)
    }
  }

  @MainActor
  private func loadContent(showProgress: Bool = true) async {
    if showProgress { loadState = .loading }
    do {
      let client = try await makeClient()
      async let loadedDetail = client.getStack(idOrName: summary.id)
      async let loadedServices = client.listStackServices(stack: summary.id)
      detail = try await loadedDetail
      services = try await loadedServices
      loadState = .loaded
    } catch is CancellationError {
      return
    } catch {
      loadState = .failed(localizedMessage(for: error))
    }
  }

  @MainActor
  private func runStackAction(_ action: StackResourceAction) async {
    pendingAction = nil
    activeActionID = summary.id
    currentAction = action
    defer {
      activeActionID = nil
      currentAction = nil
    }
    do {
      let client = try await makeClient()
      switch action {
      case .deploy: _ = try await client.deployStack(idOrName: summary.id)
      case .pull: _ = try await client.pullStackImages(idOrName: summary.id)
      case .start: _ = try await client.startStack(idOrName: summary.id)
      case .restart: _ = try await client.restartStack(idOrName: summary.id)
      case .pause: _ = try await client.pauseStack(idOrName: summary.id)
      case .resume: _ = try await client.unpauseStack(idOrName: summary.id)
      case .stop: _ = try await client.stopStack(idOrName: summary.id)
      case .destroy: _ = try await client.destroyStack(idOrName: summary.id)
      case .deleteDefinition:
        _ = try await client.deleteStack(idOrName: summary.id)
        liveUpdates.requestRefresh()
        dismiss()
        return
      }
      await loadContent()
    } catch {
      actionError = localizedMessage(for: error)
    }
  }

  @MainActor
  private func runServiceAction(_ service: StackService, start: Bool) async {
    activeActionID = service.id
    defer { activeActionID = nil }
    do {
      let client = try await makeClient()
      if let serverID = service.container?.serverID, let container = service.container?.name {
        if start {
          _ = try await client.startContainer(server: serverID, container: container)
        } else {
          _ = try await client.stopContainer(server: serverID, container: container)
        }
      } else if start {
        _ = try await client.startStack(idOrName: summary.id, services: [service.service])
      } else {
        _ = try await client.stopStack(idOrName: summary.id, services: [service.service])
      }
      await loadContent()
    } catch {
      actionError = localizedMessage(for: error)
    }
  }

  @MainActor
  private func confirmStop(_ target: StopTarget) async {
    stopTarget = nil
    switch target {
    case .stack:
      await runStackAction(.stop)
    case .service(let service):
      await runServiceAction(service, start: false)
    }
  }

  private func makeClient() async throws -> KomodoAPIClient {
    try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
  }

  private func localizedMessage(for error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(localized: "error.stack.loadFailed")
  }
}

private struct StackActionMenu: View {
  let state: String
  let updateAvailable: Bool
  let isEnabled: Bool
  let activeAction: StackResourceAction?
  let edit: () -> Void
  let perform: (StackResourceAction) -> Void

  var body: some View {
    Menu {
      Button("action.edit", systemImage: "pencil", action: edit)

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
        Label("title.stackActions", systemImage: "ellipsis.circle")
      }
    }
    .disabled(!isEnabled || activeAction != nil)
    .accessibilityLabel(activeAction?.title ?? String(localized: "title.stackActions"))
  }

  private func actionButton(_ action: StackResourceAction) -> some View {
    Button(role: action.isDestructive ? .destructive : nil) {
      perform(action)
    } label: {
      if action == .pull, updateAvailable {
        Label(
          "\(action.title) · \(String(localized: "status.updateAvailable"))",
          systemImage: action.symbol
        )
      } else {
        Label(action.title, systemImage: action.symbol)
      }
    }
  }

  private var actions: [StackResourceAction] {
    switch state.lowercased() {
    case "running", "healthy":
      [.deploy, .pull, .restart, .pause, .stop, .destroy, .deleteDefinition]
    case "paused":
      [.resume, .stop, .restart, .destroy, .deleteDefinition]
    case "stopped", "exited", "created":
      [.start, .deploy, .pull, .restart, .destroy, .deleteDefinition]
    case "down":
      [.deploy, .pull, .deleteDefinition]
    default:
      [.deploy, .pull, .deleteDefinition]
    }
  }
}

private struct StackServiceRow: View {
  let service: StackService
  let isBusy: Bool
  let updateAvailable: Bool

  var body: some View {
    HStack(spacing: 12) {
      if isBusy {
        ProgressView()
          .controlSize(.small)
          .frame(width: 22)
      } else {
        Image(systemName: stateSymbol)
          .foregroundStyle(stateColor)
          .frame(width: 22)
          .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 3) {
        Text(service.service)
          .font(.headline)
        Text(service.container?.image ?? service.image)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let name = service.container?.name, !name.isEmpty {
          Text(name)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        if updateAvailable {
          Label("status.updateAvailable", systemImage: "arrow.down.circle.fill")
            .font(.caption)
            .foregroundStyle(.blue)
        }
      }

      Spacer()

      Text(localizedState)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(service.service))
    .accessibilityValue(Text(accessibilityValue))
  }

  private var accessibilityValue: String {
    var components = [service.container?.image ?? service.image, localizedState]
    if let name = service.container?.name, !name.isEmpty {
      components.insert(name, at: 1)
    }
    if updateAvailable {
      components.append(String(localized: "status.updateAvailable"))
    }
    return components.filter { !$0.isEmpty }.joined(separator: ", ")
  }

  private var normalizedState: String {
    (service.container?.state.isEmpty == false ? service.container?.state : service.state)?
      .lowercased() ?? "unknown"
  }

  private var localizedState: String {
    switch normalizedState {
    case "running", "healthy": String(localized: "state.running")
    case "paused": String(localized: "state.paused")
    case "created": String(localized: "state.created")
    case "exited", "stopped", "down": String(localized: "state.stopped")
    case "restarting": String(localized: "state.restarting")
    case "unhealthy", "dead": String(localized: "state.unhealthy")
    default: String(localized: "state.unknown")
    }
  }

  private var stateSymbol: String {
    switch normalizedState {
    case "running", "healthy": "checkmark.circle.fill"
    case "paused", "created", "exited", "stopped", "down": "pause.circle.fill"
    case "restarting": "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
    case "unhealthy", "dead": "exclamationmark.triangle.fill"
    default: "questionmark.circle.fill"
    }
  }

  private var stateColor: Color {
    switch normalizedState {
    case "running", "healthy": .green
    case "unhealthy", "dead": .red
    case "restarting": .blue
    default: .secondary
    }
  }
}

enum LogSearch {
  struct Result: Equatable, Sendable {
    let output: String
    let query: String
    let matchCount: Int

    var isActive: Bool { !query.isEmpty }
  }

  struct Presentation: Sendable {
    let result: Result
    let highlightedOutput: AttributedString
    let highlightedLines: [AttributedString]
  }

  static func prepare(_ query: String, in output: String) -> Presentation {
    let result = find(query, in: output)
    guard result.isActive else {
      return Presentation(
        result: result,
        highlightedOutput: AttributedString(result.output),
        highlightedLines: []
      )
    }
    let highlightedLines = result.output
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { highlight(String($0), query: result.query) }
    return Presentation(
      result: result,
      highlightedOutput: AttributedString(),
      highlightedLines: highlightedLines
    )
  }

  static func find(_ query: String, in output: String) -> Result {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else {
      return Result(output: output, query: "", matchCount: 0)
    }

    var matchingLines: [String] = []
    var totalMatchCount = 0
    for substring in output.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(substring)
      let lineMatchCount = matchCount(of: normalizedQuery, in: line)
      if lineMatchCount > 0 {
        matchingLines.append(line)
        totalMatchCount += lineMatchCount
      }
    }
    return Result(
      output: matchingLines.joined(separator: "\n"),
      query: normalizedQuery,
      matchCount: totalMatchCount
    )
  }

  private static func matchCount(of query: String, in output: String) -> Int {
    var count = 0
    var searchRange = output.startIndex..<output.endIndex
    while let match = output.range(
      of: query,
      options: [.caseInsensitive, .diacriticInsensitive],
      range: searchRange
    ) {
      count += 1
      searchRange = match.upperBound..<output.endIndex
    }
    return count
  }

  private static func highlight(_ source: String, query: String) -> AttributedString {
    var output = AttributedString(source)
    var searchRange = source.startIndex..<source.endIndex
    while let match = source.range(
      of: query,
      options: [.caseInsensitive, .diacriticInsensitive],
      range: searchRange
    ) {
      guard let lowerBound = AttributedString.Index(match.lowerBound, within: output),
            let upperBound = AttributedString.Index(match.upperBound, within: output) else {
        break
      }
      output[lowerBound..<upperBound].backgroundColor = .yellow.opacity(0.7)
      output[lowerBound..<upperBound].foregroundColor = .black
      searchRange = match.upperBound..<source.endIndex
    }
    return output
  }
}

enum LogSource: Hashable, Identifiable {
  case stack(id: String, name: String, services: [String], selectedServices: [String])
  case container(serverID: String, name: String)

  var id: String {
    switch self {
    case .stack(let id, _, _, let selectedServices):
      "stack-\(id)-\(selectedServices.sorted().joined(separator: ","))"
    case .container(let serverID, let name):
      "container-\(serverID)-\(name)"
    }
  }

  var title: String {
    switch self {
    case .stack(_, let name, _, _): name
    case .container(_, let name): name
    }
  }

  var availableServices: [String] {
    switch self {
    case .stack(_, _, let services, _): services
    case .container: []
    }
  }

  var initialServices: Set<String> {
    switch self {
    case .stack(_, _, _, let selectedServices): Set(selectedServices)
    case .container: []
    }
  }
}

struct LogViewerView: View {
  private enum Stream: String, CaseIterable, Identifiable {
    case combined
    case standardOutput
    case errorOutput

    var id: Self { self }

    var title: String {
      switch self {
      case .combined: String(localized: "log.all")
      case .standardOutput: "stdout"
      case .errorOutput: "stderr"
      }
    }
  }

  let profile: ServerProfile
  let keychainStore: KeychainStore
  let source: LogSource
  @ObservedObject var appSettings: AppSettings

  @State private var log: KomodoLog?
  @State private var searchText = ""
  @State private var errorMessage: String?
  @State private var isLoading = true
  @State private var followsLatest: Bool
  @State private var selectedStream = Stream.combined
  @State private var searchResult = LogSearch.Result(output: "", query: "", matchCount: 0)
  @State private var highlightedOutput = AttributedString()
  @State private var highlightedLines: [AttributedString] = []
  @State private var logRevision = 0
  @State private var selectedServices: Set<String>
  @State private var tail = 200

  init(
    profile: ServerProfile,
    keychainStore: KeychainStore,
    source: LogSource,
    appSettings: AppSettings
  ) {
    self.profile = profile
    self.keychainStore = keychainStore
    self.source = source
    self.appSettings = appSettings
    _followsLatest = State(initialValue: appSettings.logsFollowLatest)
    _selectedServices = State(initialValue: source.initialServices)
  }

  var body: some View {
    VStack(spacing: 0) {
      logControls
      Divider()

      ZStack {
        logContent

        if isLoading, log == nil {
          ProgressView("status.loadingLogs")
        } else if log == nil, let errorMessage {
          ContentUnavailableView {
            Label("title.logsUnavailable", systemImage: "doc.text.magnifyingglass")
          } description: {
            Text(errorMessage)
          } actions: {
            Button("action.retry") {
              Task { await loadLog() }
            }
          }
        }
      }
    }
    .navigationTitle(String(format: String(localized: "log.title"), source.title))
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItemGroup {
        LiveConnectionStatusButton(
          profile: profile,
          keychainStore: keychainStore,
          appSettings: appSettings
        )
        Button("action.refreshNow", systemImage: "arrow.clockwise") {
          Task { await loadLog() }
        }
        .disabled(isLoading)

      }
    }
    .task(id: logLoadingTaskID) {
      await loadLog()
      while appSettings.logsAutoRefresh, !Task.isCancelled {
        try? await Task.sleep(for: .seconds(appSettings.logRefreshInterval.rawValue))
        guard !Task.isCancelled else { return }
        await loadLog(showProgress: false)
      }
    }
    .onChange(of: appSettings.logsFollowLatest) { _, follows in
      followsLatest = follows
    }
    .task(id: searchTaskID) {
      await updateSearchResult()
    }
#if os(iOS)
    .toolbar(.hidden, for: .tabBar)
#endif
  }

  private var logControls: some View {
    VStack(spacing: 8) {
      HStack {
        if !source.availableServices.isEmpty {
          serviceScopeMenu
        }
        Spacer()
        Picker("log.tail", selection: $tail) {
          Text(verbatim: "100").tag(100)
          Text(verbatim: "200").tag(200)
          Text(verbatim: "500").tag(500)
          Text(verbatim: "1,000").tag(1_000)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel("log.tail")
      }

      Picker("log.stream", selection: $selectedStream) {
        ForEach(Stream.allCases) { stream in
          Text(stream.title).tag(stream)
        }
      }
      .pickerStyle(.segmented)

      logSearchField
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }

  private var serviceScopeMenu: some View {
    Menu {
      Button {
        selectedServices.removeAll()
      } label: {
        if selectedServices.isEmpty {
          Label("log.allServices", systemImage: "checkmark")
        } else {
          Text("log.allServices")
        }
      }
      Divider()
      ForEach(source.availableServices, id: \.self) { service in
        Button {
          if selectedServices.contains(service) {
            selectedServices.remove(service)
          } else {
            selectedServices.insert(service)
          }
        } label: {
          if selectedServices.contains(service) {
            Label(service, systemImage: "checkmark")
          } else {
            Text(service)
          }
        }
      }
    } label: {
      Label(serviceScopeTitle, systemImage: "line.3.horizontal.decrease.circle")
    }
  }

  private var serviceScopeTitle: String {
    if selectedServices.isEmpty {
      return String(localized: "log.allServices")
    }
    if selectedServices.count == 1 {
      return selectedServices.first ?? String(localized: "log.allServices")
    }
    return String(
      format: String(localized: "log.selectedServices"),
      selectedServices.count
    )
  }

  @ViewBuilder
  private var logSearchField: some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      logSearchFieldContent
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
    } else {
      logSearchFieldContent
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(.separator.opacity(0.35), lineWidth: 0.5)
        }
    }
  }

  private var logSearchFieldContent: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField("log.search", text: $searchText)
        .textFieldStyle(.plain)
        #if os(iOS)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        #endif
      if searchResult.isActive {
        Text(String(format: String(localized: "log.matchCount"), searchResult.matchCount))
          .font(.caption)
          .foregroundStyle(searchResult.matchCount == 0 ? .red : .secondary)
          .monospacedDigit()
          .fixedSize()
        Button("log.clearSearch", systemImage: "xmark.circle.fill") {
          searchText = ""
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 36)
  }

  private var logContent: some View {
    Group {
      if log != nil,
         !searchResult.isActive,
         selectedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        ContentUnavailableView("label.noLogOutput", systemImage: "doc.text")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            Color.clear
              .frame(height: 1)
              .id("log-start")
            if searchResult.isActive, searchResult.matchCount == 0 {
              ContentUnavailableView(
                "log.noMatches",
                systemImage: "magnifyingglass",
                description: Text("log.noMatches.description")
              )
              .frame(maxWidth: .infinity, minHeight: 240)
            } else if searchResult.isActive {
              LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(highlightedLines.indices, id: \.self) { index in
                  Text(highlightedLines[index])
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .padding()
            } else {
              Text(highlightedOutput)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            Color.clear
              .frame(height: 1)
              .id("log-end")
          }
          .defaultScrollAnchor(.bottom)
          .onScrollPhaseChange { _, newPhase in
            if newPhase == .interacting {
              followsLatest = false
            }
          }
          .onChange(of: log) {
            guard followsLatest, !searchResult.isActive else { return }
            proxy.scrollTo("log-end", anchor: .bottom)
          }
          .onChange(of: searchText) {
            if searchResult.isActive {
              proxy.scrollTo("log-start", anchor: .top)
            } else if followsLatest {
              proxy.scrollTo("log-end", anchor: .bottom)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .top) {
      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .padding(8)
          .background(.regularMaterial)
      }
    }
  }

  private var selectedOutput: String {
    let output = switch selectedStream {
    case .combined: log?.combinedOutput ?? ""
    case .standardOutput: log?.cleanedStandardOutput ?? ""
    case .errorOutput: log?.cleanedErrorOutput ?? ""
    }
    return output
  }

  private struct SearchTaskID: Equatable {
    let query: String
    let stream: Stream
    let logRevision: Int
  }

  private var searchTaskID: SearchTaskID {
    SearchTaskID(query: searchText, stream: selectedStream, logRevision: logRevision)
  }

  private var logLoadingTaskID: String {
    let services = selectedServices.sorted().joined(separator: ",")
    return "\(source.id)-\(services)-\(tail)-\(appSettings.logsAutoRefresh)-\(appSettings.logRefreshInterval.rawValue)"
  }

  @MainActor
  private func updateSearchResult() async {
    let query = searchText
    let output = selectedOutput
    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      do {
        try await Task.sleep(for: .milliseconds(180))
      } catch {
        return
      }
    }

    let presentation = await Task.detached(priority: .userInitiated) {
      LogSearch.prepare(query, in: output)
    }.value
    guard !Task.isCancelled else { return }

    searchResult = presentation.result
    highlightedOutput = presentation.highlightedOutput
    highlightedLines = presentation.highlightedLines
  }

  @MainActor
  private func loadLog(showProgress: Bool = true) async {
    if showProgress {
      isLoading = true
    }
    defer { isLoading = false }
    do {
      guard let credentials = try await keychainStore.credentials(
        for: profile.credentialAccount
      ), credentials.authenticationKind == profile.authenticationKind else {
        throw KeychainStoreError.invalidCredentialData
      }
      let client = KomodoAPIClient(
        address: try profile.address,
        authentication: credentials.authentication
      )
      let loadedLog: KomodoLog
      switch source {
      case .stack(let stackID, _, _, _):
        loadedLog = try await client.getStackLog(
          stack: stackID,
          services: selectedServices.sorted(),
          tail: tail
        )
      case .container(let serverID, let name):
        loadedLog = try await client.getContainerLog(
          server: serverID,
          container: name,
          tail: tail
        )
      }
      log = loadedLog
      logRevision += 1
      errorMessage = nil
    } catch is CancellationError {
      return
    } catch {
      errorMessage =
        (error as? LocalizedError)?.errorDescription ?? String(localized: "error.logs.loadFailed")
    }
  }
}

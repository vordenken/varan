import SwiftUI

struct StackDetailView: View {
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

  @State private var detail: StackDetail?
  @State private var services: [StackService] = []
  @State private var loadState = LoadState.loading
  @State private var activeActionID: String?
  @State private var stopTarget: StopTarget?
  @State private var actionError: String?

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
    .navigationTitle(detail?.name ?? summary.name)
    .toolbar {
      ToolbarItemGroup {
        Button("action.refresh", systemImage: "arrow.clockwise") {
          Task { await loadContent() }
        }
        .disabled(isBusy)

        Menu(
          stackIsRunning ? "status.stackRunning" : "title.stackActions",
          systemImage: stackIsRunning ? "checkmark.circle.fill" : "ellipsis.circle"
        ) {
          if stackIsRunning {
            Button("status.stackRunning", systemImage: "checkmark.circle.fill") {}
              .disabled(true)
          } else {
            Button("action.startStack", systemImage: "play.fill") {
              Task { await runStackAction(start: true) }
            }
          }
          Button("action.stopStack", systemImage: "stop.fill", role: .destructive) {
            stopTarget = .stack
          }
        }
        .disabled(isBusy)
      }
    }
    .refreshable {
      await loadContent()
    }
    .task(id: summary.id) {
      await loadContent()
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
    .alert("alert.actionFailed", isPresented: showsActionError) {
      Button("action.ok") { actionError = nil }
    } message: {
      Text(actionError ?? String(localized: "error.unknown"))
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
              StackLogView(
                profile: profile,
                keychainStore: keychainStore,
                stackID: summary.id,
                service: service
              )
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
    }
  }

  private var isBusy: Bool {
    loadState == .loading || activeActionID != nil
  }

  private var stackIsRunning: Bool {
    effectiveState == "running"
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
    if states.isSubset(of: ["stopped", "exited", "paused", "created", "down"]) {
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

  private func stopMessage(for target: StopTarget) -> String {
    switch target {
    case .stack:
      String(localized: "confirm.stopAllServices")
    case .service(let service):
      String(format: String(localized: "confirm.stopService"), service.service)
    }
  }

  @MainActor
  private func loadContent() async {
    loadState = .loading
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
  private func runStackAction(start: Bool) async {
    activeActionID = summary.id
    defer { activeActionID = nil }
    do {
      let client = try await makeClient()
      if start {
        _ = try await client.startStack(idOrName: summary.id)
      } else {
        _ = try await client.stopStack(idOrName: summary.id)
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
      await runStackAction(start: false)
    case .service(let service):
      await runServiceAction(service, start: false)
    }
  }

  private func makeClient() async throws -> KomodoAPIClient {
    guard let credentials = try await keychainStore.credentials(
      for: profile.credentialAccount
    ), credentials.authenticationKind == profile.authenticationKind else {
      throw KeychainStoreError.invalidCredentialData
    }
    return KomodoAPIClient(
      address: try profile.address,
      authentication: credentials.authentication
    )
  }

  private func localizedMessage(for error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(localized: "error.stack.loadFailed")
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
    .accessibilityElement(children: .combine)
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

private struct StackLogView: View {
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
  let stackID: String
  let service: StackService

  @State private var log: KomodoLog?
  @State private var searchText = ""
  @State private var errorMessage: String?
  @State private var isLoading = true
  @State private var refreshesAutomatically = true
  @State private var followsLatest = true
  @State private var selectedStream = Stream.combined
  @State private var searchResult = LogSearch.Result(output: "", query: "", matchCount: 0)
  @State private var highlightedOutput = AttributedString()
  @State private var highlightedLines: [AttributedString] = []
  @State private var logRevision = 0

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
    .navigationTitle(String(format: String(localized: "log.title"), service.service))
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItemGroup {
        Button("action.refreshNow", systemImage: "arrow.clockwise") {
          Task { await loadLog() }
        }
        .disabled(isLoading)

        Menu("log.settings", systemImage: "slider.horizontal.3") {
          Toggle("log.autoRefresh", isOn: $refreshesAutomatically)
          Toggle("log.followLatest", isOn: $followsLatest)
        }
      }
    }
    .task(id: refreshesAutomatically) {
      await loadLog()
      while refreshesAutomatically, !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        await loadLog(showProgress: false)
      }
    }
    .task(id: searchTaskID) {
      await updateSearchResult()
    }
  }

  private var logControls: some View {
    VStack(spacing: 8) {
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
      let log: KomodoLog
      if let serverID = service.container?.serverID, let container = service.container?.name {
        log = try await client.getContainerLog(server: serverID, container: container)
      } else {
        log = try await client.getStackLog(stack: stackID, services: [service.service])
      }
      self.log = log
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
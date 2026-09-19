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
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @State private var section = ResourceSection.stacks

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
        case .servers: ServerListView(profile: profile, keychainStore: keychainStore)
        case .stacks: StackListView(profile: profile, keychainStore: keychainStore)
        case .containers: ContainerListView(profile: profile, keychainStore: keychainStore)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

@MainActor
func makeKomodoClient(profile: ServerProfile, keychainStore: KeychainStore) async throws
  -> KomodoAPIClient
{
  guard let credentials = try await keychainStore.credentials(for: profile.credentialAccount),
        credentials.authenticationKind == profile.authenticationKind else {
    throw KeychainStoreError.invalidCredentialData
  }
  return KomodoAPIClient(address: try profile.address, authentication: credentials.authentication)
}

struct ServerListView: View {
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @State private var servers: [ServerListItem] = []
  @State private var searchText = ""
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
        List(filteredServers) { server in
          NavigationLink {
            ServerDetailView(summary: server, profile: profile, keychainStore: keychainStore)
          } label: {
            HStack {
              Image(systemName: server.info.state.lowercased() == "ok" ? "checkmark.circle.fill" : "server.rack")
                .foregroundStyle(server.info.state.lowercased() == "ok" ? .green : .secondary)
              VStack(alignment: .leading) {
                Text(server.name).font(.headline)
                Text([server.info.region, server.info.address ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                  .font(.subheadline).foregroundStyle(.secondary)
              }
              Spacer()
              if let stats = server.info.stats {
                Text(stats.cpuPercent, format: .number.precision(.fractionLength(0)).rounded(rule: .up).scale(1).notation(.automatic))
                  .font(.caption.monospacedDigit())
                  .accessibilityLabel("field.cpu")
              }
            }
          }
        }
        .refreshable { await load() }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("title.servers")
    .searchable(text: $searchText, prompt: "action.searchServers")
    .toolbar {
      ToolbarItemGroup {
        Button("action.addServer", systemImage: "plus") { showingCreate = true }
        Button("action.refresh", systemImage: "arrow.clockwise") { Task { await load() } }
          .disabled(isLoading)
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
  }

  private var filteredServers: [ServerListItem] {
    guard !searchText.isEmpty else { return servers }
    return servers.filter { $0.name.localizedCaseInsensitiveContains(searchText)
      || $0.info.region.localizedCaseInsensitiveContains(searchText) }
  }

  @MainActor private func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      servers = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
        .listServers()
      errorMessage = nil
    } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
  }
}

struct ServerDetailView: View {
  let summary: ServerListItem
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @State private var server: ServerDetail?
  @State private var stats: SystemStats?
  @State private var history: [SystemStatsRecord] = []
  @State private var containers: [ContainerListItem] = []
  @State private var stacks: [StackListItem] = []
  @State private var errorMessage: String?
  @State private var isLoading = true
  @State private var autoRefresh = true
  @State private var showingEditor = false
  @State private var granularity = "15-min"

  var body: some View {
    List {
      if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
      Section("section.overview") {
        LabeledContent("field.status", value: server?.info.state ?? summary.info.state)
        if let version = server?.info.version { LabeledContent("field.version", value: version) }
        if let config = server?.config {
          LabeledContent("field.address", value: config.address)
          if !config.region.isEmpty { LabeledContent("field.region", value: config.region) }
        }
      }
      if let stats {
        Section("section.currentMetrics") {
          MetricRow(title: "field.cpu", value: stats.cpuPercent, unit: "%")
          MetricRow(title: "field.memory", value: stats.memoryUsedGB, total: stats.memoryTotalGB, unit: "GB")
          LabeledContent("field.loadAverage", value: String(format: "%.2f · %.2f · %.2f", stats.loadAverage.one, stats.loadAverage.five, stats.loadAverage.fifteen))
          LabeledContent("field.networkIn", value: ByteCountFormatter.string(fromByteCount: stats.networkIngressBytes, countStyle: .file))
          LabeledContent("field.networkOut", value: ByteCountFormatter.string(fromByteCount: stats.networkEgressBytes, countStyle: .file))
          if !stats.pollingRate.isEmpty { LabeledContent("field.pollingRate", value: stats.pollingRate) }
          if stats.refreshTimestamp > 0 {
            LabeledContent("field.lastMeasurement", value: measurementDate(stats.refreshTimestamp).formatted(date: .abbreviated, time: .standard))
          }
          ForEach(stats.disks) { disk in
            MetricRow(title: LocalizedStringKey(disk.mount), value: disk.usedGB, total: disk.totalGB, unit: "GB")
          }
        }
      } else if !isLoading {
        Section("section.currentMetrics") { Text("message.metricsUnavailable").foregroundStyle(.secondary) }
      }
      if !history.isEmpty {
        Section("section.history") {
          Picker("field.granularity", selection: $granularity) {
            Text("metrics.fifteenMinutes").tag("15-min")
            Text("metrics.oneHour").tag("1-hour")
            Text("metrics.oneDay").tag("1-day")
          }
          .pickerStyle(.segmented)
          Chart(history) { point in
            LineMark(x: .value("Time", measurementDate(point.timestamp)),
                     y: .value("CPU", point.cpuPercent))
              .foregroundStyle(.green)
          }
          .chartYAxisLabel("CPU %")
          .frame(minHeight: 180)
        }
      }
      Section("title.stacks") {
        if stacks.isEmpty { Text("message.noStacks").foregroundStyle(.secondary) }
        ForEach(stacks) { stack in
          NavigationLink {
            StackDetailView(summary: stack, profile: profile, keychainStore: keychainStore)
          } label: { Text(stack.name) }
        }
      }
      Section("title.containers") {
        if containers.isEmpty { Text("message.noContainers").foregroundStyle(.secondary) }
        ForEach(containers) { container in
          NavigationLink {
            ContainerDetailView(container: container, profile: profile, keychainStore: keychainStore)
          } label: { ContainerRow(container: container) }
        }
      }
    }
    .navigationTitle(server?.name ?? summary.name)
    .toolbar {
      ToolbarItemGroup {
        Button("action.edit", systemImage: "pencil") { showingEditor = true }.disabled(server == nil)
        Menu("metrics.refreshSettings", systemImage: "timer") {
          Toggle("metrics.autoRefresh", isOn: $autoRefresh)
        }
        Button("action.refresh", systemImage: "arrow.clockwise") { Task { await load() } }.disabled(isLoading)
      }
    }
    .sheet(isPresented: $showingEditor) {
      if let server {
        NavigationStack {
          ServerEditorView(profile: profile, keychainStore: keychainStore, server: server) {
            showingEditor = false
            Task { await load() }
          }
        }
      }
    }
    .task(id: summary.id) { await load() }
    .task(id: granularity) { await loadHistory() }
    .task(id: autoRefresh) {
      while autoRefresh, !Task.isCancelled {
        try? await Task.sleep(for: .seconds(15))
        guard !Task.isCancelled else { return }
        await load(showProgress: false)
      }
    }
  }

  @MainActor private func load(showProgress: Bool = true) async {
    if showProgress { isLoading = true }
    defer { isLoading = false }
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      async let loadedServer = client.getServer(idOrName: summary.id)
      async let loadedStats = client.getSystemStats(server: summary.id)
      async let loadedHistory = client.getHistoricalServerStats(server: summary.id)
      async let loadedContainers = client.listContainers(server: summary.id)
      async let loadedStacks = client.listStacks()
      server = try await loadedServer
      stats = try? await loadedStats
      history = (try? await loadedHistory.stats) ?? []
      containers = (try? await loadedContainers) ?? []
      let allStacks = (try? await loadedStacks) ?? []
      stacks = allStacks.filter { $0.info.serverName == summary.name }
      errorMessage = nil
    } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
  }

  @MainActor private func loadHistory() async {
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      history = try await client.getHistoricalServerStats(server: summary.id, granularity: granularity).stats
    } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
  }

  private func measurementDate(_ timestamp: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(timestamp) / (timestamp > 10_000_000_000 ? 1_000 : 1))
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

struct ContainerListView: View {
  let profile: ServerProfile
  let keychainStore: KeychainStore
  @State private var containers: [ContainerListItem] = []
  @State private var searchText = ""
  @State private var errorMessage: String?
  @State private var isLoading = true

  var body: some View {
    Group {
      if isLoading, containers.isEmpty { ProgressView("status.loadingContainers") }
      else if let errorMessage, containers.isEmpty {
        ContentUnavailableView("title.containersUnavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
      } else {
        List(filteredContainers) { container in
          NavigationLink {
            ContainerDetailView(container: container, profile: profile, keychainStore: keychainStore)
          } label: { ContainerRow(container: container) }
        }
        .refreshable { await load() }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("title.containers")
    .searchable(text: $searchText, prompt: "action.searchContainers")
    .toolbar { Button("action.refresh", systemImage: "arrow.clockwise") { Task { await load() } }.disabled(isLoading) }
    .task(id: profile.id) { await load() }
  }

  private var filteredContainers: [ContainerListItem] {
    guard !searchText.isEmpty else { return containers }
    return containers.filter { $0.name.localizedCaseInsensitiveContains(searchText)
      || ($0.image?.localizedCaseInsensitiveContains(searchText) == true)
      || ($0.serverName?.localizedCaseInsensitiveContains(searchText) == true) }
  }

  @MainActor private func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      containers = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
        .listAllContainers()
      errorMessage = nil
    } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
  }
}

struct ContainerRow: View {
  let container: ContainerListItem
  var body: some View {
    HStack {
      Image(systemName: container.state.lowercased() == "running" ? "checkmark.circle.fill" : "shippingbox")
        .foregroundStyle(container.state.lowercased() == "running" ? .green : .secondary)
      VStack(alignment: .leading) {
        Text(container.name).font(.headline)
        Text([container.image ?? "", container.serverName ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
          .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer()
      Text(container.state).font(.caption).foregroundStyle(.secondary)
    }
  }
}

struct ContainerDetailView: View {
  let container: ContainerListItem
  let profile: ServerProfile
  let keychainStore: KeychainStore
  var ownerStack: StackDetail? = nil
  @State private var log: KomodoLog?
  @State private var errorMessage: String?
  @State private var isLoadingLog = false
  @State private var showingStackEditor = false

  var body: some View {
    List {
      Section("section.overview") {
        LabeledContent("field.status", value: container.status ?? container.state)
        if let image = container.image { LabeledContent("field.image", value: image) }
        if let server = container.serverName { LabeledContent("field.server", value: server) }
        if let mode = container.networkMode { LabeledContent("field.networkMode", value: mode) }
      }
      if let stats = container.stats {
        Section("section.currentMetrics") {
          LabeledContent("field.cpu") {
            Text(String(
              format: String(localized: "metrics.cpuWithCores"),
              stats.cpuPercent,
              stats.cpuCoreEquivalent
            ))
          }
          LabeledContent("field.memory", value: stats.memoryUsage)
          if stats.memoryPercent > 0 {
            LabeledContent(
              "field.memoryPercent",
              value: String(format: "%.1f %%", stats.memoryPercent)
            )
          }
          LabeledContent("field.networkIO", value: stats.networkIO)
          LabeledContent("field.blockIO", value: stats.blockIO)
          LabeledContent("field.processes", value: String(stats.processCount))
        }
      }
      if !container.ports.isEmpty {
        Section("section.ports") {
          ForEach(Array(container.ports.enumerated()), id: \.offset) { _, port in
            LabeledContent("\(port.type.uppercased()) \(port.privatePort)", value: port.publicPort.map(String.init) ?? "—")
          }
        }
      }
      if !container.networks.isEmpty { Section("section.networks") { ForEach(container.networks, id: \.self, content: Text.init) } }
      if !container.volumes.isEmpty { Section("section.volumes") { ForEach(container.volumes, id: \.self, content: Text.init) } }
      Section("section.logs") {
        if isLoadingLog { ProgressView("status.loadingLogs") }
        else if let log { Text(log.combinedOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
        else { Text(errorMessage ?? String(localized: "label.noLogOutput")).foregroundStyle(.secondary) }
      }
    }
    .navigationTitle(container.name)
    .toolbar {
      ToolbarItemGroup {
        if ownerStack != nil {
          Button("action.editContainerConfiguration", systemImage: "pencil") { showingStackEditor = true }
        }
        Button("action.refresh", systemImage: "arrow.clockwise") { Task { await loadLog() } }
      }
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
    .task { await loadLog() }
  }

  @MainActor private func loadLog() async {
    guard let server = container.serverID else { return }
    isLoadingLog = true
    defer { isLoadingLog = false }
    do {
      log = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
        .getContainerLog(server: server, container: container.name)
      errorMessage = nil
    } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
  }
}

struct ServerEditorView: View {
  let profile: ServerProfile
  let keychainStore: KeychainStore
  let server: ServerDetail?
  let onSaved: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var address: String
  @State private var externalAddress: String
  @State private var region: String
  @State private var enabled: Bool
  @State private var insecureTLS: Bool
  @State private var autoPrune: Bool
  @State private var statsMonitoring: Bool
  @State private var showingReview = false
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(profile: ServerProfile, keychainStore: KeychainStore, server: ServerDetail? = nil, onSaved: @escaping () -> Void) {
    self.profile = profile; self.keychainStore = keychainStore; self.server = server; self.onSaved = onSaved
    _name = State(initialValue: server?.name ?? "")
    _address = State(initialValue: server?.config.address ?? "https://")
    _externalAddress = State(initialValue: server?.config.externalAddress ?? "")
    _region = State(initialValue: server?.config.region ?? "")
    _enabled = State(initialValue: server?.config.enabled ?? true)
    _insecureTLS = State(initialValue: server?.config.insecureTLS ?? false)
    _autoPrune = State(initialValue: server?.config.autoPrune ?? false)
    _statsMonitoring = State(initialValue: server?.config.statsMonitoring ?? true)
  }

  var body: some View {
    Form {
      Section("section.identity") { TextField("field.name", text: $name).disabled(server != nil); TextField("field.address", text: $address); TextField("field.externalAddress", text: $externalAddress); TextField("field.region", text: $region) }
      Section("section.behavior") { Toggle("field.enabled", isOn: $enabled); Toggle("field.statsMonitoring", isOn: $statsMonitoring); Toggle("field.autoPrune", isOn: $autoPrune); Toggle("field.insecureTLS", isOn: $insecureTLS) }
      if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
    }
    .navigationTitle(server == nil ? "title.newServer" : "title.editServer")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() }.disabled(isSaving) }
      ToolbarItem(placement: .confirmationAction) { Button("action.reviewChanges") { showingReview = true }.disabled(!canSave || isSaving) }
    }
    .confirmationDialog("confirm.saveChanges.title", isPresented: $showingReview, titleVisibility: .visible) {
      Button("action.save") { Task { await save() } }
      Button("action.cancel", role: .cancel) {}
    } message: { Text(String(format: String(localized: "confirm.saveChanges.fields"), changedFields.joined(separator: ", "))) }
    .overlay { if isSaving { ProgressView("status.saving").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty
      && (try? ServerAddress(address)) != nil
      && !changedFields.isEmpty
  }

  private var changedFields: [String] {
    guard let old = server?.config else {
      return ["field.name", "field.address", "field.externalAddress", "field.region", "section.behavior"].map { String(localized: String.LocalizationValue($0)) }
    }
    return [
      old.address == address ? nil : String(localized: "field.address"),
      old.externalAddress == externalAddress ? nil : String(localized: "field.externalAddress"),
      old.region == region ? nil : String(localized: "field.region"),
      old.enabled == enabled ? nil : String(localized: "field.enabled"),
      old.insecureTLS == insecureTLS ? nil : String(localized: "field.insecureTLS"),
      old.autoPrune == autoPrune ? nil : String(localized: "field.autoPrune"),
      old.statsMonitoring == statsMonitoring ? nil : String(localized: "field.statsMonitoring")
    ].compactMap { $0 }
  }

  private var patch: ServerConfigPatch {
    let old = server?.config
    return ServerConfigPatch(
      address: old?.address == address ? nil : address,
      externalAddress: old?.externalAddress == externalAddress ? nil : externalAddress,
      region: old?.region == region ? nil : region,
      enabled: old?.enabled == enabled ? nil : enabled,
      insecureTLS: old?.insecureTLS == insecureTLS ? nil : insecureTLS,
      autoPrune: old?.autoPrune == autoPrune ? nil : autoPrune,
      statsMonitoring: old?.statsMonitoring == statsMonitoring ? nil : statsMonitoring
    )
  }

  @MainActor private func save() async {
    guard !isSaving else { return }; isSaving = true; defer { isSaving = false }
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      let saved = if let server { try await client.updateServer(id: server.id, config: patch) }
        else { try await client.createServer(name: name, config: patch) }
      _ = try await client.getServer(idOrName: saved.id)
      onSaved()
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
  @State private var repository: String
  @State private var branch: String
  @State private var autoPull: Bool
  @State private var pollForUpdates: Bool
  @State private var autoUpdate: Bool
  @State private var showingReview = false
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(profile: ServerProfile, keychainStore: KeychainStore, stack: StackDetail? = nil, onSaved: @escaping () -> Void) {
    self.profile = profile; self.keychainStore = keychainStore; self.stack = stack; self.onSaved = onSaved
    _name = State(initialValue: stack?.name ?? ""); _serverID = State(initialValue: stack?.config.serverID ?? "")
    _projectName = State(initialValue: stack?.config.projectName ?? ""); _repository = State(initialValue: stack?.config.repository ?? "")
    _branch = State(initialValue: stack?.config.branch ?? "main"); _autoPull = State(initialValue: stack?.config.autoPull ?? false)
    _pollForUpdates = State(initialValue: stack?.config.pollForUpdates ?? false); _autoUpdate = State(initialValue: stack?.config.autoUpdate ?? false)
  }

  var body: some View {
    Form {
      Section("section.identity") { TextField("field.name", text: $name).disabled(stack != nil); TextField("field.serverID", text: $serverID); TextField("field.project", text: $projectName) }
      Section("section.repository") { TextField("field.repository", text: $repository); TextField("field.branch", text: $branch); Toggle("field.autoPull", isOn: $autoPull); Toggle("field.pollForUpdates", isOn: $pollForUpdates); Toggle("field.autoUpdate", isOn: $autoUpdate) }
      if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
    }
    .navigationTitle(stack == nil ? "title.newStack" : "title.editStack")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() }.disabled(isSaving) }
      ToolbarItem(placement: .confirmationAction) { Button("action.reviewChanges") { showingReview = true }.disabled(!canSave || isSaving) }
    }
    .confirmationDialog("confirm.saveChanges.title", isPresented: $showingReview, titleVisibility: .visible) {
      Button("action.save") { Task { await save() } }; Button("action.cancel", role: .cancel) {}
    } message: { Text(String(format: String(localized: "confirm.saveChanges.fields"), changedFields.joined(separator: ", "))) }
    .overlay { if isSaving { ProgressView("status.saving").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty
      && !serverID.trimmingCharacters(in: .whitespaces).isEmpty
      && !changedFields.isEmpty
  }

  private var changedFields: [String] {
    guard let old = stack?.config else {
      return ["field.name", "field.serverID", "field.project", "field.repository", "field.branch"].map { String(localized: String.LocalizationValue($0)) }
    }
    return [
      old.serverID == serverID ? nil : String(localized: "field.serverID"),
      old.projectName == projectName ? nil : String(localized: "field.project"),
      old.repository == repository ? nil : String(localized: "field.repository"),
      old.branch == branch ? nil : String(localized: "field.branch"),
      old.autoPull == autoPull ? nil : String(localized: "field.autoPull"),
      old.pollForUpdates == pollForUpdates ? nil : String(localized: "field.pollForUpdates"),
      old.autoUpdate == autoUpdate ? nil : String(localized: "field.autoUpdate")
    ].compactMap { $0 }
  }

  private var patch: StackConfigPatch {
    let old = stack?.config
    return StackConfigPatch(serverID: old?.serverID == serverID ? nil : serverID,
      projectName: old?.projectName == projectName ? nil : projectName, linkedRepo: nil,
      repository: old?.repository == repository ? nil : repository, branch: old?.branch == branch ? nil : branch,
      autoPull: old?.autoPull == autoPull ? nil : autoPull, pollForUpdates: old?.pollForUpdates == pollForUpdates ? nil : pollForUpdates,
      autoUpdate: old?.autoUpdate == autoUpdate ? nil : autoUpdate)
  }

  @MainActor private func save() async {
    guard !isSaving else { return }; isSaving = true; defer { isSaving = false }
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      let saved = if let stack { try await client.updateStack(id: stack.id, config: patch) }
        else { try await client.createStack(name: name, config: patch) }
      _ = try await client.getStack(idOrName: saved.id)
      onSaved()
    } catch { errorMessage = error.localizedDescription }
  }
}

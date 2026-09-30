import SwiftUI

private enum StackStateFilter: String, CaseIterable, Identifiable {
  case all
  case running
  case stopped
  case attention
  case other

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .all: "filter.allStates"
    case .running: "state.running"
    case .stopped: "state.stopped"
    case .attention: "filter.attention"
    case .other: "filter.otherStates"
    }
  }

  func includes(_ state: String) -> Bool {
    switch self {
    case .all: return true
    case .running: return ResourceStateCategory(state) == .running
    case .stopped: return ResourceStateCategory(state) == .stopped
    case .attention: return ResourceStateCategory(state) == .attention
    case .other:
      let category = ResourceStateCategory(state)
      return category == .other || category == .paused || category == .transitioning
    }
  }
}

struct StackListView: View {
  @EnvironmentObject private var liveUpdates: KomodoLiveUpdateController
  private enum LoadState: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  let profile: ServerProfile
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings

  @State private var stacks: [StackListItem] = []
  @State private var loadState = LoadState.loading
  @State private var searchText = ""
  @State private var stateFilter: StackStateFilter = .all
  @State private var selectedHost = ""
  @State private var selectedTags: Set<String> = []
  @State private var updatesOnly = false
  @State private var loadGeneration = 0
  @State private var showingCreate = false

  private let pageSize = 50

  var body: some View {
    Group {
      switch loadState {
      case .loading where stacks.isEmpty:
        ProgressView("status.loadingStacks")
      case .failed(let message) where stacks.isEmpty:
        ContentUnavailableView {
          Label("title.stacksUnavailable", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("action.retry") {
            Task { await loadStacks() }
          }
        }
      default:
        stackList
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("title.stacks")
    .searchable(text: $searchText, prompt: "title.stacks")
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Menu {
          Picker("filter.resourceState", selection: $stateFilter) {
            ForEach(StackStateFilter.allCases) { filter in
              Text(filter.title).tag(filter)
            }
          }
          if !availableHosts.isEmpty {
            Picker("filter.host", selection: $selectedHost) {
              Text("filter.allHosts").tag("")
              ForEach(availableHosts, id: \.self) { host in
                Text(host).tag(host)
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
            }
          }
          Toggle("filter.updatesAvailable", isOn: $updatesOnly)
          if hasActiveFilters {
            Button("filter.reset") { resetFilters() }
          }
        } label: {
          Label(
            "filter.stacks",
            systemImage: hasActiveFilters
              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
          )
        }
        Button("action.addStack", systemImage: "plus") {
          showingCreate = true
        }
        LiveConnectionStatusButton(
          profile: profile,
          keychainStore: keychainStore,
          appSettings: appSettings
        )
        #if os(macOS)
        Button("action.refresh", systemImage: "arrow.clockwise") {
          Task { await loadStacks() }
        }
        .disabled(loadState == .loading)
        .keyboardShortcut("r", modifiers: .command)
        #endif
      }
    }
    .sheet(isPresented: $showingCreate) {
      NavigationStack {
        StackEditorView(profile: profile, keychainStore: keychainStore) {
          showingCreate = false
          Task { await loadStacks() }
        }
      }
    }
    .task(id: profile.id) {
      stacks = []
      resetFilters()
      await loadStacks()
    }
    .onReceive(liveUpdates.$latestEvent.compactMap { $0 }) { event in
      if event.affects(.stack) || event.affects(.server) {
        Task { await loadStacks() }
      }
    }
    .onChange(of: liveUpdates.refreshGeneration) { _, _ in
      Task { await loadStacks() }
    }
  }

  private var stackList: some View {
    List {
      Section {
        if filteredStacks.isEmpty {
          if stacks.isEmpty {
            ContentUnavailableView(
              "message.noStacks",
              systemImage: "square.stack.3d.up",
              description: Text("message.noStacks.description")
            )
          } else if hasActiveFilters {
            ContentUnavailableView {
              Label("message.noStacksMatchFilters", systemImage: "line.3.horizontal.decrease.circle")
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
          ForEach(filteredStacks) { stack in
            NavigationLink {
              StackDetailView(
                summary: stack,
                profile: profile,
                keychainStore: keychainStore,
                appSettings: appSettings
              )
              .environmentObject(liveUpdates)
            } label: {
              StackRow(stack: stack)
            }
            .accessibilityIdentifier("stack-list-item-\(stack.id)")
          }
        }
        if case .failed(let message) = loadState {
          Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        }
      } header: {
        ResourceStatusSummary(
          counts: overviewCounts,
          isStale: hasRefreshError,
          showTotal: { selectOverviewFilter(.all) },
          showActive: { selectOverviewFilter(.running) },
          showProblems: { selectOverviewFilter(.attention) }
        )
        .textCase(nil)
      }
    }
    .refreshable {
      await loadStacks()
    }
  }

  private var filteredStacks: [StackListItem] {
    stacks.filter { stack in
      stateFilter.includes(stack.info.state)
        && (selectedHost.isEmpty || hostName(for: stack) == selectedHost)
        && selectedTags.isSubset(of: Set(stack.tags))
        && (!updatesOnly || stack.info.services.contains { $0.updateAvailable })
        && (searchText.isEmpty
          || stack.name.localizedCaseInsensitiveContains(searchText)
          || stack.info.serverName.localizedCaseInsensitiveContains(searchText)
          || stack.info.swarmName.localizedCaseInsensitiveContains(searchText))
    }
  }

  private var overviewCounts: ResourceOverviewCounts {
    ResourceOverviewCounts(states: stacks.map(\.info.state))
  }

  private var hasRefreshError: Bool {
    if case .failed = loadState { return true }
    return false
  }

  private func selectOverviewFilter(_ filter: StackStateFilter) {
    searchText = ""
    resetFilters()
    stateFilter = filter
  }

  private var availableHosts: [String] {
    Set(stacks.map(hostName(for:)).filter { !$0.isEmpty })
      .union(selectedHost.isEmpty ? [] : [selectedHost])
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  private var availableTags: [String] {
    Set(stacks.flatMap(\.tags))
      .union(selectedTags)
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  private var hasActiveFilters: Bool {
    stateFilter != .all || !selectedHost.isEmpty || !selectedTags.isEmpty || updatesOnly
  }

  private var emptyResetTitle: LocalizedStringKey {
    searchText.isEmpty ? "filter.reset" : "filter.resetAll"
  }

  private func hostName(for stack: StackListItem) -> String {
    stack.info.swarmName.isEmpty ? stack.info.serverName : stack.info.swarmName
  }

  private func resetFilters() {
    stateFilter = .all
    selectedHost = ""
    selectedTags.removeAll()
    updatesOnly = false
  }

  @MainActor
  private func loadStacks() async {
    loadGeneration += 1
    let generation = loadGeneration
    loadState = .loading
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      var loadedStacks: [StackListItem] = []
      var knownIDs = Set<String>()
      var page = 0
      while true {
        guard generation == loadGeneration else { return }
        let batch = try await client.listStacks(page: page, limit: pageSize)
        try Task.checkCancellation()
        guard generation == loadGeneration else { return }
        for stack in batch where knownIDs.insert(stack.id).inserted {
          loadedStacks.append(stack)
        }
        if batch.count < pageSize { break }
        page += 1
      }
      guard generation == loadGeneration else { return }
      stacks = loadedStacks
      loadState = .loaded
    } catch is CancellationError {
      return
    } catch {
      guard generation == loadGeneration else { return }
      loadState = .failed(
        (error as? LocalizedError)?.errorDescription ?? String(localized: "error.stacks.loadFailed")
      )
    }
  }
}

private struct StackRow: View {
  let stack: StackListItem

  var body: some View {
    ResourceListRow(
      title: stack.name,
      subtitle: detail,
      status: localizedState,
      symbol: resourceStateSymbol(stack.info.state),
      symbolColor: resourceStateColor(stack.info.state)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(stack.name))
    .accessibilityValue(Text("\(detail), \(localizedState)"))
  }

  private var detail: String {
    let host = stack.info.swarmName.isEmpty ? stack.info.serverName : stack.info.swarmName
    if !host.isEmpty {
      return host
    }
    return String(format: String(localized: "stack.serviceCount"), stack.info.services.count)
  }

  private var localizedState: String {
    localizedResourceState(stack.info.state)
  }
}

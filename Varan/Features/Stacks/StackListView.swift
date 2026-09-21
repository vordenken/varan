import SwiftUI

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
  @State private var nextPage = 0
  @State private var canLoadMore = true
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
        Button("action.addStack", systemImage: "plus") {
          showingCreate = true
        }
        LiveConnectionStatusButton(
          profile: profile,
          keychainStore: keychainStore,
          appSettings: appSettings
        )
        Button("action.refresh", systemImage: "arrow.clockwise") {
          Task { await loadStacks(reset: true) }
        }
        .disabled(loadState == .loading)
      }
    }
    .sheet(isPresented: $showingCreate) {
      NavigationStack {
        StackEditorView(profile: profile, keychainStore: keychainStore) {
          showingCreate = false
          Task { await loadStacks(reset: true) }
        }
      }
    }
    .task(id: profile.id) {
      await loadStacks(reset: true)
    }
    .onReceive(liveUpdates.$latestEvent.compactMap { $0 }) { event in
      if event.affects(.stack) || event.affects(.server) {
        Task { await loadStacks(reset: true) }
      }
    }
    .onChange(of: liveUpdates.refreshGeneration) { _, _ in
      Task { await loadStacks(reset: true) }
    }
  }

  private var stackList: some View {
    List {
      if filteredStacks.isEmpty {
        if searchText.isEmpty {
          ContentUnavailableView(
            "message.noStacks",
            systemImage: "square.stack.3d.up",
            description: Text("message.noStacks.description")
          )
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
        }

        if searchText.isEmpty, canLoadMore {
          Button("action.loadMore", systemImage: "arrow.down.circle") {
            Task { await loadStacks(reset: false) }
          }
          .disabled(loadState == .loading)
        }

        if case .failed(let message) = loadState {
          Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        }
      }
    }
    .refreshable {
      await loadStacks(reset: true)
    }
  }

  private var filteredStacks: [StackListItem] {
    guard !searchText.isEmpty else { return stacks }
    return stacks.filter {
      $0.name.localizedCaseInsensitiveContains(searchText)
        || $0.info.serverName.localizedCaseInsensitiveContains(searchText)
        || $0.info.swarmName.localizedCaseInsensitiveContains(searchText)
    }
  }

  @MainActor
  private func loadStacks(reset: Bool = true) async {
    loadState = .loading
    do {
      let client = try await makeKomodoClient(profile: profile, keychainStore: keychainStore)
      let page = reset ? 0 : nextPage
      let loadedStacks = try await client.listStacks(page: page, limit: pageSize)
      if reset {
        stacks = loadedStacks
      } else {
        let existingIDs = Set(stacks.map(\.id))
        stacks.append(contentsOf: loadedStacks.filter { !existingIDs.contains($0.id) })
      }
      nextPage = page + 1
      canLoadMore = loadedStacks.count == pageSize
      loadState = .loaded
    } catch is CancellationError {
      return
    } catch {
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

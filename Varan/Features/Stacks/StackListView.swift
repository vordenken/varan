import SwiftUI

struct StackListView: View {
  private enum LoadState: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  let profile: ServerProfile
  let keychainStore: KeychainStore

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
      ToolbarItem {
        Button("action.refresh", systemImage: "arrow.clockwise") {
          Task { await loadStacks(reset: true) }
        }
        .disabled(loadState == .loading)
      }
      ToolbarItem {
        Button("action.addStack", systemImage: "plus") {
          showingCreate = true
        }
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
              keychainStore: keychainStore
            )
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
      guard let credentials = try await keychainStore.credentials(
        for: profile.credentialAccount
      ), credentials.authenticationKind == profile.authenticationKind else {
        throw KeychainStoreError.invalidCredentialData
      }
      let client = KomodoAPIClient(
        address: try profile.address,
        authentication: credentials.authentication
      )
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
    HStack(spacing: 12) {
      Image(systemName: stateSymbol)
        .foregroundStyle(stateColor)
        .frame(width: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(stack.name)
          .font(.headline)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Text(localizedState)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
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
    switch stack.info.state {
    case "running": String(localized: "state.running")
    case "paused": String(localized: "state.paused")
    case "stopped": String(localized: "state.stopped")
    case "created": String(localized: "state.created")
    case "restarting": String(localized: "state.restarting")
    case "deploying": String(localized: "state.unknown")
    case "unhealthy": String(localized: "state.unhealthy")
    case "down": String(localized: "state.down")
    default: String(localized: "state.unknown")
    }
  }

  private var stateSymbol: String {
    switch stack.info.state {
    case "running": "checkmark.circle.fill"
    case "paused", "stopped", "created": "pause.circle.fill"
    case "deploying", "restarting": "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
    case "unhealthy", "dead": "exclamationmark.triangle.fill"
    case "down": "minus.circle.fill"
    default: "questionmark.circle.fill"
    }
  }

  private var stateColor: Color {
    switch stack.info.state {
    case "running": .green
    case "unhealthy", "dead": .red
    case "deploying", "restarting": .blue
    default: .secondary
    }
  }
}

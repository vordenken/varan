import SwiftData
import SwiftUI

struct AppShellView: View {
  private struct ProfileEditorPresentation: Identifiable {
    let profile: ServerProfile
    let credentials: StoredCredentials

    var id: UUID { profile.id }
  }

  @Environment(\.modelContext) private var modelContext
  @Query(sort: \ServerProfile.name) private var profiles: [ServerProfile]
  @State private var selectedProfileID: UUID?
  @State private var selectedProfileRevision = 0
  @State private var isCompletingOnboarding = false
  @State private var showingAddConnection = false
  @State private var profileEditorPresentation: ProfileEditorPresentation?
  @State private var errorTitle = String(localized: "alert.deleteConnection.failed")
  @State private var errorMessage: String?

  private let keychainStore: KeychainStore
  @ObservedObject private var appSettings: AppSettings

  init(
    keychainStore: KeychainStore = .shared,
    appSettings: AppSettings = AppSettings()
  ) {
    self.keychainStore = keychainStore
    self.appSettings = appSettings
  }

  var body: some View {
    Group {
      if profiles.isEmpty || isCompletingOnboarding {
        OnboardingView(
          keychainStore: keychainStore,
          onProfileSaved: { profile in
            selectedProfileID = profile.id
            isCompletingOnboarding = true
          },
          onFinished: { profile in
            selectedProfileID = profile.id
            isCompletingOnboarding = false
          }
        )
      } else {
#if os(iOS)
        MobileAppShellView(
          profiles: profiles,
          selectedProfileID: $selectedProfileID,
          keychainStore: keychainStore,
          appSettings: appSettings
        )
#else
        NavigationSplitView {
          List(selection: $selectedProfileID) {
            Section("section.connections") {
              ForEach(profiles) { profile in
                NavigationLink(value: profile.id) {
                  Label {
                    VStack(alignment: .leading, spacing: 2) {
                      Text(profile.name)
                      Text(profile.baseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                  } icon: {
                    Image(systemName: "server.rack")
                      .accessibilityHidden(true)
                  }
                }
                .accessibilityLabel(Text(profile.name))
                .accessibilityValue(Text(profile.baseURL))
                .contextMenu {
                  Button("action.editConnection", systemImage: "pencil") {
                    prepareEditor(for: profile)
                  }
                  Button("action.deleteConnection", systemImage: "trash", role: .destructive) {
                    deleteProfiles([profile])
                  }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                  Button("action.delete", systemImage: "trash", role: .destructive) {
                    deleteProfiles([profile])
                  }
                  Button("action.edit", systemImage: "pencil") {
                    prepareEditor(for: profile)
                  }
                  .tint(.blue)
                }
              }
              .onDelete(perform: deleteProfiles)
            }
          }
          .navigationTitle("Varan")
          .toolbar {
            ToolbarItemGroup {
              Button("action.addConnection", systemImage: "plus") {
                showingAddConnection = true
              }
              SettingsLink {
                Label("settings.title", systemImage: "gearshape")
              }
            }
          }
        } detail: {
          NavigationStack {
            if let selectedProfile {
              ResourceBrowserView(
                profile: selectedProfile,
                keychainStore: keychainStore,
                appSettings: appSettings
              )
            } else {
              ContentUnavailableView(
                "message.selectConnection",
                systemImage: "server.rack",
                description: Text("message.selectConnection.description")
              )
            }
          }
          .id("\(selectedProfileID?.uuidString ?? "none")-\(selectedProfileRevision)")
        }
        .task {
          if selectedProfileID == nil {
            selectedProfileID = profiles.first?.id
          }
        }
#endif
      }
    }
    .sheet(isPresented: $showingAddConnection) {
      NavigationStack {
        ConnectionEditorView(keychainStore: keychainStore) { profile in
          selectedProfileID = profile.id
          showingAddConnection = false
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("action.cancel") {
              showingAddConnection = false
            }
          }
        }
      }
    }
    .sheet(item: $profileEditorPresentation) { presentation in
      NavigationStack {
        ConnectionEditorView(
          profile: presentation.profile,
          storedCredentials: presentation.credentials,
          keychainStore: keychainStore
        ) { savedProfile in
          selectedProfileID = savedProfile.id
          selectedProfileRevision += 1
          profileEditorPresentation = nil
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("action.cancel") {
              profileEditorPresentation = nil
            }
          }
        }
      }
    }
    .alert(errorTitle, isPresented: showsError) {
      Button("OK") { errorMessage = nil }
    } message: {
      Text(errorMessage ?? String(localized: "error.unknown"))
    }
  }

  private var selectedProfile: ServerProfile? {
    profiles.first { $0.id == selectedProfileID }
  }

  private var showsError: Binding<Bool> {
    Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )
  }

  private func deleteProfiles(at offsets: IndexSet) {
    let profilesToDelete = offsets.map { profiles[$0] }
    deleteProfiles(profilesToDelete)
  }

  private func deleteProfiles(_ profilesToDelete: [ServerProfile]) {
    Task { @MainActor in
      do {
        for profile in profilesToDelete {
          try await keychainStore.deleteSecret(for: profile.credentialAccount)
          modelContext.delete(profile)
        }
        try modelContext.save()
        if profilesToDelete.contains(where: { $0.id == selectedProfileID }) {
          selectedProfileID = nil
        }
      } catch {
        errorTitle = String(localized: "alert.deleteConnection.failed")
        errorMessage = error.localizedDescription
      }
    }
  }

  private func prepareEditor(for profile: ServerProfile) {
    Task { @MainActor in
      do {
        guard let credentials = try await keychainStore.credentials(
          for: profile.credentialAccount
        ) else {
          throw KeychainStoreError.invalidCredentialData
        }
        profileEditorPresentation = ProfileEditorPresentation(
          profile: profile,
          credentials: credentials
        )
      } catch {
        errorTitle = String(localized: "alert.editConnection.failed")
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct OnboardingView: View {
  private enum Stage {
    case welcome
    case connection
    case success
  }

  let keychainStore: KeychainStore
  let onProfileSaved: (ServerProfile) -> Void
  let onFinished: (ServerProfile) -> Void

  @State private var stage = Stage.welcome
  @State private var mostRecentProfile: ServerProfile?

  var body: some View {
    NavigationStack {
      switch stage {
      case .welcome:
        welcome
      case .connection:
        ConnectionEditorView(keychainStore: keychainStore) { profile in
          mostRecentProfile = profile
          onProfileSaved(profile)
          stage = .success
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("action.back", systemImage: "chevron.backward") {
              stage = mostRecentProfile == nil ? .welcome : .success
            }
          }
        }
      case .success:
        success
      }
    }
  }

  private var welcome: some View {
    VStack(spacing: 28) {
      Image("VaranAppIcon")
        .resizable()
        .interpolation(.high)
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        .accessibilityHidden(true)
      VStack(spacing: 10) {
        Text(verbatim: "Varan")
          .font(.title.bold())
          .tracking(1.6)
          .foregroundStyle(.tint)
          .accessibilityAddTraits(.isHeader)
        Text("onboarding.welcome.title")
          .font(.largeTitle.bold())
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
        Text("onboarding.welcome.description")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
      VStack(alignment: .leading, spacing: 16) {
        OnboardingBenefit(icon: "square.stack.3d.up", title: "onboarding.benefit.resources")
        OnboardingBenefit(icon: "chart.xyaxis.line", title: "onboarding.benefit.insights")
        OnboardingBenefit(icon: "rectangle.stack.badge.plus", title: "onboarding.benefit.multiple")
      }
      .frame(maxWidth: 440, alignment: .leading)

      Spacer(minLength: 16)

      Button("onboarding.action.setupFirstInstance") {
        stage = .connection
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .frame(maxWidth: 440)
    }
    .padding(.horizontal, 28)
    .padding(.top, 36)
    .padding(.bottom, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(iOS)
    .toolbar(.hidden, for: .navigationBar)
#endif
  }

  private var success: some View {
    VStack(spacing: 22) {
      Spacer()
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 68))
        .foregroundStyle(.green)
        .accessibilityHidden(true)
      Text("onboarding.success.title")
        .font(.largeTitle.bold())
      if let mostRecentProfile {
        Text(mostRecentProfile.name)
          .font(.title2)
        Text(mostRecentProfile.baseURL)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      Spacer()
      if let mostRecentProfile {
        Button("onboarding.action.openVaran") {
          onFinished(mostRecentProfile)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
      Button("onboarding.action.addAnotherInstance", systemImage: "plus") {
        stage = .connection
      }
      .buttonStyle(.borderless)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("onboarding.success.navigationTitle")
  }
}

private struct OnboardingBenefit: View {
  let icon: String
  let title: LocalizedStringKey

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.tint)
        .frame(width: 42, height: 42)
        .background(.tint.opacity(0.12), in: Circle())
        .accessibilityHidden(true)
      Text(title)
        .font(.headline)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }
}

#if os(iOS)
private enum AppTab: Hashable {
  case servers
  case stacks
  case containers
  case settings

  init(defaultSection: DefaultResourceSection) {
    switch defaultSection {
    case .servers: self = .servers
    case .stacks: self = .stacks
    case .containers: self = .containers
    }
  }
}

private struct MobileAppShellView: View {
  @Environment(\.scenePhase) private var scenePhase
  let profiles: [ServerProfile]
  @Binding var selectedProfileID: UUID?
  let keychainStore: KeychainStore
  @ObservedObject var appSettings: AppSettings

  @StateObject private var liveUpdates = KomodoLiveUpdateController()
  @State private var selectedTab: AppTab

  init(
    profiles: [ServerProfile],
    selectedProfileID: Binding<UUID?>,
    keychainStore: KeychainStore,
    appSettings: AppSettings
  ) {
    self.profiles = profiles
    _selectedProfileID = selectedProfileID
    self.keychainStore = keychainStore
    self.appSettings = appSettings
    _selectedTab = State(
      initialValue: profiles.isEmpty ? .settings : AppTab(defaultSection: appSettings.defaultResourceSection)
    )
  }

  var body: some View {
    adaptiveTabView
      .environmentObject(liveUpdates)
      .task {
        if selectedProfileID == nil {
          selectedProfileID = profiles.first?.id
        }
      }
      .task(id: selectedProfile?.id) {
        guard scenePhase == .active else { return }
        await connectLiveUpdates()
      }
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
      .onChange(of: profiles.map(\.id)) { _, profileIDs in
        if profileIDs.isEmpty {
          selectedProfileID = nil
          selectedTab = .settings
        } else if let selectedProfileID, profileIDs.contains(selectedProfileID) {
          return
        } else {
          selectedProfileID = profileIDs.first
        }
      }
      .onDisappear { liveUpdates.stop() }
  }

  @ViewBuilder
  private var adaptiveTabView: some View {
    if #available(iOS 26.0, *) {
      tabs
        .tabBarMinimizeBehavior(.onScrollDown)
    } else {
      tabs
    }
  }

  private var tabs: some View {
    TabView(selection: $selectedTab) {
      Tab("title.servers", systemImage: "server.rack", value: AppTab.servers) {
        NavigationStack {
          resourceContent(.servers)
        }
        .id(selectedProfileID)
      }

      Tab("title.stacks", systemImage: "square.stack.3d.up.fill", value: AppTab.stacks) {
        NavigationStack {
          resourceContent(.stacks)
        }
        .id(selectedProfileID)
      }

      Tab("title.containers", systemImage: "shippingbox.fill", value: AppTab.containers) {
        NavigationStack {
          resourceContent(.containers)
        }
        .id(selectedProfileID)
      }

      Tab("settings.title", systemImage: "gearshape.fill", value: AppTab.settings) {
        NavigationStack {
          SettingsView(
            settings: appSettings,
            keychainStore: keychainStore,
            selectedProfileID: $selectedProfileID
          )
        }
      }
    }
  }

  @ViewBuilder
  private func resourceContent(_ section: ResourceSection) -> some View {
    if let profile = selectedProfile {
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
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          connectionMenu
        }
      }
    } else {
      ContentUnavailableView {
        Label("message.selectConnection", systemImage: "server.rack")
      } description: {
        Text("message.selectConnection.description")
      } actions: {
        Button("settings.title", systemImage: "gearshape") {
          selectedTab = .settings
        }
      }
    }
  }

  private var connectionMenu: some View {
    Menu {
      ForEach(profiles) { profile in
        Button {
          selectedProfileID = profile.id
        } label: {
          if profile.id == selectedProfileID {
            Label(profile.name, systemImage: "checkmark")
          } else {
            Text(profile.name)
          }
        }
      }
      Divider()
      Button("settings.title", systemImage: "gearshape") {
        selectedTab = .settings
      }
    } label: {
      Label(selectedProfile?.name ?? String(localized: "message.selectConnection"), systemImage: "server.rack")
        .lineLimit(1)
    }
    .accessibilityLabel("settings.connection.active")
    .accessibilityValue(Text(selectedProfile?.name ?? String(localized: "message.selectConnection")))
  }

  private var selectedProfile: ServerProfile? {
    profiles.first { $0.id == selectedProfileID }
  }

  @MainActor
  private func connectLiveUpdates() async {
    guard appSettings.liveUpdatesEnabled, let selectedProfile else {
      liveUpdates.stop()
      return
    }
    do {
      guard let credentials = try await keychainStore.credentials(
        for: selectedProfile.credentialAccount
      ), credentials.authenticationKind == selectedProfile.authenticationKind else {
        throw KeychainStoreError.invalidCredentialData
      }
      liveUpdates.start(
        address: try selectedProfile.address,
        authentication: credentials.authentication
      )
    } catch {
      liveUpdates.stop()
    }
  }
}
#endif

#Preview {
  AppShellView(appSettings: AppSettings())
    .modelContainer(for: ServerProfile.self, inMemory: true)
}

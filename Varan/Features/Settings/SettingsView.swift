import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \ServerProfile.name) private var profiles: [ServerProfile]
  @ObservedObject var settings: AppSettings
  let keychainStore: KeychainStore
  private let selectedProfileID: Binding<UUID?>?

  @State private var confirmsReset = false
  @State private var showingAddConnection = false
  @State private var editingProfile: ServerProfile?
  @State private var profileToDelete: ServerProfile?
  @State private var errorMessage: String?

  init(
    settings: AppSettings,
    keychainStore: KeychainStore = .shared,
    selectedProfileID: Binding<UUID?>? = nil
  ) {
    self.settings = settings
    self.keychainStore = keychainStore
    self.selectedProfileID = selectedProfileID
  }

  var body: some View {
    Form {
      Section {
        if profiles.isEmpty {
          Text("settings.connections.empty")
            .foregroundStyle(.secondary)
        } else {
          ForEach(profiles) { profile in
            HStack(spacing: 12) {
              Button {
                if selectedProfileID != nil {
                  selectedProfileID?.wrappedValue = profile.id
                } else {
                  editingProfile = profile
                }
              } label: {
                HStack(spacing: 12) {
                  Image(systemName: "server.rack")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                      .foregroundStyle(.primary)
                    Text(profile.baseURL)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                }
                .contentShape(.rect)
              }
              .buttonStyle(.plain)

              Spacer()
              if selectedProfileID?.wrappedValue == profile.id {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
                  .accessibilityLabel("settings.connection.active")
              }
              Button("action.editConnection", systemImage: "pencil") {
                editingProfile = profile
              }
              .labelStyle(.iconOnly)
            }
            .contextMenu {
              Button("action.editConnection", systemImage: "pencil") {
                editingProfile = profile
              }
              Button("action.deleteConnection", systemImage: "trash", role: .destructive) {
                profileToDelete = profile
              }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button("action.delete", systemImage: "trash", role: .destructive) {
                profileToDelete = profile
              }
            }
          }
        }

        Button("action.addConnection", systemImage: "plus") {
          showingAddConnection = true
        }
      } header: {
        Text("settings.section.instances")
      } footer: {
        Text("settings.connections.description")
      }

      Section("settings.section.general") {
        Picker("settings.defaultResourceSection", selection: $settings.defaultResourceSection) {
          ForEach(DefaultResourceSection.allCases) { section in
            Text(section.title).tag(section)
          }
        }
      }

      Section("settings.section.liveUpdates") {
        Toggle("settings.liveUpdatesEnabled", isOn: $settings.liveUpdatesEnabled)
        Text("settings.liveUpdates.description")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("settings.section.metrics") {
        Toggle("metrics.autoRefresh", isOn: $settings.metricsAutoRefresh)
        Picker("metrics.refreshInterval", selection: $settings.metricsRefreshInterval) {
          ForEach(MetricsRefreshInterval.allCases) { interval in
            Text(interval.title).tag(interval)
          }
        }
        .disabled(!settings.metricsAutoRefresh)
      }

      Section("settings.section.logs") {
        Toggle("log.autoRefresh", isOn: $settings.logsAutoRefresh)
        Picker("settings.logRefreshInterval", selection: $settings.logRefreshInterval) {
          ForEach(LogRefreshInterval.allCases) { interval in
            Text(interval.title).tag(interval)
          }
        }
        .disabled(!settings.logsAutoRefresh)
        Toggle("log.followLatest", isOn: $settings.logsFollowLatest)
      }

      Section {
        Button("settings.reset", role: .destructive) {
          confirmsReset = true
        }
      } footer: {
        Text("settings.reset.description")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("settings.title")
    .sheet(isPresented: $showingAddConnection) {
      NavigationStack {
        ConnectionEditorView(keychainStore: keychainStore) { profile in
          selectedProfileID?.wrappedValue = profile.id
          showingAddConnection = false
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("action.cancel") { showingAddConnection = false }
          }
        }
      }
    }
    .sheet(item: $editingProfile) { profile in
      NavigationStack {
        ConnectionEditorView(profile: profile, keychainStore: keychainStore) { savedProfile in
          selectedProfileID?.wrappedValue = savedProfile.id
          editingProfile = nil
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("action.cancel") { editingProfile = nil }
          }
        }
      }
    }
    .confirmationDialog(
      "settings.deleteConnection.confirm.title",
      isPresented: confirmsConnectionDeletion,
      titleVisibility: .visible,
      presenting: profileToDelete
    ) { profile in
      Button("action.deleteConnection", role: .destructive) {
        deleteProfile(profile)
      }
      Button("action.cancel", role: .cancel) {}
    } message: { profile in
      Text(String(
        format: String(localized: "settings.deleteConnection.confirm.message"),
        profile.name
      ))
    }
    .confirmationDialog(
      "settings.reset.confirm.title",
      isPresented: $confirmsReset,
      titleVisibility: .visible
    ) {
      Button("settings.reset", role: .destructive) { settings.reset() }
      Button("action.cancel", role: .cancel) {}
    } message: {
      Text("settings.reset.confirm.message")
    }
    .alert("alert.deleteConnection.failed", isPresented: showsError) {
      Button("action.ok") { errorMessage = nil }
    } message: {
      Text(errorMessage ?? String(localized: "error.unknown"))
    }
  }

  private var confirmsConnectionDeletion: Binding<Bool> {
    Binding(
      get: { profileToDelete != nil },
      set: { if !$0 { profileToDelete = nil } }
    )
  }

  private var showsError: Binding<Bool> {
    Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )
  }

  private func deleteProfile(_ profile: ServerProfile) {
    Task { @MainActor in
      do {
        try await keychainStore.deleteSecret(for: profile.credentialAccount)
        modelContext.delete(profile)
        try modelContext.save()
        if selectedProfileID?.wrappedValue == profile.id {
          selectedProfileID?.wrappedValue = profiles.first { $0.id != profile.id }?.id
        }
        profileToDelete = nil
      } catch {
        profileToDelete = nil
        errorMessage = error.localizedDescription
      }
    }
  }
}

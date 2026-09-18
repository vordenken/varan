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
  @State private var showingAddConnection = false
  @State private var profileEditorPresentation: ProfileEditorPresentation?
  @State private var errorTitle = String(localized: "alert.deleteConnection.failed")
  @State private var errorMessage: String?

  private let keychainStore: KeychainStore

  init(keychainStore: KeychainStore = .shared) {
    self.keychainStore = keychainStore
  }

  var body: some View {
    Group {
      if profiles.isEmpty {
        NavigationStack {
          ConnectionEditorView(keychainStore: keychainStore) { profile in
            selectedProfileID = profile.id
          }
        }
      } else {
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
                  }
                }
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
#if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
#endif
          .toolbar {
            ToolbarItem {
              Button("action.addConnection", systemImage: "plus") {
                showingAddConnection = true
              }
            }
          }
        } detail: {
          NavigationStack {
            if let selectedProfile {
              StackListView(profile: selectedProfile, keychainStore: keychainStore)
            } else {
              ContentUnavailableView(
                "message.selectConnection",
                systemImage: "server.rack",
                description: Text("message.selectConnection.description")
              )
            }
          }
          .id(selectedProfileID)
        }
        .task {
          if selectedProfileID == nil {
            selectedProfileID = profiles.first?.id
          }
        }
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

#Preview {
  AppShellView()
    .modelContainer(for: ServerProfile.self, inMemory: true)
}
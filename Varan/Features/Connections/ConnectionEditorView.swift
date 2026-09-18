import SwiftData
import SwiftUI

struct ConnectionEditorView: View {
  private enum AuthenticationMode: CaseIterable, Identifiable {
    case apiKey
    case token

    var id: Self { self }

    var title: LocalizedStringKey {
      switch self {
      case .apiKey: "auth.apiKey"
      case .token: "auth.token"
      }
    }
  }

  private enum ConnectionState: Equatable {
    case idle
    case testing
    case connected
    case failed(String)
  }

  @State private var serverURL = ""
  @State private var profileName = ""
  @State private var authenticationMode = AuthenticationMode.apiKey
  @State private var key = ""
  @State private var secret = ""
  @State private var token = ""
  @State private var connectionState = ConnectionState.idle
  @State private var isLoadingCredentials: Bool

  @Environment(\.modelContext) private var modelContext
  private let profile: ServerProfile?
  private let storedCredentials: StoredCredentials?
  private let keychainStore: KeychainStore
  private let onSaved: (ServerProfile) -> Void

  init(
    profile: ServerProfile? = nil,
    storedCredentials: StoredCredentials? = nil,
    keychainStore: KeychainStore = .shared,
    onSaved: @escaping (ServerProfile) -> Void = { _ in }
  ) {
    self.profile = profile
    self.storedCredentials = storedCredentials
    self.keychainStore = keychainStore
    self.onSaved = onSaved
    _serverURL = State(initialValue: profile?.baseURL ?? "")
    _profileName = State(initialValue: profile?.name ?? "")
    _authenticationMode = State(
      initialValue: storedCredentials?.authenticationKind == .bearerToken
        || profile?.authenticationKind == .bearerToken ? .token : .apiKey
    )
    _key = State(initialValue: storedCredentials?.apiKey ?? "")
    _secret = State(
      initialValue: storedCredentials?.authenticationKind == .apiKey
        ? storedCredentials?.secret ?? "" : ""
    )
    _token = State(
      initialValue: storedCredentials?.authenticationKind == .bearerToken
        ? storedCredentials?.secret ?? "" : ""
    )
    _isLoadingCredentials = State(initialValue: profile != nil && storedCredentials == nil)
  }

  var body: some View {
    Form {
      Section("section.server") {
        TextField("field.name", text: $profileName, prompt: Text("placeholder.profileName"))
          .textContentType(.name)
        TextField(
          "field.serverAddress",
          text: $serverURL,
          prompt: Text("https://komodo.example.com").foregroundStyle(.secondary)
        )
          #if os(iOS)
          .textContentType(.URL)
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
          #endif
      }

      Section("section.authentication") {
        Picker("field.authenticationMethod", selection: $authenticationMode) {
          ForEach(AuthenticationMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)

        if authenticationMode == .apiKey {
          TextField("API-Key", text: $key)
            .textContentType(.username)
          SecureField("API-Secret", text: $secret)
            .textContentType(.password)
        } else {
          SecureField("JWT", text: $token)
            .textContentType(.password)
        }
      }

      Section {
        Button {
          Task { await testConnection() }
        } label: {
          if connectionState == .testing || isLoadingCredentials {
            ProgressView()
              .controlSize(.small)
          } else {
            Label(saveButtonTitle, systemImage: "checkmark.shield")
          }
        }
        .disabled(!canTestConnection || connectionState == .testing || isLoadingCredentials)
      } footer: {
        statusView
      }
    }
    .formStyle(.grouped)
    .navigationTitle(profile == nil ? "title.newConnection" : "title.editConnection")
    .frame(minWidth: 340, idealWidth: 520, minHeight: 420)
    .task(id: profile?.id) {
      await loadStoredCredentials()
    }
  }

  @ViewBuilder
  private var statusView: some View {
    switch connectionState {
    case .idle, .testing:
      EmptyView()
    case .connected:
      Label("status.connectionSuccessful", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    }
  }

  private var canTestConnection: Bool {
    guard !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    switch authenticationMode {
    case .apiKey:
      return !key.isEmpty && !secret.isEmpty
    case .token:
      return !token.isEmpty
    }
  }

  private var saveButtonTitle: LocalizedStringKey {
    profile == nil ? "action.testAndSave" : "action.testAndUpdate"
  }

  @MainActor
  private func loadStoredCredentials() async {
    guard let profile, storedCredentials == nil else { return }
    defer { isLoadingCredentials = false }
    do {
      guard let credentials = try await keychainStore.credentials(
        for: profile.credentialAccount
      ) else {
        connectionState = .failed(String(localized: "error.credentials.notFound"))
        return
      }
      switch credentials.authenticationKind {
      case .apiKey:
        authenticationMode = .apiKey
        key = credentials.apiKey ?? ""
        secret = credentials.secret
      case .bearerToken:
        authenticationMode = .token
        token = credentials.secret
      }
    } catch {
      connectionState = .failed(
        (error as? LocalizedError)?.errorDescription
          ?? String(localized: "error.credentials.loadFailed")
      )
    }
  }

  @MainActor
  private func testConnection() async {
    connectionState = .testing
    do {
      let address = try ServerAddress(serverURL)
      let credentials: StoredCredentials = switch authenticationMode {
      case .apiKey:
        .apiKey(key, secret: secret)
      case .token:
        .bearerToken(token)
      }
      let client = KomodoAPIClient(address: address, authentication: credentials.authentication)
      try await client.testConnection()
      let profile = try await saveProfile(address: address, credentials: credentials)
      connectionState = .connected
      onSaved(profile)
    } catch {
      connectionState = .failed(
        (error as? LocalizedError)?.errorDescription ?? String(localized: "error.connection.failed")
      )
    }
  }

  @MainActor
  private func saveProfile(
    address: ServerAddress,
    credentials: StoredCredentials
  ) async throws -> ServerProfile {
    let normalizedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let profile else {
      let newProfile = ServerProfile(
        name: normalizedName,
        address: address,
        authenticationKind: credentials.authenticationKind
      )
      try await keychainStore.save(credentials, for: newProfile.credentialAccount)
      do {
        modelContext.insert(newProfile)
        try modelContext.save()
        return newProfile
      } catch {
        modelContext.delete(newProfile)
        try? await keychainStore.deleteSecret(for: newProfile.credentialAccount)
        throw error
      }
    }

    let previousName = profile.name
    let previousAddress = try profile.address
    let previousAuthenticationKind = profile.authenticationKind
    let previousCredentials = try await keychainStore.credentials(for: profile.credentialAccount)

    try await keychainStore.save(credentials, for: profile.credentialAccount)
    profile.update(
      name: normalizedName,
      address: address,
      authenticationKind: credentials.authenticationKind
    )
    do {
      try modelContext.save()
      return profile
    } catch {
      profile.update(
        name: previousName,
        address: previousAddress,
        authenticationKind: previousAuthenticationKind
      )
      if let previousCredentials {
        try? await keychainStore.save(previousCredentials, for: profile.credentialAccount)
      } else {
        try? await keychainStore.deleteSecret(for: profile.credentialAccount)
      }
      throw error
    }
  }
}

#Preview {
  NavigationStack {
    ConnectionEditorView()
  }
  .modelContainer(for: ServerProfile.self, inMemory: true)
}
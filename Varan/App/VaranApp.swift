import SwiftUI
import SwiftData

@main
struct VaranApp: App {
  @State private var startupState = StartupState.loading
  @State private var startupAttempt = 0
  @StateObject private var appSettings = AppSettings()

  var body: some Scene {
    WindowGroup {
      startupContent
        .task(id: startupAttempt) {
          await prepareModelContainer()
        }
    }
#if os(macOS)
    Settings {
      settingsContent
        .frame(minWidth: 520, minHeight: 560)
    }
#endif
  }

  @ViewBuilder
  private var startupContent: some View {
#if DEBUG && os(iOS)
    if ScreenshotDemo.enabled {
      ScreenshotDemoRootView()
    } else {
      regularStartupContent
    }
#else
    regularStartupContent
#endif
  }

  @ViewBuilder
  private var regularStartupContent: some View {
    switch startupState {
    case .loading:
      StartupView()
    case .ready(let container):
      AppShellView(appSettings: appSettings)
        .modelContainer(container)
    case .failed(let message):
      StartupFailureView(message: message) {
        startupState = .loading
        startupAttempt += 1
      }
    }
  }

#if os(macOS)
  @ViewBuilder
  private var settingsContent: some View {
    switch startupState {
    case .loading:
      ProgressView("app.preparing")
    case .ready(let container):
      SettingsView(settings: appSettings)
        .modelContainer(container)
    case .failed(let message):
      ContentUnavailableView(
        "app.start.failed",
        systemImage: "externaldrive.badge.exclamationmark",
        description: Text(message)
      )
    }
  }
#endif

  @MainActor
  private func prepareModelContainer() async {
    guard case .loading = startupState else { return }
    do {
      startupState = .ready(try await AppModelContainer.make())
    } catch {
      startupState = .failed(
        String(format: String(localized: "error.startup.databaseUnavailable"), error.localizedDescription)
      )
    }
  }
}

enum AppModelContainer {
  static func make(inMemory: Bool = false) async throws -> ModelContainer {
    try await Task.detached(priority: .userInitiated) {
      let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
      return try ModelContainer(for: ServerProfile.self, configurations: configuration)
    }.value
  }
}

private enum StartupState {
  case loading
  case ready(ModelContainer)
  case failed(String)
}

private struct StartupView: View {
  var body: some View {
    ZStack {
      Color("LaunchScreenBackground")
        .ignoresSafeArea()

      VStack(spacing: 18) {
        Image(systemName: "server.rack")
          .font(.system(size: 52, weight: .medium))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        Text("Varan")
          .font(.title2.bold())
        ProgressView()
          .accessibilityLabel("app.preparing")
      }
    }
  }
}

private struct StartupFailureView: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("app.start.failed", systemImage: "externaldrive.badge.exclamationmark")
    } description: {
      Text(message)
    } actions: {
      Button("action.retry", action: retry)
    }
  }
}

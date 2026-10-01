import Foundation

enum StackComposeSource: String, CaseIterable, Identifiable, Sendable {
  case komodo, host, git, linkedRepo, unknown
  var id: String { rawValue }
  var localizationKey: String { "stack.compose.source.\(rawValue)" }
}

// This snapshot exists only for the open editor. It is never encoded for local
// persistence, and its textual representations never include sensitive contents.
struct StackComposeConfiguration: Decodable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  var filesOnHost: Bool?
  var fileContents: String?
  var runDirectory: String?
  var filePaths: [String]?
  var envFilePath: String?
  var environment: String?
  var linkedRepo: String?
  var repository: String?
  var branch: String?
  var gitProvider: String?
  var gitAccount: String?

  private enum CodingKeys: String, CodingKey {
    case filesOnHost = "files_on_host"
    case fileContents = "file_contents"
    case runDirectory = "run_directory"
    case filePaths = "file_paths"
    case envFilePath = "env_file_path"
    case environment
    case linkedRepo = "linked_repo"
    case repository = "repo"
    case branch
    case gitProvider = "git_provider"
    case gitAccount = "git_account"
  }

  var description: String { "StackComposeConfiguration(contents hidden)" }
  var debugDescription: String { description }

  var source: StackComposeSource {
    if filesOnHost == true { return .host }
    guard filesOnHost == false else { return .unknown }
    if let fileContents, !fileContents.isEmpty { return .komodo }
    guard fileContents != nil else { return .unknown }
    if let linkedRepo, !linkedRepo.isEmpty { return .linkedRepo }
    guard linkedRepo != nil else { return .unknown }
    if let repository, !repository.isEmpty { return .git }
    return .unknown
  }
}

struct StackComposeConfigurationResponse: Decodable, Sendable {
  let config: StackComposeConfiguration
}

struct StackComposeDraft: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  let original: StackComposeConfiguration?
  var source: StackComposeSource
  var fileContents: String
  var runDirectory: String
  var filePathsText: String
  var envFilePath: String
  var environment: String
  var repository: String
  var branch: String
  var gitProvider: String
  var gitAccount: String

  init(original: StackComposeConfiguration? = nil) {
    self.original = original
    source = original?.source ?? .komodo
    fileContents = original?.fileContents ?? ""
    runDirectory = original?.runDirectory ?? ""
    filePathsText = original?.filePaths?.joined(separator: "\n") ?? ""
    envFilePath = original?.envFilePath ?? ".env"
    environment = original?.environment ?? ""
    repository = original?.repository ?? ""
    branch = original?.branch ?? "main"
    gitProvider = original?.gitProvider ?? "github.com"
    gitAccount = original?.gitAccount ?? ""
  }

  var description: String { "StackComposeDraft(contents hidden)" }
  var debugDescription: String { description }
  var isNew: Bool { original == nil }
  var sourceChanged: Bool { source != original?.source }
  var clearsInlineContents: Bool {
    original?.fileContents?.isEmpty == false && patch.fileContents == ""
  }
  var filePaths: [String] {
    filePathsText.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }

  var availableSources: [StackComposeSource] {
    [.komodo, .host, .git]
      + ((original?.linkedRepo?.isEmpty == false) ? [.linkedRepo] : [])
      + (original?.source == .unknown ? [.unknown] : [])
  }

  var validationMessageKey: String? {
    if source == .komodo, (isNew || sourceChanged || fileContents != original?.fileContents),
       fileContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "stack.compose.validation.contents"
    }
    if source == .git, (isNew || sourceChanged || repository != original?.repository) {
      let components = repository.split(separator: "/", omittingEmptySubsequences: false)
      if components.count < 2 || components.contains(where: { $0.isEmpty })
        || repository.contains(":") || repository.contains("@") || repository.contains("\0")
        || repository.contains(where: { $0.isWhitespace || $0.isNewline }) {
        return "stack.compose.validation.repository"
      }
    }
    if (source == .git || source == .linkedRepo),
       (isNew || sourceChanged || branch != (original?.branch ?? "main")),
       branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "stack.compose.validation.branch"
    }
    if source == .git, (isNew || sourceChanged || gitProvider != original?.gitProvider),
       gitProvider.contains("/") || gitProvider.contains(where: { $0.isWhitespace })
         || (try? ServerAddress(gitProvider)) == nil {
      return "stack.compose.validation.provider"
    }
    if (isNew || sourceChanged || runDirectory != (original?.runDirectory ?? "")),
       !runDirectory.isEmpty,
       (runDirectory.contains("\0") || (source != .host && !Self.isRelativePath(runDirectory))) {
      return "stack.compose.validation.directory"
    }
    if isNew || sourceChanged || filePaths != (original?.filePaths ?? []) {
      if filePaths.contains(where: { !Self.isRelativePath($0) }) || Set(filePaths).count != filePaths.count {
        return "stack.compose.validation.paths"
      }
    }
    if (isNew || envFilePath != (original?.envFilePath ?? ".env")),
       !Self.isRelativePath(envFilePath) {
      return "stack.compose.validation.envPath"
    }
    if fileContents.contains("\0") || environment.contains("\0") {
      return "stack.compose.validation.contentsInvalid"
    }
    return nil
  }

  private static func isRelativePath(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.contains("\0")
      && !path.components(separatedBy: "/").contains("..")
  }

  var patch: StackConfigPatch {
    var patch = StackConfigPatch()
    switch source {
    case .komodo:
      if isNew || sourceChanged { patch.filesOnHost = false }
      if isNew || sourceChanged || fileContents != original?.fileContents {
        patch.fileContents = fileContents
      }
    case .host:
      if isNew || sourceChanged { patch.filesOnHost = true }
    case .git, .linkedRepo:
      if isNew || sourceChanged {
        patch.filesOnHost = false
        patch.fileContents = ""
        patch.linkedRepo = source == .git ? "" : original?.linkedRepo
      }
    case .unknown:
      break
    }
    if source == .git || source == .unknown {
      if (source == .git && (isNew || sourceChanged)) || repository != (original?.repository ?? "") {
        patch.repository = repository
      }
      if source == .git {
        if isNew || gitProvider != (original?.gitProvider ?? "github.com") { patch.gitProvider = gitProvider }
        if isNew || gitAccount != (original?.gitAccount ?? "") { patch.gitAccount = gitAccount }
        if isNew || sourceChanged || patch.gitProvider != nil { patch.gitHTTPS = true }
      }
    }
    if source == .git || source == .linkedRepo || source == .unknown {
      if isNew || branch != (original?.branch ?? "main") { patch.branch = branch }
    }
    if runDirectory != (original?.runDirectory ?? "") { patch.runDirectory = runDirectory }
    if filePaths != (original?.filePaths ?? []) { patch.filePaths = filePaths }
    if envFilePath != (original?.envFilePath ?? ".env") { patch.envFilePath = envFilePath }
    if environment != (original?.environment ?? "") { patch.environment = environment }
    return patch
  }

  var changedFields: [String] {
    let patch = patch
    let fields: [(Bool, String)] = [
      (patch.filesOnHost != nil, "stack.compose.source.label"),
      (patch.fileContents != nil, "configuration.field.fileContents"),
      (patch.linkedRepo != nil, "configuration.field.linkedRepo"),
      (patch.repository != nil, "field.repository"),
      (patch.branch != nil, "field.branch"),
      (patch.gitProvider != nil, "configuration.field.gitProvider"),
      (patch.gitAccount != nil, "configuration.field.gitAccount"),
      (patch.gitHTTPS != nil, "configuration.field.gitHTTPS"),
      (patch.runDirectory != nil, "configuration.field.runDirectory"),
      (patch.filePaths != nil, "configuration.field.filePaths"),
      (patch.envFilePath != nil, "configuration.field.envFilePath"),
      (patch.environment != nil, "configuration.field.environment")
    ]
    return fields.compactMap { changed, key in
      changed ? String(localized: String.LocalizationValue(key)) : nil
    }
  }
}

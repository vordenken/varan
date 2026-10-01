import CryptoKit
import Foundation

// Retain only fingerprints, never Compose files, environment values, or error contents.
struct StackFileSnapshot: Decodable, Equatable, Sendable, CustomDebugStringConvertible {
  let path: String
  private let fingerprint: Data
  let requirement: String?

  private enum CodingKeys: String, CodingKey {
    case path, contents
    case requirement = "requires"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
    let contents = try container.decode(String.self, forKey: .contents)
    fingerprint = Data(SHA256.hash(data: Data(contents.utf8)))
    requirement = try container.decodeIfPresent(String.self, forKey: .requirement)
  }

  func hasSameContents(as other: Self) -> Bool { fingerprint == other.fingerprint }
  var debugDescription: String { "StackFileSnapshot(contents: hidden)" }
}

struct StackDeploymentValueComparison: Equatable, Sendable {
  let deployed: String
  let latest: String
  var hasChanged: Bool { deployed != latest }
}

struct StackDeploymentComparison: Equatable, Sendable {
  enum State: String, Sendable {
    case deploymentRequired, restartRequired, revisionAvailable, noDifferences, unavailable
    var localizationKey: String { "stack.deployment.\(rawValue)" }
  }

  let state: State
  let projectNames: StackDeploymentValueComparison?
  let gitRevisions: StackDeploymentValueComparison?
  var projectNameChanged: Bool { projectNames?.hasChanged == true }
  let changedFiles: [String]
  let hasIncompleteFileComparison: Bool

  init(stack: StackDetail) {
    let info = stack.info
    let configuration = stack.config.displayConfiguration
    if let savedName = configuration.projectName,
       let deployedName = info.deployedProjectName, !deployedName.isEmpty {
      projectNames = StackDeploymentValueComparison(deployed: deployedName, latest: savedName.isEmpty ? stack.name : savedName)
    } else {
      projectNames = nil
    }

    var deploy = projectNames?.hasChanged == true
    var restart = false
    var paths: [String] = []
    var comparedFiles = false
    var incomplete = true
    let source = configuration.composeSourceLocalizationKey
    let usesRemoteFiles = ["host", "git", "linkedRepo"].contains {
      source == "configuration.source.\($0)"
    }
    // Remote contents are the server's cached source snapshot, not a fresh host read.
    // Inline contents may be interpolated before deployment and cannot be compared safely.
    if usesRemoteFiles, info.missingFiles.isEmpty, info.remoteErrors?.isEmpty == true,
       let latest = info.remoteContents, !latest.isEmpty,
       let deployed = info.deployedContents, !deployed.isEmpty,
       Set(latest.map(\.path)).count == latest.count,
       Set(deployed.map(\.path)).count == deployed.count {
      comparedFiles = true
      incomplete = false
      for file in latest {
        guard let previous = deployed.first(where: { $0.path == file.path }) else {
          paths.append(file.path)
          deploy = true
          continue
        }
        guard !file.hasSameContents(as: previous) else { continue }
        switch file.requirement {
        case "Redeploy":
          deploy = true
          paths.append(file.path)
        case "Restart":
          restart = true
          paths.append(file.path)
        case "None": break
        default: incomplete = true
        }
      }
      // Removed paths and unknown requirements cannot establish equivalence.
      if !Set(deployed.map(\.path)).isSubset(of: Set(latest.map(\.path))) {
        incomplete = true
      }
    }
    changedFiles = paths.sorted()
    hasIncompleteFileComparison = incomplete
    let usesGit = ["git", "linkedRepo"].contains { source == "configuration.source.\($0)" }
    if usesGit, let latest = info.latestHash, !latest.isEmpty,
       let deployed = info.deployedHash, !deployed.isEmpty {
      gitRevisions = StackDeploymentValueComparison(deployed: deployed, latest: latest)
    } else {
      gitRevisions = nil
    }
    let revisionChanged = gitRevisions?.hasChanged == true
    if deploy {
      state = .deploymentRequired
    } else if restart {
      state = .restartRequired
    } else if revisionChanged {
      // A Git revision alone does not establish that any deployed file changed.
      state = .revisionAvailable
    } else if comparedFiles && !incomplete {
      state = .noDifferences
    } else {
      state = .unavailable
    }
  }
}

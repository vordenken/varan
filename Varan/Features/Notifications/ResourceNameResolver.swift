import Combine
import Foundation

@MainActor
final class ResourceNameResolver: ObservableObject {
  enum Resolution: Equatable {
    case name(String)
    case missing
    case unavailable
  }

  @Published private(set) var resolutions: [String: Resolution] = [:]
  @Published private(set) var generation = 0
  private var loadedTypes: Set<String> = []
  private var pendingKeys: Set<String> = []

  static func supports(_ target: KomodoNoticeTarget) -> Bool {
    !target.id.isEmpty && KomodoAPIClient.nameableResourceTypes[target.type] != nil
  }

  func resolution(for target: KomodoNoticeTarget) -> Resolution? {
    resolutions[key(target)]
  }

  func reset() {
    resolutions = [:]
    loadedTypes = []
    pendingKeys = []
    generation += 1
  }

  /// Keeps known names visible while the next prefetch reloads them.
  func invalidate() {
    resolutions = resolutions.filter { $0.value != .unavailable }
    loadedTypes = []
    generation += 1
  }

  func prefetch(_ targets: [KomodoNoticeTarget], client: KomodoAPIClient) async {
    let generation = generation
    let byType = Dictionary(grouping: Set(targets.filter(Self.supports).map(TargetKey.init)), by: \.type)
    for (type, keys) in byType {
      var verify = keys.filter { resolutions[$0.value] == nil }
      if !loadedTypes.contains(type) {
        loadedTypes.insert(type)
        do {
          let names = try await client.listResourceNames(type: type)
          guard generation == self.generation else { return }
          resolutions.merge(names.map { ("\(type):\($0.key)", .name($0.value)) }) { _, new in new }
          verify = keys.filter { names[$0.id] == nil }
        } catch is CancellationError {
          loadedTypes.remove(type)
          return
        } catch {
          // Unsupported list endpoints fall back to single lookups until the next invalidation.
          guard generation == self.generation else { return }
          verify = Array(keys)
        }
      }
      for target in verify {
        await resolve(KomodoNoticeTarget(type: target.type, id: target.id), client: client, force: true)
        guard generation == self.generation else { return }
      }
    }
  }

  func name(for target: KomodoNoticeTarget, client: KomodoAPIClient) async -> String? {
    await resolve(target, client: client, force: false)
    if case .name(let name) = resolutions[key(target)] { return name }
    return nil
  }

  private func resolve(_ target: KomodoNoticeTarget, client: KomodoAPIClient, force: Bool) async {
    let key = key(target)
    guard Self.supports(target), force || resolutions[key] == nil,
          pendingKeys.insert(key).inserted else { return }
    let generation = generation
    defer { pendingKeys.remove(key) }
    let resolution: Resolution
    do {
      resolution = try await client.resourceName(type: target.type, id: target.id).map(Resolution.name)
        ?? .missing
    } catch KomodoAPIError.server(statusCode: 404, reason: _) {
      resolution = .missing
    } catch KomodoAPIError.server(statusCode: 500, reason: let reason) {
      let missingReasons = ["not found", "Did not find any \(target.type) matching \(target.id)"]
      resolution = missingReasons.contains { reason?.caseInsensitiveCompare($0) == .orderedSame }
        ? .missing : .unavailable
    } catch is CancellationError {
      return
    } catch {
      resolution = .unavailable
    }
    guard generation == self.generation else { return }
    resolutions[key] = resolution
  }

  private func key(_ target: KomodoNoticeTarget) -> String { "\(target.type):\(target.id)" }

  private struct TargetKey: Hashable {
    let type: String
    let id: String
    var value: String { "\(type):\(id)" }

    init(_ target: KomodoNoticeTarget) {
      type = target.type
      id = target.id
    }
  }
}

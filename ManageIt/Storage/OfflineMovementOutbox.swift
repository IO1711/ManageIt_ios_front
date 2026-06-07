import Foundation

/// Single queued (or rejected) offline movement awaiting server replay.
struct OfflineMovementEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var itemId: Int64
    var queuedAt: Date
    var request: ItemMovementCreateRequest
    var optimisticItem: ItemResponse
    var status: Status
    var lastError: String?

    enum Status: String, Codable {
        case queued
        case syncing
        case rejected
    }
}

/// Dedicated persistent outbox per the architecture: "Synchronization must
/// read only from that dedicated outbox." Stored separately from any other
/// UI state so that view caches cannot drift away from the canonical
/// pending-write list.
final class OfflineMovementOutbox {
    private let userDefaults: UserDefaults
    private let key = "manageit.offline.movement.outbox"

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func load() -> [OfflineMovementEntry] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        return (try? decoder.decode([OfflineMovementEntry].self, from: data)) ?? []
    }

    func save(_ entries: [OfflineMovementEntry]) {
        guard let data = try? encoder.encode(entries) else { return }
        userDefaults.set(data, forKey: key)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}

/// Local cache of the last successfully fetched location hierarchy. Used by
/// the Movement form so the user can still pick a destination while offline.
final class OfflineLocationCache {
    private let userDefaults: UserDefaults
    private let key = "manageit.offline.location.cache"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> [LocationResponse] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([LocationResponse].self, from: data)) ?? []
    }

    func save(_ locations: [LocationResponse]) {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        userDefaults.set(data, forKey: key)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}

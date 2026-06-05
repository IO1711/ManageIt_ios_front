import Foundation

final class AppPreferences {
    private enum Keys {
        static let serverAddress = "manageit.serverAddress"
        static let pairedDeviceContext = "manageit.pairedDeviceContext"
        static let lastInventoryQuery = "manageit.lastInventoryQuery"
        static let cachedLocations = "manageit.cachedLocations"
        static let offlineMovementOutbox = "manageit.offlineMovementOutbox"
    }

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var serverAddress: String {
        get { userDefaults.string(forKey: Keys.serverAddress) ?? "" }
        set { userDefaults.set(newValue, forKey: Keys.serverAddress) }
    }

    func loadDeviceContext() -> StoredDeviceContext? {
        guard let data = userDefaults.data(forKey: Keys.pairedDeviceContext) else {
            return nil
        }

        return try? decoder.decode(StoredDeviceContext.self, from: data)
    }

    func saveDeviceContext(_ context: StoredDeviceContext) {
        guard let data = try? encoder.encode(context) else {
            return
        }

        userDefaults.set(data, forKey: Keys.pairedDeviceContext)
    }

    func clearDeviceContext() {
        userDefaults.removeObject(forKey: Keys.pairedDeviceContext)
    }

    func clearAllLocalContext() {
        userDefaults.removeObject(forKey: Keys.pairedDeviceContext)
        userDefaults.removeObject(forKey: Keys.serverAddress)
        userDefaults.removeObject(forKey: Keys.lastInventoryQuery)
        userDefaults.removeObject(forKey: Keys.cachedLocations)
        userDefaults.removeObject(forKey: Keys.offlineMovementOutbox)
    }

    func saveLastInventoryQuery(_ query: String) {
        userDefaults.set(query, forKey: Keys.lastInventoryQuery)
    }

    func loadLastInventoryQuery() -> String {
        userDefaults.string(forKey: Keys.lastInventoryQuery) ?? ""
    }

    func saveCachedLocations(_ locations: [LocationResponse]) {
        guard let data = try? encoder.encode(locations) else {
            return
        }
        userDefaults.set(data, forKey: Keys.cachedLocations)
    }

    func loadCachedLocations() -> [LocationResponse] {
        guard let data = userDefaults.data(forKey: Keys.cachedLocations) else {
            return []
        }
        return (try? decoder.decode([LocationResponse].self, from: data)) ?? []
    }

    func saveOfflineMovementOutbox(_ entries: [OfflineMovementOutboxEntry]) {
        guard let data = try? encoder.encode(entries) else {
            return
        }
        userDefaults.set(data, forKey: Keys.offlineMovementOutbox)
    }

    func loadOfflineMovementOutbox() -> [OfflineMovementOutboxEntry] {
        guard let data = userDefaults.data(forKey: Keys.offlineMovementOutbox) else {
            return []
        }
        return (try? decoder.decode([OfflineMovementOutboxEntry].self, from: data)) ?? []
    }
}

import Foundation

final class AppPreferences {
    private enum Keys {
        static let serverAddress = "manageit.serverAddress"
        static let pairedDeviceContext = "manageit.pairedDeviceContext"
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
}

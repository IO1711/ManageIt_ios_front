import Foundation
import Security

final class KeychainStore {
    private let service = "com.bestAppleDev.ManageIt"
    private let refreshTokenAccount = "device.refresh-token"
    private let installationIdAccount = "device.installation-id"

    func saveRefreshToken(_ refreshToken: String) throws {
        try saveString(refreshToken, account: refreshTokenAccount)
    }

    func loadOrCreateInstallationId() throws -> UUID {
        if
            let storedValue = try loadString(account: installationIdAccount)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let installationId = UUID(uuidString: storedValue)
        {
            return installationId
        }

        let installationId = UUID()
        try saveString(installationId.uuidString, account: installationIdAccount)
        return installationId
    }

    func clearRefreshToken() {
        clearValue(account: refreshTokenAccount)
    }

    private func saveString(_ value: String, account: String) throws {
        let encodedValue = Data(value.utf8)
        let query = baseQuery(for: account)

        let attributes: [String: Any] = [
            kSecValueData as String: encodedValue
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw KeychainStoreError.operationFailed(updateStatus)
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = encodedValue

        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.operationFailed(addStatus)
        }
    }

    private func loadString(account: String) throws -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.operationFailed(status)
        }

        guard
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainStoreError.operationFailed(errSecDecode)
        }

        return value
    }

    private func clearValue(account: String) {
        let query = baseQuery(for: account)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainStoreError: Error {
    case operationFailed(OSStatus)
}

import Foundation
import Security

enum SpotifyKeychain {
    private static let service = "com.jackson.sideman.spotify"
    private static let account = "tokens"

    static func saveTokens(_ tokens: SpotifyTokens) throws {
        let data = try JSONEncoder().encode(tokens)

        deleteTokens()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SpotifyClientError.network("Keychain save failed: \(status)")
        }

        DebugLogger.log(.app, "Spotify tokens saved to Keychain")
    }

    static func loadTokens() -> SpotifyTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        do {
            let tokens = try JSONDecoder().decode(SpotifyTokens.self, from: data)
            DebugLogger.log(.app, "Spotify tokens loaded from Keychain")
            return tokens
        } catch {
            DebugLogger.log(.app, "Spotify tokens decode failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func deleteTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}

import Foundation
import Security

enum Credentials {
    static let service = "com.presstrans.mac.deepseek"
    static func load() -> String? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"api-key", kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let key = String(data:data, encoding:.utf8), !key.isEmpty { return key }
        // Development builds reference the ignored .env by path; no key is bundled.
        if let path = Bundle.main.object(forInfoDictionaryKey:"PressTransDevelopmentConfig") as? String,
           let contents = try? String(contentsOfFile:path, encoding:.utf8) {
            return contents.split(separator:"\n").first(where:{$0.hasPrefix("DEEPSEEK_API_KEY=")}).map { String($0.dropFirst("DEEPSEEK_API_KEY=".count)).trimmingCharacters(in:.whitespacesAndNewlines) }
        }
        return nil
    }
    static func save(_ key:String) -> Bool {
        let query:[String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"api-key"]
        let attributes:[String:Any] = [kSecValueData as String:Data(key.utf8)]
        let status=SecItemUpdate(query as CFDictionary,attributes as CFDictionary)
        if status==errSecItemNotFound { return SecItemAdd(query.merging(attributes){_,new in new} as CFDictionary,nil)==errSecSuccess }
        return status==errSecSuccess
    }
}

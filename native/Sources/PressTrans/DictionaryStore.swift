import Foundation
import PressTransCore

enum DictionaryStore {
    static let shared: OfflineDictionary? = {
        guard let url = Bundle.main.url(forResource: "dictionary", withExtension: "sqlite") else { return nil }
        return try? OfflineDictionary(path: url.path)
    }()
    static var available: Bool { shared != nil }
}

enum TranslationPreferences {
    static var onlineEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "onlineEnhancementEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "onlineEnhancementEnabled") }
    }
}

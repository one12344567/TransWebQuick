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
    static var chineseMode:ChineseMode {
        get {ChineseMode(rawValue:UserDefaults.standard.string(forKey:"chineseResponseMode") ?? "") ?? .translateAndExplain}
        set {UserDefaults.standard.set(newValue.rawValue,forKey:"chineseResponseMode")}
    }
    static var chineseTarget:OutputLanguage {
        get {OutputLanguage(rawValue:UserDefaults.standard.string(forKey:"chineseTargetLanguage") ?? "") ?? .english}
        set {UserDefaults.standard.set(newValue.rawValue,forKey:"chineseTargetLanguage")}
    }
    static var policy:TranslationPolicy {TranslationPolicy(chineseMode:chineseMode,chineseTarget:chineseTarget)}
    static var onlineEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "onlineEnhancementEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "onlineEnhancementEnabled") }
    }
}

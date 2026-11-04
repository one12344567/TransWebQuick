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
    static var target:String {
        get {UserDefaults.standard.string(forKey:"translationTarget") ?? "system"}
        set {UserDefaults.standard.set(newValue,forKey:"translationTarget")}
    }
    static var explanation:String {
        get {UserDefaults.standard.string(forKey:"explanationLanguage") ?? "target"}
        set {UserDefaults.standard.set(newValue,forKey:"explanationLanguage")}
    }
    static var sameLanguageTranslate:Bool {
        get {
            if UserDefaults.standard.object(forKey:"sameLanguageTranslate") != nil {return UserDefaults.standard.bool(forKey:"sameLanguageTranslate")}
            return UserDefaults.standard.string(forKey:"chineseResponseMode") == ChineseMode.translateAndExplain.rawValue
        }
        set {UserDefaults.standard.set(newValue,forKey:"sameLanguageTranslate")}
    }
    static var alternate:String {
        get {UserDefaults.standard.string(forKey:"alternateLanguage") ?? chineseTarget.rawValue.capitalized}
        set {UserDefaults.standard.set(newValue,forKey:"alternateLanguage")}
    }
    static var resolvedTarget:String {target == "system" ? LanguageOptions.systemLanguage : target}
    static var policy:TranslationPolicy {
        TranslationPolicy(targetLanguage:resolvedTarget,explanationLanguage:explanation == "target" ? resolvedTarget:explanation,sameLanguageTranslate:sameLanguageTranslate,alternateLanguage:alternate)
    }
    static var supportsOffline:Bool {resolvedTarget == "Chinese (Simplified)"}
    static var onlineEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "onlineEnhancementEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "onlineEnhancementEnabled") }
    }
}

import Foundation
import PressTransCore

enum ServiceProvider:String,CaseIterable {
    case deepseek="DeepSeek",openAI="OpenAI",bailian="Alibaba Cloud",moonshot="Moonshot / Kimi",custom="Custom"
    var baseURL:String {switch self {
    case .deepseek:"https://api.deepseek.com"
    case .openAI:"https://api.openai.com/v1"
    case .bailian:"https://dashscope.aliyuncs.com/compatible-mode/v1"
    case .moonshot:"https://api.moonshot.cn/v1"
    case .custom:""
    }}
    var model:String {switch self {
    case .deepseek:"deepseek-flash"
    case .openAI:"gpt-4.1-mini"
    case .bailian:"qwen-plus"
    case .moonshot:"kimi-k3.1-pro"
    case .custom:""
    }}
}
enum ServicePreferences {
    static var provider:ServiceProvider {ServiceProvider(rawValue:UserDefaults.standard.string(forKey:"serviceProvider") ?? "") ?? .deepseek}
    static var baseURL:String {UserDefaults.standard.string(forKey:"serviceBaseURL") ?? ServiceProvider.deepseek.baseURL}
    static var model:String {UserDefaults.standard.string(forKey:"serviceModel") ?? ServiceProvider.deepseek.model}
    static func save(provider:ServiceProvider,baseURL:String,model:String,key:String)->Bool {
        guard let endpoint=ServiceEndpoint.completionURL(baseURL),!model.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return false}
        let cleaned=key.trimmingCharacters(in:.whitespacesAndNewlines)
        let savedKey=cleaned.isEmpty && endpoint == ServiceEndpoint.completionURL(Self.baseURL) ? Credentials.load():cleaned
        guard let savedKey,!savedKey.isEmpty,Credentials.save(savedKey,endpoint:endpoint.absoluteString) else{return false}
        UserDefaults.standard.set(provider.rawValue,forKey:"serviceProvider")
        UserDefaults.standard.set(baseURL.trimmingCharacters(in:.whitespacesAndNewlines),forKey:"serviceBaseURL")
        UserDefaults.standard.set(model.trimmingCharacters(in:.whitespacesAndNewlines),forKey:"serviceModel")
        return true
    }
}
/// Never forward a stored API key through a redirect to another endpoint.
final class NoServiceRedirect:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void){completionHandler(nil)}
}

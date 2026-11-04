import Foundation
import PressTransCore

enum TranslationFailure: LocalizedError {
    case missingKey, auth, rateLimit, incomplete, network
    var errorDescription: String? {
        switch self {
        case .missingKey: return L("在线增强尚未配置，仍可使用离线词典。")
        case .auth: return L("密钥或账户验证失败，请检查设置。")
        case .rateLimit: return L("服务暂时限流，请稍后重试。")
        case .incomplete: return L("回答未完整返回。请稍后手动重试。")
        case .network: return L("连接暂不可用，请稍后重试。")
        }
    }
}
struct Translator {
    static func run(_ context: CapturedContext, detail: Bool, policy:TranslationPolicy, onText: @escaping @Sendable (String) async -> Void) async throws {
        guard let key = Credentials.load(), !key.isEmpty else { throw TranslationFailure.missingKey }
        guard let endpoint=ServiceEndpoint.completionURL(ServicePreferences.baseURL) else {throw TranslationFailure.network}
        var request = URLRequest(url:endpoint)
        request.httpMethod="POST"; request.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization"); request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let payload:[String:Any] = ["selectedText":context.selection,"sources":[["kind":"paragraph","text":context.context]],"contextStatus":context.limited ? "limited":"complete","mode":detail ? "detail":"brief"]
        let user = String(data:try JSONSerialization.data(withJSONObject:payload),encoding:.utf8)!
        var body:[String:Any] = ["model":ServicePreferences.model,"stream":true,"max_tokens":detail ? 900:600,"messages":[["role":"system","content":policy.prompt],["role":"user","content":user]]]
        if endpoint.host == "api.deepseek.com" {body["thinking"]=["type":"disabled"]}
        request.httpBody=try JSONSerialization.data(withJSONObject:body)
        let config=URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest=15; config.timeoutIntervalForResource=30; config.urlCache=nil
        let session=URLSession(configuration:config,delegate:NoServiceRedirect(),delegateQueue:nil); defer { session.invalidateAndCancel() }
        let (bytes,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse else { throw TranslationFailure.network }
        guard http.statusCode==200 else { throw http.statusCode==401 || http.statusCode==403 ? TranslationFailure.auth : http.statusCode==429 ? TranslationFailure.rateLimit : TranslationFailure.network }
        var parser=SSEParser(), text="", finished=false, lastUpdate=Date.distantPast
        var lineBytes: [UInt8] = []
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte != 10 {
                lineBytes.append(byte)
                guard lineBytes.count <= 65536 else { throw TranslationFailure.incomplete }
                continue
            }
            if lineBytes.last == 13 { lineBytes.removeLast() }
            let line = String(decoding: lineBytes, as: UTF8.self)
            lineBytes.removeAll(keepingCapacity: true)
            guard let data=parser.line(line) else { continue }
            if data=="[DONE]" { break }
            guard let object=try JSONSerialization.jsonObject(with:Data(data.utf8)) as? [String:Any], let choices=object["choices"] as? [[String:Any]], let choice=choices.first else { continue }
            if let delta=choice["delta"] as? [String:Any], let chunk=delta["content"] as? String {
                text+=chunk
                guard text.count<=12000 else { throw TranslationFailure.incomplete }
                if Date().timeIntervalSince(lastUpdate)>0.04 { await onText(text); lastUpdate=Date() }
            }
            if let reason=choice["finish_reason"] as? String { guard reason=="stop" else { throw TranslationFailure.incomplete }; finished=true }
        }
        guard finished, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw TranslationFailure.incomplete }
        await onText(text)
    }
}

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
    static func run(_ context: CapturedContext, detail: Bool, policy:TranslationPolicy, onText: @escaping @Sendable (String) async -> Void, onRecord:@escaping @Sendable (UsageRecord) async ->Void) async throws {
        guard let key = Credentials.load(), !key.isEmpty else { throw TranslationFailure.missingKey }
        guard let endpoint=ServiceEndpoint.completionURL(ServicePreferences.baseURL) else {throw TranslationFailure.network}
        var request = URLRequest(url:endpoint)
        request.httpMethod="POST"; request.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization"); request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let payload:[String:Any] = ["selectedText":context.selection,"sources":[["kind":"paragraph","text":context.context]],"contextStatus":context.limited ? "limited":"complete","mode":detail ? "detail":"brief"]
        let user = String(data:try JSONSerialization.data(withJSONObject:payload),encoding:.utf8)!
        let model=ServicePreferences.model
        var body:[String:Any] = ["model":model,"stream":true,"stream_options":["include_usage":true],"max_tokens":detail ? 900:600,"messages":[["role":"system","content":policy.prompt],["role":"user","content":user]]]
        if endpoint.host == "api.deepseek.com" {body["thinking"]=["type":"disabled"]}
        request.httpBody=try JSONSerialization.data(withJSONObject:body)
        let config=URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest=15; config.timeoutIntervalForResource=30; config.urlCache=nil
        let session=URLSession(configuration:config,delegate:NoServiceRedirect(),delegateQueue:nil); defer { session.invalidateAndCancel() }
        try Task.checkCancellation()
        var record=UsageRecord(provider:ServicePreferences.provider.rawValue,model:model,detail:detail)
        await UsageHistory.shared.save(record)
        do {
        try Task.checkCancellation()
        let (bytes,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse else { throw TranslationFailure.network }
        guard http.statusCode==200 else { throw http.statusCode==401 || http.statusCode==403 ? TranslationFailure.auth : http.statusCode==429 ? TranslationFailure.rateLimit : TranslationFailure.network }
        let text: String
        do {
            text = try await withTaskCancellationHandler {
                try await CompletionStream.read(bytes, usage: &record.usage, onText: onText)
            } onCancel: {
                session.invalidateAndCancel()
            }
        } catch CompletionStream.Failure.incomplete {
            throw TranslationFailure.incomplete
        }
        try Task.checkCancellation()
        await onText(text)
        try Task.checkCancellation()
        record.status="completed"
        await UsageHistory.shared.save(record)
        await onRecord(record)
        } catch {
            record.status=Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled ? "cancelled":"failed"
            await UsageHistory.shared.save(record)
            await onRecord(record)
            throw error
        }
    }
}

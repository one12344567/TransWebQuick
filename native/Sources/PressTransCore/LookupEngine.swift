import Foundation

public struct LookupUpdate: Sendable {
    public let text: String
    public let note: String
    public let message: String
    public let loading: Bool
    public let complete: Bool
    public let offline: Bool
    public var reference: DictionaryResult? = nil
}
/// Online answers own the primary surface. Local results are references or an explicit failure fallback.
public enum LookupEngine {
    public typealias Sink = @Sendable (LookupUpdate) async -> Void
    public typealias Online = @Sendable (@escaping @Sendable (String) async -> Void) async throws -> Void
    public static func run(local: @Sendable () async -> DictionaryResult?, online: Online?, emit: @escaping Sink) async {
        guard !Task.isCancelled else { return }
        guard let online else {
            let result=await local()
            guard !Task.isCancelled else{return}
            await emit(localUpdate(result,message:""))
            return
        }
        await emit(LookupUpdate(text:"",note:"",message:"",loading:true,complete:false,offline:false))
        let buffer = ResponseBuffer()
        do {
            try await online { text in
                guard !Task.isCancelled else { return }
                await buffer.set(text)
                await emit(LookupUpdate(text:text,note:"",message:"",loading:true,complete:false,offline:false))
            }
            guard !Task.isCancelled else { return }
            let text = await buffer.text
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw CocoaError(.fileReadUnknown) }
            await emit(LookupUpdate(text:text,note:"",message:"",loading:false,complete:true,offline:false))
            // Fetch reference text after delivering the complete online answer, never before the request.
            let reference=await local()
            guard !Task.isCancelled else{return}
            if let reference,!reference.entries.isEmpty {
                await emit(LookupUpdate(text:text,note:"",message:"",loading:false,complete:true,offline:false,reference:reference))
            }
        } catch {
            guard !Task.isCancelled else { return }
            let result=await local()
            guard !Task.isCancelled else{return}
            await emit(localUpdate(result,message:"在线增强暂不可用，已回退离线词典。"))
        }
    }
    private static func localUpdate(_ result:DictionaryResult?,message:String)->LookupUpdate {
        LookupUpdate(text:result?.text ?? "",note:result?.note ?? "离线词库未安装，请重新构建完整应用。",message:message,loading:false,complete:!(result?.entries.isEmpty ?? true),offline:true)
    }
    private actor ResponseBuffer {
        var text = ""
        func set(_ text: String) { self.text = text }
    }
}

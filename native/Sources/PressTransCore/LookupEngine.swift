import Foundation

public struct LookupUpdate: Sendable {
    public let text: String
    public let note: String
    public let message: String
    public let loading: Bool
    public let complete: Bool
    public let offline: Bool
}
/// Delivers the local answer before optional online enhancement. Failed partial responses never replace it.
public enum LookupEngine {
    public typealias Sink = @Sendable (LookupUpdate) async -> Void
    public typealias Online = @Sendable (@escaping @Sendable (String) async -> Void) async throws -> Void
    public static func run(local: @Sendable () async -> DictionaryResult?, online: Online?, emit: @escaping Sink) async {
        let result = await local()
        guard !Task.isCancelled else { return }
        let localText = result?.text ?? ""
        let localNote = result?.note ?? "离线词库未安装，请重新构建完整应用。"
        let complete = !(result?.entries.isEmpty ?? true)
        await emit(LookupUpdate(text:localText,note:localNote,message:"",loading:online != nil,complete:complete,offline:true))
        guard let online, !Task.isCancelled else { return }
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
        } catch {
            guard !Task.isCancelled else { return }
            await emit(LookupUpdate(text:localText,note:localNote,message:"在线增强暂不可用，已回退离线词典。",loading:false,complete:complete,offline:true))
        }
    }
    private actor ResponseBuffer {
        var text = ""
        func set(_ text: String) { self.text = text }
    }
}

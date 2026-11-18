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
        guard !Task.isCancelled else { return }
        let buffer = ResponseBuffer()
        do {
            try await online { text in
                guard !Task.isCancelled else { return }
                await buffer.set(text)
                guard !Task.isCancelled else { return }
                await emit(LookupUpdate(text:text,note:"",message:"",loading:true,complete:false,offline:false))
            }
            guard !Task.isCancelled else { return }
            let text = await buffer.text
            try Task.checkCancellation()
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw CocoaError(.fileReadUnknown) }
            await emit(LookupUpdate(text:text,note:"",message:"",loading:false,complete:true,offline:false))
            // Fetch reference text after delivering the complete online answer, never before the request.
            guard !Task.isCancelled else { return }
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

/// Reads one chat completion. A stop frame completes the text, while a later frame may add usage.
public enum CompletionStream {
    public enum Failure: Error { case incomplete }

    @inlinable public static func read<Bytes: AsyncSequence>(
        _ bytes: Bytes, usage: inout TokenUsage?, onText: (String) async -> Void
    ) async throws -> String where Bytes.Element == UInt8 {
        usage = nil
        var parser = SSEParser()
        var answer = StreamedAnswer()
        var finishReason: String?
        var lineBytes: [UInt8] = []
        var lastUpdate = Date.distantPast
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                if byte != 10 {
                    lineBytes.append(byte)
                    guard lineBytes.count <= 65_536 else { throw Failure.incomplete }
                    continue
                }
                if lineBytes.last == 13 { lineBytes.removeLast() }
                let line = String(decoding: lineBytes, as: UTF8.self)
                lineBytes.removeAll(keepingCapacity: true)
                guard let data = parser.line(line) else { continue }
                if data == "[DONE]" { break }
                let event = try CompletionChunk(data: data)
                if finishReason == nil {
                    if let delta = event.content {
                        guard answer.append(delta) else { throw Failure.incomplete }
                        if Date().timeIntervalSince(lastUpdate) > 0.04 {
                            await onText(answer.text)
                            lastUpdate = Date()
                        }
                    }
                    finishReason = event.finishReason
                }
                // Compatible providers may report provisional counters alongside content.
                // Only the terminal choice frame or a later usage frame confirms the total.
                if finishReason != nil, let finalUsage = event.usage {
                    usage = finalUsage
                    break
                }
            }
        } catch {
            try Task.checkCancellation()
            // A timeout or dropped connection while collecting optional counters does not
            // invalidate already completed text. An interrupted partial answer must still fail.
            guard finishReason == "stop", error is URLError else { throw error }
        }
        try Task.checkCancellation()
        guard finishReason == "stop", !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.incomplete
        }
        return answer.text
    }
}

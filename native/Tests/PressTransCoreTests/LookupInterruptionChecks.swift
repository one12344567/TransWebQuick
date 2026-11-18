import Foundation
import PressTransCore

func checkLookupInterruptions() async throws {
    let content = #"{"choices":[{"delta":{"content":"译文"}}]}"#
    let contentWithUsage = #"{"choices":[{"delta":{"content":"译文"}}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}}"#
    let stop = #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#
    let length = #"{"choices":[{"delta":{},"finish_reason":"length"}]}"#
    let stats = #"{"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":2,"total_tokens":7}}"#

    func bytes(_ frames: [String], error: Error? = nil) -> AsyncThrowingStream<UInt8, Error> {
        AsyncThrowingStream { stream in
            for frame in frames {
                for byte in "data: \(frame)\r\n\r\n".utf8 { stream.yield(byte) }
            }
            stream.finish(throwing: error)
        }
    }

    for code in [URLError.timedOut, .networkConnectionLost] {
        var usage: TokenUsage?
        let final = try await CompletionStream.read(bytes([content, stop], error: URLError(code)), usage: &usage) { _ in }
        precondition(final == "译文" && usage == nil)
        do {
            _ = try await CompletionStream.read(bytes([content], error: URLError(code)), usage: &usage) { _ in }
            preconditionFailure("Transport failure before stop must reject partial text")
        } catch let error as URLError { precondition(error.code == code) }
    }

    var usage: TokenUsage?
    let final = try await CompletionStream.read(bytes([content, stop, stats, "invalid after usage"]), usage: &usage) { _ in }
    precondition(final == "译文" && usage?.total == 7)
    let previewThenFinal = try await CompletionStream.read(bytes([contentWithUsage, stop, stats]), usage: &usage) { _ in }
    precondition(previewThenFinal == "译文" && usage?.total == 7)
    let missingFinalUsage = try await CompletionStream.read(bytes([contentWithUsage, stop], error: URLError(.timedOut)), usage: &usage) { _ in }
    precondition(missingFinalUsage == "译文" && usage == nil)
    usage = nil
    do {
        _ = try await CompletionStream.read(bytes([content, length, stats]), usage: &usage) { _ in }
        preconditionFailure("Output limit must reject incomplete text")
    } catch CompletionStream.Failure.incomplete { precondition(usage?.total == 7) }

    // Cancel from precisely the UI handoff, before the next stage has a chance to start.
    await Task {
        await LookupEngine.run(local: { preconditionFailure("Unexpected dictionary lookup") }, online: { _ in
            preconditionFailure("A cancelled loading callback must not start the provider")
        }) { _ in withUnsafeCurrentTask { $0?.cancel() } }
    }.value
    await Task {
        await LookupEngine.run(local: { preconditionFailure("Cancellation must skip dictionary reference") }, online: { sink in
            await sink("译文")
        }) { update in
            if update.complete { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }.value
    print("Stream interruption checks passed: timeout and disconnect before/after stop, separate usage, truncation, cancellation at UI handoffs")
}

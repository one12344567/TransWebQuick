import Foundation
import PressTransCore

func checkUsage() async throws {
    let deepseek=try CompletionChunk(data:#"{"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":25,"total_tokens":125,"prompt_cache_hit_tokens":64}}"#)
    precondition(deepseek.finishReason=="stop" && deepseek.usage?.total==125 && deepseek.usage?.cached==64)
    let openAI=try CompletionChunk(data:#"{"choices":[],"usage":{"prompt_tokens":80,"completion_tokens":20,"total_tokens":100,"prompt_tokens_details":{"cached_tokens":32},"completion_tokens_details":{"reasoning_tokens":5}}}"#)
    precondition(openAI.content==nil && openAI.usage?.cached==32 && openAI.usage?.reasoning==5)
    let partial=try CompletionChunk(data:#"{"choices":[{"delta":{"content":"hello"}}],"usage":null}"#)
    precondition(partial.content=="hello" && partial.usage==nil)
    precondition(TokenUsage.parse(["prompt_tokens":false,"completion_tokens":1])==nil)
    precondition(TokenUsage.parse(["prompt_tokens":-1,"completion_tokens":1])==nil)
    precondition(TokenUsage.parse(["prompt_tokens":"100","completion_tokens":1])==nil)
    precondition(TokenUsage.parse(["prompt_tokens":1.5,"completion_tokens":1])==nil)
    precondition(TokenUsage.parse(["prompt_tokens":0,"completion_tokens":0])?.total==0)

    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("presstrans-usage-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let path=directory.appendingPathComponent("usage.sqlite").path
    var ledger:UsageLedger?=try UsageLedger(path:path)
    let first=UsageRecord(provider:"DeepSeek",model:"test-model",detail:false)
    try await ledger!.save(first)
    var finished=first;finished.status="completed";finished.usage=deepseek.usage
    try await ledger!.save(finished)
    try await ledger!.save(finished) // Completion replay is an upsert, never another charge.
    try await ledger!.save(UsageRecord(provider:"Custom",model:"test",detail:true,status:"cancelled"))
    try await ledger!.save(UsageRecord(provider:"OpenAI",model:"test",detail:false,status:"failed",usage:openAI.usage))
    var page=try await ledger!.page()
    precondition(page.count==3 && page.total==225 && page.today==225 && page.unknown==1)
    precondition(page.records.first?.status=="failed")
    let today=Calendar.current.startOfDay(for:Date())
    try await ledger!.save(UsageRecord(date:today.addingTimeInterval(-10),provider:"DeepSeek",model:"yesterday",detail:false,status:"completed",usage:deepseek.usage))
    let pending=UsageRecord(provider:"Custom",model:"pending",detail:false)
    try await ledger!.save(pending)
    ledger=nil
    ledger=try UsageLedger(path:path)
    page=try await ledger!.page()
    precondition(page.count==5 && page.total==350 && page.today==225 && page.unknown==2)
    precondition(page.records.contains{$0.id==pending.id && $0.status=="interrupted"})
    let second=try await ledger!.page(offset:2,limit:2)
    precondition(second.records.count==2 && second.records[0].id==page.records[2].id)
    let permissions=try FileManager.default.attributesOfItem(atPath:path)[.posixPermissions] as? Int
    precondition(permissions==0o600)
    for _ in 0..<995 {try await ledger!.save(UsageRecord(provider:"DeepSeek",model:"deepseek-flash",detail:false,status:"completed",usage:deepseek.usage))}
    page=try await ledger!.page()
    precondition(page.count==1000 && page.records.count==50)
    print("Usage checks passed: both provider formats, missing/invalid usage, duplicate completion, failure/cancellation, reopen, pagination; 1,000 records = \(page.bytes) bytes")
}

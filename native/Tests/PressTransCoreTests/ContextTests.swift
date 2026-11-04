import CoreGraphics
import Foundation
import PressTransCore
@main enum CoreChecks {
    static func main() async throws {
        try await checkOCR()
        let policy=TranslationPolicy(targetLanguage:"Japanese",explanationLanguage:"French",sameLanguageTranslate:true,alternateLanguage:"Korean").prompt
        precondition(policy.contains("Japanese") && policy.contains("French") && policy.contains("Korean"))
        precondition(policy.contains("first translate it into alternateLanguage"))
        precondition(TranslationPolicy().prompt.contains("do not force a translation"))
        precondition(ServiceEndpoint.completionURL("https://api.deepseek.com/")?.absoluteString == "https://api.deepseek.com/chat/completions")
        precondition(ServiceEndpoint.completionURL("https://host.example/v1/chat/completions/")?.path == "/v1/chat/completions")
        precondition(ServiceEndpoint.completionURL("https://host.example/compatible-mode/v1")?.path == "/compatible-mode/v1/chat/completions")
        precondition(ServiceEndpoint.completionURL("http://127.0.0.1:1234/v1") != nil)
        for invalid in ["http://example.com/v1","https://key@example.com","https://example.com?key=secret","file:///tmp/key",""] {precondition(ServiceEndpoint.completionURL(invalid)==nil)}
        for sample in ["résumé", "中文术语", "日本語", "안녕하세요", "مرحبا", "🙂"] {
            let match=TextTarget.range(in:sample,atUTF16:0)
            precondition(match != nil && match!.length>0)
        }
        precondition(TextTarget.range(in:"hello world",atUTF16:5)==nil)
        precondition(TextTarget.range(in:"hello",atUTF16:100)==nil)
        print("Multilingual policy and Unicode target checks passed")
        var gesture=PressGesture()
        gesture.down(at:.zero,clicks:1,time:1)
        precondition(gesture.pressure(200,time:1.1)==nil)
        precondition(gesture.pressure(500,time:1.2)==CGPoint.zero)
        precondition(gesture.pressure(600,time:1.3)==nil)
        gesture.down(at:.zero,clicks:2,time:2);precondition(gesture.pressure(700,time:2.1)==nil)
        gesture.down(at:.zero,clicks:1,time:3);gesture.move(to:CGPoint(x:30,y:0));precondition(gesture.pressure(700,time:3.1)==nil)
        gesture.down(at:.zero,clicks:1,time:4);precondition(gesture.pressure(700,time:5)==nil)
        gesture.down(at:.zero,clicks:1,time:6);gesture.up();precondition(gesture.pressure(700,time:6.1)==nil)
        print("Pressure detector checks passed: light click, one-shot, multi-click, drag, hold, release")
        let text=String(repeating:"a",count:10000)+"DM limits"+String(repeating:"b",count:10000)
        let result=ContextBuilder.make(selection:"DM limits",surrounding:text,sourceApp:"Test")!
        precondition(result.context.contains("DM limits") && result.context.count==1809 && !result.limited)
        precondition(ContextBuilder.make(selection:"DM",surrounding:"Other text",sourceApp:"Test")!.limited)
        precondition(ContextBuilder.make(selection:" ",surrounding:nil,sourceApp:"Test")==nil)
        precondition(ContextBuilder.make(selection:String(repeating:"a",count:1001),surrounding:nil,sourceApp:"Test")==nil)
        let parts=AnswerParts.split("私信额度\r\n\r\n没有说明具体额度。")
        precondition(parts.meaning=="私信额度" && parts.explanation=="没有说明具体额度。")
        var parser=SSEParser()
        precondition(parser.line("data: 中文")==nil);precondition(parser.line("data: 第二行")==nil);precondition(parser.line("")=="中文\n第二行")
        precondition(parser.line(": heartbeat")==nil);precondition(parser.line("")==nil)
        precondition(parser.line("data: [DONE]")==nil);precondition(parser.line("")=="[DONE]")
        print("4 Swift core checks passed: context budget, limited input, answer hierarchy, SSE framing")
        if let path = ProcessInfo.processInfo.environment["PRESSTRANS_DICTIONARY"] {
            let dictionary = try OfflineDictionary(path:path)
            let cases = ["BOOK", "  book!  ", "taking off", "took off", "turned it down", "looked after", "children", "books", "recieve", "DM limits", "That’s a hill to die on.", "zzzzxxyy", "", String(repeating:"unrecognized ",count:80)]
            for input in cases {
                let start = Date()
                let result = await dictionary.lookup(input)
                print("lookup \(String(input.prefix(40))) → \(result.kind.rawValue): \(result.entries.map(\.term).joined(separator:", ")) [\(Int(Date().timeIntervalSince(start)*1000)) ms]")
                if input == "BOOK" || input == "  book!  " { precondition(result.kind == .exact && result.entries.first?.term.lowercased() == "book") }
                if input == "took off" { precondition(result.entries.contains(where:{$0.term == "take off"})) }
                if input == "turned it down" { precondition(result.kind == .phrase && result.entries.first?.term == "turn down") }
                if input == "looked after" { precondition(result.entries.first?.term == "look after") }
                if input == "recieve" { precondition(result.kind == .suggestion && result.entries.contains(where:{$0.term == "receive"})) }
                if input == "zzzzxxyy" || input.isEmpty { precondition(result.kind == .missing && result.entries.isEmpty) }
                precondition(result.entries.count <= 5)
            }
            let events = UpdateRecorder()
            await LookupEngine.run(local:{await dictionary.lookup("book")},online:nil) {await events.add($0)}
            var updates = await events.values
            precondition(updates.count == 1 && updates[0].offline && updates[0].complete && !updates[0].loading)
            await events.clear()
            await LookupEngine.run(local:{await dictionary.lookup("book")},online:{sink in
                await sink("不完整的在线输出")
                throw CocoaError(.fileReadUnknown)
            }) {await events.add($0)}
            updates=await events.values
            precondition(updates.count == 3 && updates[0].offline && !updates[1].offline)
            precondition(updates.last!.offline && updates.last!.complete && updates.last!.text == updates.first!.text && !updates.last!.loading)
            await events.clear()
            await LookupEngine.run(local:{await dictionary.lookup("book")},online:{sink in await sink("书\n\n这里用作名词。")}) {await events.add($0)}
            updates=await events.values
            precondition(updates.last!.text == "书\n\n这里用作名词。" && updates.last!.complete && !updates.last!.offline)
            await events.clear()
            let cancelled=Task {
                await LookupEngine.run(local:{try? await Task.sleep(nanoseconds:50_000_000);return await dictionary.lookup("book")},online:nil) {await events.add($0)}
            }
            cancelled.cancel(); await cancelled.value
            let cancelledUpdates=await events.values; precondition(cancelledUpdates.isEmpty)
            print("Lookup pipeline checks passed: no credentials, partial failure fallback, online completion, cancellation")
            var timings:[Double]=[]
            for _ in 0..<100 {
                let start=Date(); _ = await dictionary.lookup("taking off"); timings.append(Date().timeIntervalSince(start)*1000)
            }
            timings.sort()
            print("Dictionary checks passed; warmed phrase p50=\(timings[50]) ms, p95=\(timings[95]) ms")
        }

    }
}

actor UpdateRecorder {
    var values:[LookupUpdate]=[]
    func add(_ value:LookupUpdate) {values.append(value)}
    func clear() {values=[]}
}

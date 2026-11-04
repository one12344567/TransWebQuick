import Foundation
import CoreFoundation

public struct TokenUsage:Sendable,Equatable {
    public let input:Int
    public let output:Int
    public let total:Int
    public let cached:Int?
    public let reasoning:Int?
    public init(input:Int,output:Int,total:Int,cached:Int?=nil,reasoning:Int?=nil) {
        self.input=input;self.output=output;self.total=total;self.cached=cached;self.reasoning=reasoning
    }
    /// Provider counters are snapshots, never deltas. Missing usage is unknown, not zero.
    public static func parse(_ value:Any?)->TokenUsage? {
        guard let object=value as? [String:Any] else{return nil}
        func count(_ value:Any?)->Int? {
            guard let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID() else{return nil}
            let value=number.doubleValue
            guard value.isFinite,value>=0,value<=1_000_000_000,value.rounded(.down)==value else{return nil}
            return Int(value)
        }
        guard let input=count(object["prompt_tokens"]),let output=count(object["completion_tokens"]) else{return nil}
        let total=count(object["total_tokens"]) ?? input+output
        guard total>=input,total>=output else{return nil}
        let prompt=object["prompt_tokens_details"] as? [String:Any]
        let completion=object["completion_tokens_details"] as? [String:Any]
        let cached=count(object["prompt_cache_hit_tokens"]) ?? count(prompt?["cached_tokens"])
        let reasoning=count(completion?["reasoning_tokens"])
        return TokenUsage(input:input,output:output,total:total,cached:cached.flatMap{$0<=input ? $0:nil},reasoning:reasoning.flatMap{$0<=output ? $0:nil})
    }
}

/// Decodes usage before choices so OpenAI's empty-choices usage chunk is retained.
public struct CompletionChunk {
    public let content:String?
    public let finishReason:String?
    public let usage:TokenUsage?
    public init(data:String) throws {
        guard let object=try JSONSerialization.jsonObject(with:Data(data.utf8)) as? [String:Any] else{throw CocoaError(.fileReadCorruptFile)}
        usage=TokenUsage.parse(object["usage"])
        let choice=(object["choices"] as? [[String:Any]])?.first
        content=(choice?["delta"] as? [String:Any])?["content"] as? String
        finishReason=choice?["finish_reason"] as? String
    }
}

import Foundation

public enum ServiceEndpoint {
    /// Only explicit HTTPS services or loopback development servers; no credentials/query in URLs.
    public static func completionURL(_ input:String)->URL? {
        let value=input.trimmingCharacters(in:.whitespacesAndNewlines)
        guard var parts=URLComponents(string:value),let host=parts.host,!host.isEmpty,
              parts.user == nil,parts.password == nil,parts.query == nil,parts.fragment == nil,
              parts.scheme == "https" || (parts.scheme == "http" && ["localhost","127.0.0.1","[::1]","::1"].contains(host)) else{return nil}
        var path=parts.path
        while path.hasSuffix("/"){path.removeLast()}
        if !path.hasSuffix("/chat/completions"){path += "/chat/completions"}
        parts.path=path
        return parts.url
    }
}

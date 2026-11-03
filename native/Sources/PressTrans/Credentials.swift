import Foundation

enum Credentials {
    private struct Configuration:Codable {let apiKey:String}
    static var directory:URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PressTrans",isDirectory:true)
    }
    private static var file:URL {directory.appendingPathComponent("provider.json")}
    static func load()->String? {
        guard let data=try? Data(contentsOf:file),data.count<8192,
              let configuration=try? JSONDecoder().decode(Configuration.self,from:data),!configuration.apiKey.isEmpty else{return nil}
        return configuration.apiKey
    }
    static func save(_ key:String)->Bool {
        let cleaned=key.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !cleaned.isEmpty,cleaned.count<=4096,!cleaned.contains("\n"),!cleaned.contains("\r") else{return false}
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
            // Explicit 0600 temporary file before writing sensitive bytes; same-directory atomic rename.
            let temporary=directory.appendingPathComponent(UUID().uuidString+".tmp")
            defer {try? FileManager.default.removeItem(at:temporary)}
            guard FileManager.default.createFile(atPath:temporary.path,contents:nil,attributes:[.posixPermissions:0o600]) else{return false}
            let handle=try FileHandle(forWritingTo:temporary)
            do {try handle.write(contentsOf:JSONEncoder().encode(Configuration(apiKey:cleaned)));try handle.synchronize();try handle.close()}
            catch {try? handle.close();throw error}
            if FileManager.default.fileExists(atPath:file.path) {_ = try FileManager.default.replaceItemAt(file,withItemAt:temporary)}
            else {try FileManager.default.moveItem(at:temporary,to:file)}
            return true
        } catch {return false}
    }
}

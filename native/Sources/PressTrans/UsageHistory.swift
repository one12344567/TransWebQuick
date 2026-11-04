import Foundation
import Combine
import PressTransCore

extension Notification.Name {static let usageHistoryChanged=Notification.Name("PressTransUsageHistoryChanged")}
@MainActor final class UsageHistory:ObservableObject {
    static let shared=UsageHistory()
    @Published private(set) var unavailable=false
    private let store:Result<UsageLedger,Error>
    private init() {
        store=Result {
            let directory=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("PressTrans",isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            return try UsageLedger(path:directory.appendingPathComponent("usage.sqlite").path)
        }
        if case .failure=store {unavailable=true}
    }
    func save(_ record:UsageRecord) async {
        do {try await store.get().save(record);unavailable=false}
        catch {unavailable=true}
        NotificationCenter.default.post(name:.usageHistoryChanged,object:nil)
    }
    func page(offset:Int) async throws ->UsagePage {try await store.get().page(offset:offset)}
}

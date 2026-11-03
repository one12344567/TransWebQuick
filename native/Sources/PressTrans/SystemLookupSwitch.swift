import Foundation

/// Backs up only the three observed lookup preferences, never force/haptic settings.
/// Original missing values remain missing. Recovery is durable before changing anything.
struct SystemLookupSwitch {
    private static let backupKey="systemLookupRecoveryV1"
    private static let phaseKey="systemLookupRecoveryPhaseV1"
    private static let entries:[(String,String)] = [
        (kCFPreferencesAnyApplication as String,"com.apple.trackpad.forceClick"),
        ("com.apple.AppleMultitouchTrackpad","TrackpadThreeFingerTapGesture"),
        ("com.apple.driver.AppleBluetoothMultitouch.trackpad","TrackpadThreeFingerTapGesture")]
    static var hasBackup:Bool {UserDefaults.standard.array(forKey:backupKey) != nil}
    private static func read(_ domain:String,_ key:String)->Any? {
        CFPreferencesCopyValue(key as CFString,domain as CFString,kCFPreferencesCurrentUser,kCFPreferencesAnyHost)
    }
    private static func write(_ domain:String,_ key:String,_ value:Any?)->Bool {
        CFPreferencesSetValue(key as CFString,value as CFPropertyList?,domain as CFString,kCFPreferencesCurrentUser,kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(domain as CFString,kCFPreferencesCurrentUser,kCFPreferencesAnyHost)
    }
    static func disable() -> Bool {
        guard !hasBackup else{return false}
        let backup=entries.map {domain,key -> [String:Any] in
            var row:[String:Any]=["domain":domain,"key":key]
            if let value=read(domain,key) {row["value"]=value}
            return row
        }
        UserDefaults.standard.set(backup,forKey:backupKey)
        UserDefaults.standard.set("prepared",forKey:phaseKey)
        guard UserDefaults.standard.synchronize() else{return false}
        for (index,entry) in entries.enumerated() {
            let value:NSNumber=index==0 ? NSNumber(value:false):NSNumber(value:0)
            guard write(entry.0,entry.1,value) else {_ = restore(preserveExternalChanges:false);return false}
        }
        guard entries.allSatisfy({(read($0.0,$0.1) as? NSNumber)?.intValue==0}) else {_ = restore(preserveExternalChanges:false);return false}
        UserDefaults.standard.set("disabled",forKey:phaseKey);UserDefaults.standard.synchronize()
        return true
    }
    /// nil: nothing to restore; true: original values restored; false: external settings preserved or restore failed.
    static func restore(preserveExternalChanges:Bool=true)->Bool? {
        guard let backup=UserDefaults.standard.array(forKey:backupKey) as? [[String:Any]] else{return nil}
        if preserveExternalChanges && UserDefaults.standard.string(forKey:phaseKey)=="disabled" && !entries.allSatisfy({(read($0.0,$0.1) as? NSNumber)?.intValue==0}) {
            UserDefaults.standard.removeObject(forKey:backupKey);UserDefaults.standard.removeObject(forKey:phaseKey);UserDefaults.standard.synchronize();return false
        }
        UserDefaults.standard.set("restoring",forKey:phaseKey);UserDefaults.standard.synchronize()
        var success=true
        for row in backup {
            guard let domain=row["domain"] as? String, let key=row["key"] as? String,
                  entries.contains(where:{$0.0==domain && $0.1==key}) else{success=false;continue}
            if !write(domain,key,row["value"]) {success=false}
        }
        if success {UserDefaults.standard.removeObject(forKey:backupKey);UserDefaults.standard.removeObject(forKey:phaseKey);UserDefaults.standard.synchronize()}
        return success
    }
}

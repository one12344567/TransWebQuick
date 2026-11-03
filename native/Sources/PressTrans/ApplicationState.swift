import AppKit
import ApplicationServices

@MainActor final class ApplicationState:ObservableObject {
    @Published var trusted=AXIsProcessTrusted()
    @Published var menuVisible = !UserDefaults.standard.bool(forKey:"menuBarHidden")
    @Published var forceEnabled=false
    @Published var forceStatus="当前由系统处理重按查词。"
    @Published var gestureCount=0
    let pressure=PressureInput()
    var onForce:((CGPoint)->Void)?
    func refreshPermission() {
        let current=AXIsProcessTrusted()
        if trusted != current {trusted=current}
        if !current && forceEnabled {setForce(false);forceStatus="权限不可用，已停止 PressTrans 重按并尝试恢复系统设置。"}
    }
    func setForce(_ enabled:Bool) {
        if !enabled {
            pressure.stop();forceEnabled=false
            let restored=SystemLookupSwitch.restore()
            forceStatus=restored == false ? (SystemLookupSwitch.hasBackup ? "系统设置恢复失败，请打开触控板设置恢复查词。":"已停止 PressTrans，保留你后来更改的系统设置。") : "已恢复原来的系统查词设置。"
            return
        }
        refreshPermission()
        guard trusted else{forceStatus="需要先修复辅助功能授权，系统查词保持原样。";return}
        guard !forceEnabled else{return}
        guard pressure.start(action:{[weak self] point in
            guard let self,self.forceEnabled else{return}
            self.refreshPermission();guard self.trusted else{return}
            self.gestureCount+=1;self.onForce?(point)
        }) else {forceStatus="无法启动压力监听，系统查词保持原样。";return}
        guard SystemLookupSwitch.disable() else {pressure.stop();forceStatus="未能保存或切换系统设置，未启用重按。";return}
        forceEnabled=true;forceStatus="PressTrans 重按已启用；关闭或退出会恢复原设置。"
    }
    func recover() {
        if let restored=SystemLookupSwitch.restore() {forceStatus=restored ? "已恢复上次退出前的系统查词设置。":"检测到系统设置已变化，未覆盖你的修改。"}
    }
}

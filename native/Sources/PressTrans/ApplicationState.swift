import AppKit
import ApplicationServices
#if CAPTURE_ACCEPTANCE
import ScreenCaptureKit
import PressTransCore
#endif

@MainActor final class ApplicationState:ObservableObject {
    @Published var trusted=AXIsProcessTrusted()
    @Published var menuVisible = !UserDefaults.standard.bool(forKey:"menuBarHidden")
    @Published var forceEnabled=false
    @Published var forceStatus="当前由系统处理重按查词。"
    @Published var gestureCount=0
    @Published var captureStatus="尚未查询。"
    let pressure=PressureInput()
    var onForce:((CGPoint)->Void)?
    var onCaptureTest:(()->Void)?
#if CAPTURE_ACCEPTANCE
    @Published var acceptanceImage:NSImage?
    func inspectCapture(pid:pid_t,x:Double,y:Double,selection:Bool,ocr:Bool) {
        captureStatus="检测中…"
        Task {
            do {
                if ocr {
                    let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:false)
                    guard let window=content.windows.first(where:{$0.owningApplication?.processID==pid && $0.windowLayer==0 && $0.frame.width>400}),CGPreflightScreenCaptureAccess() else{throw ScreenTextFailure.permission}
                    let point=CGPoint(x:window.frame.minX+window.frame.width*x/100,y:window.frame.minY+window.frame.height*y/100)
                    let region=CGRect(x:point.x-320,y:point.y-130,width:640,height:260).intersection(window.frame)
                    let config=SCStreamConfiguration();config.sourceRect=region.offsetBy(dx:-window.frame.minX,dy:-window.frame.minY);config.width=Int(region.width*2);config.height=Int(region.height*2);config.showsCursor=false;config.ignoreShadowsSingleWindow=true;config.ignoreGlobalClipSingleWindow=true
                    let began=Date()
                    let image=try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:window),configuration:config)
                    acceptanceImage=NSImage(cgImage:image,size:NSSize(width:320,height:130))
                    let result=try await Task.detached {try ScreenTextRecognizer.recognize(image:image,region:region,point:point)}.value
                    captureStatus="窗口 OCR · \(Int(Date().timeIntervalSince(began)*1000)) ms\n目标：\(result.word)\n上下文：\(result.line)";return
                }
                let result=try await Task.detached {
                    let root=AXUIElementCreateApplication(pid)
                    guard let raw=TextCapture.value(root,kAXFocusedWindowAttribute),CFGetTypeID(raw)==AXUIElementGetTypeID() else{throw CaptureFailure.unsupported}
                    let window=raw as! AXUIElement
                    guard let position=TextCapture.value(window,kAXPositionAttribute),let size=TextCapture.value(window,kAXSizeAttribute),CFGetTypeID(position)==AXValueGetTypeID(),CFGetTypeID(size)==AXValueGetTypeID() else{throw CaptureFailure.unsupported}
                    var origin=CGPoint.zero,dimensions=CGSize.zero
                    AXValueGetValue(position as! AXValue,.cgPoint,&origin);AXValueGetValue(size as! AXValue,.cgSize,&dimensions)
                    let name=NSRunningApplication(processIdentifier:pid)?.localizedName ?? "应用"
                    let began=Date()
                    let capture=try TextCapture.capture(processID:pid,appName:name,point:selection ? nil:CGPoint(x:origin.x+dimensions.width*x/100,y:origin.y+dimensions.height*y/100))
                    return "\(name) · \(capture.context.limited ? "仅选词":"有上下文") · bounds=\(capture.anchor != nil) · \(Int(Date().timeIntervalSince(began)*1000)) ms\n目标：\(capture.context.selection)\n上下文：\(capture.context.context.prefix(300))"
                }.value
                captureStatus=result
            } catch {captureStatus=error.localizedDescription}
        }
    }
#endif
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

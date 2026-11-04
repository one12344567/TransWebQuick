import AppKit
import SwiftUI
import Carbon
import ApplicationServices
import PressTransCore

@main struct PressTransApp {
    static func main() {
        let app=NSApplication.shared
        let delegate=AppDelegate(); app.delegate=delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    var item:NSStatusItem!, panel:PanelController!, window:NSWindow?
    var hotkey:EventHotKeyRef?, pointerHotkey:EventHotKeyRef?, eventHandler:EventHandlerRef?
    var captureTask:Task<Void,Never>?
    let state=ApplicationState()
    var languageObserver:NSObjectProtocol?
    var permissionTimer:Timer?
    var terminateSignal:DispatchSourceSignal?
    func applicationDidFinishLaunching(_ notification:Notification) {
        panel=PanelController()
        state.recover();state.onForce={[weak self] point in self?.performLookup(at:point)}
        state.onCaptureTest={[weak self] in
            guard let self else{return}
            self.hideSettings();self.captureTask?.cancel()
            self.captureTask=Task { [weak self] in
                try? await Task.sleep(nanoseconds:5_000_000_000)
                guard !Task.isCancelled else{return}
                self?.performLookup(at:NSEvent.mouseLocation)
            }
        }
        signal(SIGTERM,SIG_IGN)
        terminateSignal=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
        terminateSignal?.setEventHandler{NSApp.terminate(nil)};terminateSignal?.resume()
        let mainMenu=NSMenu(), appItem=NSMenuItem(), appMenu=NSMenu()
        mainMenu.addItem(appItem);appItem.submenu=appMenu
        let settingsItem=NSMenuItem(title:L("PressTrans 设置…"),action:#selector(settings),keyEquivalent:",");settingsItem.target=self;appMenu.addItem(settingsItem)
        let closeItem=NSMenuItem(title:L("关闭窗口"),action:#selector(closeSettings),keyEquivalent:"w");closeItem.target=self;appMenu.addItem(closeItem)
        appMenu.addItem(.separator());appMenu.addItem(NSMenuItem(title:L("退出 PressTrans"),action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"));NSApp.mainMenu=mainMenu
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.image=PressIcon.menuImage()
        let menu=NSMenu()
        let title=NSMenuItem(title:L("PressTrans · 按压翻译"),action:nil,keyEquivalent:""); title.isEnabled=false; menu.addItem(title)
        add(menu,L("翻译选中文字  ⌥⇧T"),#selector(lookup)); add(menu,L("手动查询…"),#selector(manual)); menu.addItem(.separator())
        add(menu,L("预览原生浮窗"),#selector(preview)); add(menu,L("设置与使用指南…"),#selector(settings)); menu.addItem(.separator()); add(menu,L("退出 PressTrans"),#selector(quit))
        add(menu,L("隐藏菜单栏图标"),#selector(hideMenuBar))
        item.menu=menu;item.isVisible=state.menuVisible
        var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{ _,event,userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let owner=Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            var key=EventHotKeyID()
            GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&key)
            let pointer=key.id==2
            Task { @MainActor in if pointer {owner.performLookup(at:NSEvent.mouseLocation)} else {owner.lookup()} }; return noErr
        },1,&spec,Unmanaged.passUnretained(self).toOpaque(),&eventHandler)
        let status=RegisterEventHotKey(UInt32(kVK_ANSI_T),UInt32(optionKey|shiftKey),EventHotKeyID(signature:0x5054524e,id:1),GetApplicationEventTarget(),0,&hotkey)
        if status != noErr { panel.model.message=L("⌥⇧T 已被其他应用占用，请从菜单栏发起查询。") }
        RegisterEventHotKey(UInt32(kVK_ANSI_P),UInt32(optionKey|shiftKey),EventHotKeyID(signature:0x5054524e,id:2),GetApplicationEventTarget(),0,&pointerHotkey)
        languageObserver=NotificationCenter.default.addObserver(forName:.interfaceLanguageChanged,object:nil,queue:.main){[weak self] _ in
            Task { @MainActor in
                func refresh(_ menu:NSMenu?) {for item in menu?.items ?? [] {item.title=L(item.title);refresh(item.submenu)}}
                refresh(NSApp.mainMenu);refresh(self?.item.menu)
                self?.panel.model.clear()
            }
        }
        settings()
    }
    func add(_ menu:NSMenu,_ title:String,_ action:Selector) { let entry=NSMenuItem(title:title,action:action,keyEquivalent:"");entry.target=self;menu.addItem(entry) }
    @objc func lookup() {performLookup(at:nil)}
    func performLookup(at point:CGPoint?) {
        state.refreshPermission()
        state.captureStatus=L("正在获取查询目标…")
        captureTask?.cancel()
        guard let foreground=NSWorkspace.shared.frontmostApplication, foreground.bundleIdentifier != Bundle.main.bundleIdentifier else {
            panel.model.clear();panel.model.message=CaptureFailure.noSelection.localizedDescription;panel.show();return
        }
        let pid=foreground.processIdentifier, name=foreground.localizedName ?? L("当前应用")
        let began=Date()
        let axPoint=point.map{CGPoint(x:$0.x,y:(NSScreen.screens.first?.frame.maxY ?? 0)-$0.y)}
        let screen=point.flatMap{location in NSScreen.screens.first(where:{$0.frame.contains(location)})}.map{screen in
            CGRect(x:screen.frame.minX,y:(NSScreen.screens.first?.frame.maxY ?? 0)-screen.frame.maxY,width:screen.frame.width,height:screen.frame.height)
        }
        captureTask=Task {
            do {
                let result:CaptureResult
                do {result=try await Task.detached(priority:.userInitiated){try TextCapture.capture(processID:pid,appName:name,point:axPoint)}.value}
                catch CaptureFailure.secure {throw CaptureFailure.secure}
                catch CaptureFailure.permission {throw CaptureFailure.permission}
                catch {
                    try Task.checkCancellation()
                    guard ScreenTextCapture.enabled,let axPoint,let screen,NSWorkspace.shared.frontmostApplication?.processIdentifier==pid else{throw error}
                    result=try await ScreenTextCapture.shared.capture(processID:pid,appName:name,point:axPoint,screen:screen)
                }
                guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == result.processID else{return}
                state.captureStatus="\(result.context.sourceApp) · \(result.context.limited ? "仅目标文字":"含上下文") · \(Int(Date().timeIntervalSince(began)*1000)) ms\n\(result.context.selection.prefix(80))"
                panel.model.show(result.context);panel.show(anchor:result.anchor)
            } catch {
                guard !Task.isCancelled else{return}
                state.captureStatus="\(name)：\(error.localizedDescription)"
                panel.model.clear();panel.model.message=error.localizedDescription;panel.show()
            }
        }
    }
    @objc func preview() { panel.model.demo();panel.show() }
    @objc func settings() { showWindow(manual:false) }
    @objc func manual() { showWindow(manual:true) }
    func showWindow(manual:Bool) {
        if window == nil {
            window=NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:590),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window?.minSize=NSSize(width:760,height:560)
            window?.title="PressTrans";window?.isReleasedWhenClosed=false;window?.delegate=self;window?.center()
        }
        window?.contentView=NSHostingView(rootView:SettingsView(appState:state,menuVisibility:{[weak self] visible in self?.setMenuVisible(visible)},manualMode:manual,changeMode:{[weak self] in self?.showWindow(manual:!manual)},preview:{[weak self] in self?.hideSettings();self?.preview()},translate:{[weak self] text in
            guard let self,let context=ContextBuilder.make(selection:text,surrounding:nil,sourceApp:L("手动输入")) else{return}
            self.hideSettings();self.panel.model.show(context);self.panel.show()
        }))
        NSApp.setActivationPolicy(.regular)
        state.refreshPermission();permissionTimer?.invalidate()
        permissionTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in Task { @MainActor in self?.state.refreshPermission() }}
        NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)
    }
    func setMenuVisible(_ visible:Bool) {state.menuVisible=visible;item.isVisible=visible;UserDefaults.standard.set(!visible,forKey:"menuBarHidden")}
    @objc func hideMenuBar() {setMenuVisible(false)}
    @objc func closeSettings() {window?.close()}
    func hideSettings() {window?.orderOut(nil);permissionTimer?.invalidate();permissionTimer=nil;NSApp.setActivationPolicy(.accessory)}
    func windowWillClose(_ notification:Notification) {hideSettings()}
    func applicationDidBecomeActive(_ notification:Notification) {state.refreshPermission()}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {settings();return true}
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification:Notification) { captureTask?.cancel();panel.model.cancel();permissionTimer?.invalidate();state.setForce(false);if let hotkey{UnregisterEventHotKey(hotkey)};if let pointerHotkey{UnregisterEventHotKey(pointerHotkey)};if let eventHandler{RemoveEventHandler(eventHandler)} }
}

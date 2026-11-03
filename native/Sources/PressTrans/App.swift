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
    var hotkey:EventHotKeyRef?, eventHandler:EventHandlerRef?
    var captureTask:Task<Void,Never>?
    let state=ApplicationState()
    var permissionTimer:Timer?
    var terminateSignal:DispatchSourceSignal?
    func applicationDidFinishLaunching(_ notification:Notification) {
        panel=PanelController()
        state.recover();state.onForce={[weak self] point in self?.performLookup(at:point)}
        signal(SIGTERM,SIG_IGN)
        terminateSignal=DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
        terminateSignal?.setEventHandler{NSApp.terminate(nil)};terminateSignal?.resume()
        let mainMenu=NSMenu(), appItem=NSMenuItem(), appMenu=NSMenu()
        mainMenu.addItem(appItem);appItem.submenu=appMenu
        let settingsItem=NSMenuItem(title:"PressTrans 设置…",action:#selector(settings),keyEquivalent:",");settingsItem.target=self;appMenu.addItem(settingsItem)
        appMenu.addItem(.separator());appMenu.addItem(NSMenuItem(title:"退出 PressTrans",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"));NSApp.mainMenu=mainMenu
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.image=NSImage(systemSymbolName:"hand.point.up.left",accessibilityDescription:"PressTrans")
        let menu=NSMenu()
        let title=NSMenuItem(title:"PressTrans · 按压翻译",action:nil,keyEquivalent:""); title.isEnabled=false; menu.addItem(title)
        add(menu,"翻译选中文字  ⌥⇧T",#selector(lookup)); add(menu,"手动查询…",#selector(manual)); menu.addItem(.separator())
        add(menu,"预览原生浮窗",#selector(preview)); add(menu,"设置与使用指南…",#selector(settings)); menu.addItem(.separator()); add(menu,"退出 PressTrans",#selector(quit))
        add(menu,"隐藏菜单栏图标",#selector(hideMenuBar))
        item.menu=menu;item.isVisible=state.menuVisible
        var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{ _,_,userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let owner=Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in owner.lookup() }; return noErr
        },1,&spec,Unmanaged.passUnretained(self).toOpaque(),&eventHandler)
        let status=RegisterEventHotKey(UInt32(kVK_ANSI_T),UInt32(optionKey|shiftKey),EventHotKeyID(signature:0x5054524e,id:1),GetApplicationEventTarget(),0,&hotkey)
        if status != noErr { panel.model.message="⌥⇧T 已被其他应用占用，请从菜单栏发起查询。" }
        settings()
    }
    func add(_ menu:NSMenu,_ title:String,_ action:Selector) { let entry=NSMenuItem(title:title,action:action,keyEquivalent:"");entry.target=self;menu.addItem(entry) }
    @objc func lookup() {performLookup(at:nil)}
    func performLookup(at point:CGPoint?) {
        state.refreshPermission()
        captureTask?.cancel()
        guard let foreground=NSWorkspace.shared.frontmostApplication, foreground.bundleIdentifier != Bundle.main.bundleIdentifier else {
            panel.model.clear();panel.model.message=CaptureFailure.noSelection.localizedDescription;panel.show();return
        }
        let pid=foreground.processIdentifier, name=foreground.localizedName ?? "当前应用"
        let axPoint=point.map{CGPoint(x:$0.x,y:(NSScreen.screens.first?.frame.maxY ?? 0)-$0.y)}
        captureTask=Task {
            do {
                let result=try await Task.detached(priority:.userInitiated){try TextCapture.capture(processID:pid,appName:name,point:axPoint)}.value
                guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == result.processID else{return}
                panel.model.show(result.context);panel.show(anchor:result.anchor)
            } catch {
                guard !Task.isCancelled else{return}
                panel.model.clear();panel.model.message=error.localizedDescription;panel.show()
            }
        }
    }
    @objc func preview() { panel.model.demo();panel.show() }
    @objc func settings() { showWindow(manual:false) }
    @objc func manual() { showWindow(manual:true) }
    func showWindow(manual:Bool) {
        if window == nil {
            window=NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:760),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
            window?.title="PressTrans";window?.isReleasedWhenClosed=false;window?.delegate=self;window?.center()
        }
        window?.contentView=NSHostingView(rootView:SettingsView(appState:state,menuVisibility:{[weak self] visible in self?.setMenuVisible(visible)},manualMode:manual,changeMode:{[weak self] in self?.showWindow(manual:!manual)},preview:{[weak self] in self?.hideSettings();self?.preview()},translate:{[weak self] text in
            guard let self,let context=ContextBuilder.make(selection:text,surrounding:nil,sourceApp:"手动输入") else{return}
            self.hideSettings();self.panel.model.show(context);self.panel.show()
        }))
        NSApp.setActivationPolicy(.regular)
        state.refreshPermission();permissionTimer?.invalidate()
        permissionTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in Task { @MainActor in self?.state.refreshPermission() }}
        NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)
    }
    func setMenuVisible(_ visible:Bool) {state.menuVisible=visible;item.isVisible=visible;UserDefaults.standard.set(!visible,forKey:"menuBarHidden")}
    @objc func hideMenuBar() {setMenuVisible(false)}
    func hideSettings() {window?.orderOut(nil);permissionTimer?.invalidate();permissionTimer=nil;NSApp.setActivationPolicy(.accessory)}
    func windowWillClose(_ notification:Notification) {hideSettings()}
    func applicationDidBecomeActive(_ notification:Notification) {state.refreshPermission()}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {settings();return true}
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification:Notification) { captureTask?.cancel();panel.model.cancel();permissionTimer?.invalidate();state.setForce(false);if let hotkey{UnregisterEventHotKey(hotkey)};if let eventHandler{RemoveEventHandler(eventHandler)} }
}
final class SettingsState:ObservableObject {
    @Published var key=""
    @Published var status=""
    @Published var text=""
    @Published var online=TranslationPreferences.onlineEnabled
    @Published var advanced=false
}
@MainActor struct SettingsView:View {
    @ObservedObject var appState:ApplicationState
    var menuVisibility:(Bool)->Void
    var manualMode:Bool;var changeMode:()->Void;var preview:()->Void;var translate:(String)->Void
    @ObservedObject private var state=SettingsState()
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:22) {
            HStack(spacing:12) {
                Image(systemName:"hand.point.up.left.fill").font(.system(size:27)).foregroundStyle(.green).frame(width:52,height:52).background(.green.opacity(0.08),in:RoundedRectangle(cornerRadius:15))
                VStack(alignment:.leading,spacing:4){Text("PressTrans").font(.system(size:27,weight:.semibold,design:.rounded));Text("选中，就读懂。").font(.system(size:13)).foregroundStyle(.secondary)}
                Spacer();Text("原生预览版").font(.system(size:11)).foregroundStyle(.secondary)
            }
            if manualMode {
                Text("输入一段英文").font(.headline)
                TextEditor(text:$state.text).font(.system(size:15)).frame(height:150).padding(8).background(.quaternary,in:RoundedRectangle(cornerRadius:12))
                Button("查询释义"){translate(state.text)}.buttonStyle(.borderedProminent).disabled(state.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || state.text.unicodeScalars.count>1000)
                Text("最多 1000 个字符。这里只使用你输入的文字。").font(.caption).foregroundStyle(.secondary)
                Button("返回设置",action:changeMode)
            } else {
                VStack(alignment:.leading,spacing:12) {
                    Label("在其他应用中选中文字，按 ⌥⇧T",systemImage:"keyboard").font(.system(size:15,weight:.medium))
                    Text("释义会出现在选区附近。原文上下文可展开查看；没有读到上下文时会明确提示。").font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
                    HStack { Label(appState.trusted ? "辅助功能已授权":"需要辅助功能权限",systemImage:appState.trusted ? "checkmark.circle.fill":"hand.raised").foregroundStyle(appState.trusted ? .green:.secondary);Spacer();Button("打开系统设置") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) };Button("重新检测"){appState.refreshPermission()} }.font(.system(size:12))
                }.padding(18).background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:16))
                if !appState.trusted {
                    Text("若系统开关已打开但这里仍未授权，请移除旧的 PressTrans 条目，再添加当前应用。开发版已改用固定签名。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Button("在 Finder 中显示当前应用") {NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])}
                }
                VStack(alignment:.leading,spacing:10) {
                    HStack {Text("重按查词").font(.headline);Spacer();Text("实验功能").font(.caption).foregroundStyle(.secondary)}
                    Picker("处理方式",selection:Binding(get:{appState.forceEnabled},set:{appState.setForce($0)})) {
                        Text("系统查词").tag(false);Text("PressTrans").tag(true)
                    }.pickerStyle(.segmented)
                    Text(appState.forceStatus).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text("全局压力读取使用 macOS 未公开接口，系统更新后可能失效。只切换查词手势，保留触感反馈；关闭或正常退出时恢复原设置。").font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    if appState.forceEnabled {Text("已识别重按：\(appState.gestureCount) 次").font(.caption).foregroundStyle(.secondary)}
                    Button("打开触控板设置") {NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)}
                }.padding(16).background(.quaternary.opacity(0.4),in:RoundedRectangle(cornerRadius:14))
                Toggle("显示菜单栏图标",isOn:Binding(get:{appState.menuVisible},set:{menuVisibility($0)}))
                Text("设置窗口打开时显示 Dock 图标；关闭后隐藏。菜单栏图标隐藏后，可从启动台或 Finder 再次打开设置。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                VStack(alignment:.leading,spacing:10) {
                    Label(DictionaryStore.available ? "英汉离线词典已就绪":"英汉离线词典未安装",systemImage:"book.closed").font(.headline)
                    Text("无需注册或配置。支持词形还原、短语匹配；离线释义不等同于整句翻译。").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Toggle("在线语境增强（可选）",isOn:$state.online).onChange(of:state.online) { _, value in TranslationPreferences.onlineEnabled=value }
                    Text("开启后，仅在查询时将所选文字及附近上下文发送给 DeepSeek；失败自动回退词典。").font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    DisclosureGroup("高级：个人 DeepSeek 账户",isExpanded:$state.advanced) {
                        VStack(alignment:.leading,spacing:8) {
                            Text(Credentials.load()==nil ? "可选配置，不影响离线查词。":"本机密钥已就绪，不显示密钥内容").font(.system(size:11)).foregroundStyle(.secondary)
                            HStack { SecureField("输入新 API Key",text:$state.key);Button("保存到本机") { state.status=Credentials.save(state.key.trimmingCharacters(in:.whitespacesAndNewlines)) ? "已保存":"保存失败";state.key="" }.disabled(state.key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
                            Text("仅保存在本机 PressTrans 数据目录，不读取系统钥匙串。").font(.system(size:11)).foregroundStyle(.secondary)
                            if !state.status.isEmpty {Text(state.status).font(.caption).foregroundStyle(.secondary)}
                        }.padding(.top,8)
                    }
                }
                Divider()
                Text("支持快捷键与可访问文本选区；实验重按会尝试读取指针下单词。网页结构适配和 OCR 尚未完成。").font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4)
                HStack { Button("试试离线查词",action:changeMode).buttonStyle(.borderedProminent);Button("预览浮窗与动画",action:preview);Spacer() }
            }
            Spacer(minLength:0)
            Text("只在主动查询时读取文本 · ECDICT 离线词库 · 配置保存在本机").font(.system(size:11)).foregroundStyle(.tertiary)
        }.padding(30).frame(maxWidth:.infinity,alignment:.leading) }.frame(width:580,height:760).background(.background)
    }
}

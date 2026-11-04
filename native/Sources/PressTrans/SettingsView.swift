import AppKit
import SwiftUI
import PressTransCore

private enum SettingsPage:String,CaseIterable,Identifiable {
    case general="通用",translation="翻译",service="服务",appearance="界面"
    var id:String {rawValue}
    var symbol:String {switch self {case .general:"slider.horizontal.3";case .translation:"character.bubble";case .service:"externaldrive.connected.to.line.below";case .appearance:"paintpalette"}}
}
private final class SettingsState:ObservableObject {
    @Published var page:SettingsPage = .translation
    @Published var key=""
    @Published var status=""
    @Published var text=""
    @Published var online=TranslationPreferences.onlineEnabled
    @Published var advanced=false
    @Published var editService=false
    @Published var manual=false
    @Published var permissions=false
    @Published var gestureDemo=false
    @Published var demoKind:FeatureDemoKind = .online
    @Published var demoReplay=0
    @Published var configured=Credentials.load() != nil
    @Published var ocr=ScreenTextCapture.enabled
    @Published var target=TranslationPreferences.target
    @Published var explanation=TranslationPreferences.explanation
    @Published var alternate=TranslationPreferences.alternate
    @Published var sameLanguage=TranslationPreferences.sameLanguageTranslate
    @Published var provider=ServicePreferences.provider
    @Published var baseURL=ServicePreferences.baseURL
    @Published var model=ServicePreferences.model
    func prepareService() {
        provider=ServicePreferences.provider;baseURL=ServicePreferences.baseURL;model=ServicePreferences.model;key="";status="";editService=true
    }
}
private struct SidebarMaterial:NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView {
        let view=NSVisualEffectView();view.material = .sidebar;view.blendingMode = .behindWindow;view.state = .followsWindowActiveState;return view
    }
    func updateNSView(_ view:NSVisualEffectView,context:Context) {}
}
@MainActor struct SettingsView:View {
    @ObservedObject var appState:ApplicationState
    var menuVisibility:(Bool)->Void
    var manualMode:Bool;var changeMode:()->Void;var preview:()->Void;var translate:(String)->Void
    @StateObject private var state=SettingsState()
    // A is the default; appearance choices live in the dedicated visual settings page.
    @AppStorage("settingsStyle") private var style="glass"
    @AppStorage("interfaceLanguage") private var interfaceLanguage="system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var paper:Bool {style == "paper"}
    private var accent:Color {Color.accentColor}
    var body:some View {
        HStack(spacing:0) {
            if !paper {
                VStack(alignment:.leading,spacing:4) {
                    ForEach(SettingsPage.allCases){page in
                        Button {state.page=page} label:{
                            Label(L(page.rawValue),systemImage:page.symbol)
                                .font(.system(size:13)).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,10)
                                .background(state.page == page ? Color.primary.opacity(0.08):.clear,in:RoundedRectangle(cornerRadius:7))
                        }.buttonStyle(.plain).accessibilityAddTraits(state.page == page ? .isSelected:[])
                    }
                    Spacer()
                }.padding(.horizontal,10).padding(.top,24).frame(width:148).background(SidebarMaterial())
                Divider()
            }
            VStack(spacing:0) {
                HStack(alignment:.center,spacing:22) {
                    if paper {
                        ForEach(SettingsPage.allCases){page in
                            Button {state.page=page} label:{
                                Text(L(page.rawValue)).font(.system(size:14,weight:state.page == page ? .semibold:.regular))
                                    .foregroundStyle(state.page == page ? .primary:.secondary)
                                    .padding(.vertical,10)
                                    .overlay(alignment:.bottom){if state.page == page {Rectangle().frame(height:1.5)}}
                            }.buttonStyle(.plain).accessibilityAddTraits(state.page == page ? .isSelected:[])
                        }
                    } else {Text(L(state.page.rawValue)).font(.system(size:23,weight:.semibold))}
                    Spacer(minLength:12)
                }.padding(.horizontal,28).padding(.top,22).padding(.bottom,16)
                ScrollView {
                    VStack(alignment:.leading,spacing:24) {
                        switch state.page {case .general:general;case .translation:translation;case .service:service;case .appearance:AppearanceView(showPopover:preview)}
                    }.frame(maxWidth:580,alignment:.leading).padding(.horizontal,28).padding(.top,6).padding(.bottom,28).frame(maxWidth:.infinity)
                }.scrollIndicators(.automatic)
            }.background(Color(nsColor:paper ? .textBackgroundColor:.windowBackgroundColor))
        }.frame(minWidth:660,minHeight:450).tint(accent)
        .animation(reduceMotion ? nil:.easeInOut(duration:0.16),value:style)
        .onAppear{state.manual=manualMode}
        .sheet(isPresented:$state.editService,onDismiss:{state.key=""}){serviceEditor}
        .sheet(isPresented:$state.manual){manual}
        .sheet(isPresented:$state.permissions){permissions}
        .sheet(isPresented:$state.gestureDemo){VStack(spacing:18){FeatureDemo(kind:.force);Button(L("完成")){state.gestureDemo=false}.keyboardShortcut(.cancelAction)}.padding(24).frame(width:450)}
    }
    private func note(_ text:String)->some View {
        Text(L(text)).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).lineSpacing(3)
    }
    private func group<Content:View>(@ViewBuilder _ content:()->Content)->some View {
        VStack(alignment:.leading,spacing:0,content:content)
            .padding(.horizontal,paper ? 0:16).padding(.vertical,paper ? 0:3)
            .background(paper ? Color.clear:Color(nsColor:.controlBackgroundColor).opacity(0.75),in:RoundedRectangle(cornerRadius:10))
            .overlay{if !paper {RoundedRectangle(cornerRadius:10).strokeBorder(.primary.opacity(0.045),lineWidth:0.5)}}
    }
    private func row<Content:View>(@ViewBuilder _ content:()->Content)->some View {
        content().frame(minHeight:36).padding(.vertical,7).frame(maxWidth:.infinity,alignment:.leading)
    }
    private var rule:some View {Divider().opacity(paper ? 0.55:0.35)}
    private var general:some View {
        Group {
            group {
                row {HStack {Text(L("界面语言"));Spacer();GlassMenuPicker(title:L("界面语言"),value:interfaceLanguage == "system" ? L("跟随系统") : interfaceLanguage == "en" ? "English" : interfaceLanguage == "zh-Hant" ? "繁體中文":"简体中文",selection:$interfaceLanguage) {
                    Text(L("跟随系统")).tag("system");Text("English").tag("en");Text("简体中文").tag("zh-Hans");Text("繁體中文").tag("zh-Hant")
                }.labelsHidden().frame(width:200).onChange(of:interfaceLanguage){_,_ in NotificationCenter.default.post(name:.interfaceLanguageChanged,object:nil)}}}
                rule
                row {HStack {Text(L("显示菜单栏图标"));Spacer();Toggle(L("显示菜单栏图标"),isOn:Binding(get:{appState.menuVisible},set:{menuVisibility($0)})).labelsHidden().toggleStyle(.switch).controlSize(.small).padding(.leading,12).frame(width:200,alignment:.leading)}}
            }
            group {
                row {HStack {Text(L("触控板重按"));Spacer();GlassMenuPicker(title:L("触控板重按"),value:appState.forceEnabled ? "PressTrans":L("系统查词"),selection:Binding(get:{appState.forceEnabled},set:{appState.setForce($0)})) {Text(L("系统查词")).tag(false);Text("PressTrans").tag(true)}.labelsHidden().frame(width:200)}}
                rule
                row {HStack {Text(L("查询选中文字"));Spacer();keycap("⌥ ⇧ T").padding(.leading,12).frame(width:200,alignment:.leading)}}
                rule
                row {HStack {Text(L("查询指针下的词"));Spacer();keycap("⌥ ⇧ P").padding(.leading,12).frame(width:200,alignment:.leading)}}
            }
            if !appState.trusted {
                HStack {note("需要先修复辅助功能授权，系统查词保持原样。");Spacer();Button(L("开启…"),action:openAccessibility)}
            }
            DisclosureGroup(L("高级与诊断"),isExpanded:$state.advanced) {
                VStack(alignment:.leading,spacing:14) {
                    note(appState.forceStatus)
                    note("重按仍为实验功能，压力检测使用未公开的系统接口。不限制应用名单：优先直接读取文字，失败时可回退到屏幕识字。受保护的输入框不支持。")
                    Text(appState.captureStatus).font(.system(size:12)).textSelection(.enabled)
                    HStack {Button(L("测试取词（5 秒后）")){appState.onCaptureTest?()};Button(L("触控板设置…")){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)}}
                    note("窗口将隐藏，请将指针放到其他应用的文字上。这只检测取词，不模拟物理重按。")
                    note("关闭窗口后，PressTrans 会继续运行。可随时从应用程序中重新打开设置。")
                }.padding(.top,12)
            }.font(.system(size:12)).foregroundStyle(.secondary)
            HStack(spacing:18) {Button(L("手势演示")){state.gestureDemo=true};Button(L("手动查询…")){state.manual=true};Button(L("预览浮窗"),action:preview)}.buttonStyle(.link).font(.system(size:12))
        }
    }
    private var translation:some View {
        Group {
            group {
                row {languagePicker("译文语言",selection:$state.target,allowSystem:true).onChange(of:state.target){_,value in TranslationPreferences.target=value}}
                rule
                row {languagePicker("解释语言",selection:$state.explanation,allowTarget:true).onChange(of:state.explanation){_,value in TranslationPreferences.explanation=value}}
                rule
                row {HStack {Text(L("同语言内容"));Spacer();GlassMenuPicker(title:L("同语言内容"),value:state.sameLanguage ? L("翻译为另一种语言"):L("直接释义"),selection:$state.sameLanguage) {Text(L("直接释义")).tag(false);Text(L("翻译为另一种语言")).tag(true)}.labelsHidden().frame(width:200).onChange(of:state.sameLanguage){_,value in TranslationPreferences.sameLanguageTranslate=value}}}
                if state.sameLanguage {
                    rule
                    row {languagePicker("另一种语言",selection:$state.alternate).onChange(of:state.alternate){_,value in TranslationPreferences.alternate=value}}
                }
            }
            group {row {HStack {Text(L("在线服务"));Spacer();Text(state.online ? ServicePreferences.provider.rawValue:L("关闭")).foregroundStyle(.secondary);Button(L("管理…")){state.page = .service}.buttonStyle(.link)}}}
            DisclosureGroup(L("离线词典")) {
                VStack(alignment:.leading,spacing:8) {note("英语 → 中文");note("无需账户，断网也可查询。复杂句可能只提供部分词组释义。");note("离线词典仅支持英语到简体中文；当前语言需要在线服务。")}.padding(.top,12)
            }.font(.system(size:12)).foregroundStyle(.secondary)
        }
    }
    private var service:some View {
        Group {
            group {
                row {HStack {
                    Text(L("在线释义"));Spacer()
                    HStack {Toggle(L("在线释义"),isOn:$state.online).labelsHidden().toggleStyle(.switch).controlSize(.small).onChange(of:state.online){_,value in TranslationPreferences.onlineEnabled=value;state.demoKind = .online};Spacer();demoButton(.online)}.padding(.leading,12).frame(width:200)
                }}
                rule
                row {HStack {Text(ServicePreferences.provider.rawValue);Spacer();HStack {Text(ServicePreferences.model).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1);Spacer();Button(L("配置…")){state.prepareService()}}.padding(.leading,12).frame(width:200)}}
                rule
                row {HStack {
                    Text(L("屏幕识字"));Spacer()
                    HStack {Toggle(L("屏幕识字"),isOn:$state.ocr).labelsHidden().toggleStyle(.switch).controlSize(.small).onChange(of:state.ocr){_,value in ScreenTextCapture.enabled=value;state.demoKind = .ocr};Spacer();demoButton(.ocr)}.padding(.leading,12).frame(width:200)
                }}
            }
            if state.online && !state.configured {HStack {note("尚未配置在线服务");Spacer();Button(L("配置…")){state.prepareService()}}}
            if state.ocr && !CGPreflightScreenCaptureAccess() {HStack {note("需要屏幕录制权限");Spacer();Button(L("授权…")){state.permissions=true}}}
            FeatureDemo(kind:state.demoKind,trigger:state.demoReplay)
            HStack(alignment:.top) {note("在线查询发送文字与上下文；截图不上传。");Spacer();Button(L("权限与隐私…")){state.permissions=true}.buttonStyle(.link)}
        }
    }
    private func demoButton(_ kind:FeatureDemoKind)->some View {
        Button {state.demoKind=kind;state.demoReplay+=1} label:{Image(systemName:"play.circle").font(.system(size:15)).foregroundStyle(.secondary)}.buttonStyle(.plain).help(L("查看效果")).accessibilityLabel((kind == .online ? L("在线释义"):L("屏幕识字"))+" · "+L("查看效果"))
    }
    private var permissions:some View {
        VStack(alignment:.leading,spacing:20) {
            Text(L("数据与权限")).font(.system(size:20,weight:.semibold))
            HStack {Text(L("辅助功能权限"));Spacer();Button(L("系统设置…"),action:openAccessibility)}
            HStack {Text(L("屏幕识字"));Spacer();Button(L("授权…")){CGRequestScreenCaptureAccess()}}
            note("在线查询发送文字与上下文；截图不上传。")
            DisclosureGroup(L("详细说明")) {
                VStack(alignment:.leading,spacing:12){note("开启智能释义后，所选文字和附近上下文会发送至你配置的服务。关闭后，离线查询完全在本机完成。");note("仅识别指针附近的一小块画面。截图不保存、不上传；识别出的目标行可用于在线释义。首次初始化可能较慢，图片和复杂排版仍在适配。需要 macOS 15.2 或更新版本。")}.padding(.top,12)
            }.font(.system(size:12))
            HStack {Spacer();Button(L("完成")){state.permissions=false}.keyboardShortcut(.cancelAction)}
        }.padding(28).frame(width:470)
    }
    private var serviceEditor:some View {
        VStack(alignment:.leading,spacing:20) {
            Text(L("在线服务")).font(.system(size:20,weight:.semibold))
            Form {
                Picker(L("服务商"),selection:$state.provider) {ForEach(ServiceProvider.allCases,id:\.rawValue){Text($0.rawValue).tag($0)}}
                    .onChange(of:state.provider){_,value in state.baseURL=value.baseURL;state.model=value.model;state.key=""}
                TextField("Base URL",text:$state.baseURL)
                TextField(L("模型名称"),text:$state.model)
                SecureField("API Key",text:$state.key,prompt:Text(L("留空保留当前地址的密钥")))
            }.textFieldStyle(.roundedBorder)
            note("开启智能释义后，所选文字和附近上下文会发送至你配置的服务。关闭后，离线查询完全在本机完成。")
            DisclosureGroup(L("配置说明")) {VStack(alignment:.leading,spacing:8){note("填写 OpenAI Chat Completions 兼容地址。切换地址后需为新地址保存密钥。");note("仅保存在本机 PressTrans 数据目录，不读取系统钥匙串。个人密钥为可选配置，不影响离线查词。")}.padding(.top,8)}.font(.system(size:12))
            if !state.status.isEmpty {note(state.status)}
            HStack {Spacer();Button(L("取消")){state.editService=false}.keyboardShortcut(.cancelAction);Button(L("保存")) {
                let saved=ServicePreferences.save(provider:state.provider,baseURL:state.baseURL,model:state.model,key:state.key)
                if saved {state.configured=Credentials.load() != nil;state.editService=false;state.key=""}
                else {state.status=L("保存失败，请重试")}
            }.keyboardShortcut(.defaultAction)}
        }.padding(28).frame(width:470)
    }
    private var manual:some View {
        VStack(alignment:.leading,spacing:18) {
            Text(L("手动查询")).font(.system(size:20,weight:.semibold))
            TextEditor(text:$state.text).font(.system(size:16)).padding(10).frame(height:150)
                .background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:8)).accessibilityLabel(L("待查询文字"))
            HStack {note("\(state.text.unicodeScalars.count) / 1000");Spacer();Button(L("取消")){state.manual=false};Button(L("查询释义")){state.manual=false;translate(state.text)}.keyboardShortcut(.defaultAction).disabled(state.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || state.text.unicodeScalars.count>1000)}
        }.padding(28).frame(width:470)
    }
    private func keycap(_ text:String)->some View {Text(text).font(.system(size:12,weight:.medium,design:.monospaced)).foregroundStyle(.secondary)}
    private func languagePicker(_ title:String,selection:Binding<String>,allowSystem:Bool=false,allowTarget:Bool=false)->some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(L(title));Spacer(minLength:16)
                GlassMenuPicker(title:L(title),value:selection.wrappedValue == "system" ? L("跟随系统"):selection.wrappedValue == "target" ? L("与译文相同"):selection.wrappedValue.isEmpty ? L("其他语言…"):LanguageOptions.title(selection.wrappedValue),selection:Binding(get:{LanguageOptions.values.contains(selection.wrappedValue) || ["system","target"].contains(selection.wrappedValue) ? selection.wrappedValue:"custom"},set:{selection.wrappedValue = $0 == "custom" ? "":$0})) {
                if allowSystem {Text(L("跟随系统")).tag("system")}
                if allowTarget {Text(L("与译文相同")).tag("target")}
                ForEach(LanguageOptions.values,id:\.self){Text(LanguageOptions.title($0)).tag($0)}
                Text(L("其他语言…")).tag("custom")
                }.labelsHidden().frame(width:200)
            }
            if !LanguageOptions.values.contains(selection.wrappedValue) && !["system","target"].contains(selection.wrappedValue) {TextField(L("语言名称，如 Hindi"),text:selection).textFieldStyle(.roundedBorder)}
        }
    }
    private func openAccessibility(){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)}
}

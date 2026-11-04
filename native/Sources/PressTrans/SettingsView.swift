import AppKit
import SwiftUI
import PressTransCore

private enum SettingsPage:String,CaseIterable,Identifiable {
    case general="通用",translation="翻译",gesture="重按与快捷键",privacy="隐私与服务",tryIt="手动查询"
    var id:String {rawValue}
    var symbol:String {switch self {case .general:"slider.horizontal.3";case .translation:"character.bubble";case .gesture:"hand.point.up.left";case .privacy:"lock.shield";case .tryIt:"text.magnifyingglass"}}
    var subtitle:String {switch self {case .general:L("让理解自然发生。");case .translation:L("先读懂意思，再了解细节。");case .gesture:L("在阅读的地方，轻轻一按。");case .privacy:L("你决定何时联网、分享哪些内容。");case .tryIt:L("一个词、一句话，或一个新概念。")}}
}
private final class SettingsState:ObservableObject {
    @Published var page:SettingsPage = .general
    @Published var key=""
    @Published var status=""
    @Published var text=""
    @Published var online=TranslationPreferences.onlineEnabled
    @Published var advanced=false
    @Published var configured=Credentials.load() != nil
    @Published var ocr=ScreenTextCapture.enabled
    @Published var target=TranslationPreferences.target
    @Published var explanation=TranslationPreferences.explanation
    @Published var alternate=TranslationPreferences.alternate
    @Published var sameLanguage=TranslationPreferences.sameLanguageTranslate
    @Published var interfaceLanguage=UserDefaults.standard.string(forKey:"interfaceLanguage") ?? "system"
    @Published var provider=ServicePreferences.provider
    @Published var baseURL=ServicePreferences.baseURL
    @Published var model=ServicePreferences.model
#if CAPTURE_ACCEPTANCE
    @Published var acceptancePID:pid_t=0
    @Published var acceptanceX=51.0
    @Published var acceptanceY=54.45
    @Published var acceptanceSelection=false
    @Published var acceptanceOCR=false
#endif
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
    private var green:Color {Color(red:0.22,green:0.43,blue:0.34)}
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:24) {
                HStack(spacing:10) {
                    if let url=Bundle.main.url(forResource:"PressTrans",withExtension:"icns"),let icon=NSImage(contentsOf:url) {
                        Image(nsImage:icon).resizable().frame(width:42,height:42)
                    }
                    VStack(alignment:.leading,spacing:3) {Text("PressTrans").font(.system(size:16,weight:.semibold));Text(L("按压翻译")).font(.system(size:11)).foregroundStyle(.secondary)}
                }.padding(.horizontal,16).padding(.top,24)
                List(selection:$state.page) {
                    ForEach(SettingsPage.allCases) {page in
                        Label(L(page.rawValue),systemImage:page.symbol).font(.system(size:13)).padding(.vertical,6).tag(page)
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                VStack(alignment:.leading,spacing:6) {
                    Label(L("随时，读懂。"),systemImage:"leaf").font(.system(size:11,weight:.medium))
                    Text(L("PressTrans · 预览版")).font(.system(size:10)).foregroundStyle(.tertiary)
                }.foregroundStyle(.secondary).padding(20)
            }.frame(width:196).background(SidebarMaterial())
            Divider()
            VStack(alignment:.leading,spacing:0) {
                VStack(alignment:.leading,spacing:7) {
                    Text(L(state.page.rawValue)).font(.system(size:25,weight:.bold))
                    Text(state.page.subtitle).font(.system(size:13)).foregroundStyle(.secondary)
                }.padding(.horizontal,30).padding(.top,28).padding(.bottom,8)
                Group {
                    switch state.page {
                    case .general:general
                    case .translation:translation
                    case .gesture:gesture
                    case .privacy:privacy
                    case .tryIt:manual
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            }.background(Color(nsColor:.windowBackgroundColor))
        }.frame(minWidth:760,minHeight:520).tint(green)
        .onAppear {if manualMode {state.page = .tryIt}}
    }
    private func note(_ text:String)->some View {Text(L(text)).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).lineSpacing(3)}
    private var general:some View {
        Form {
            Section {
                HStack(spacing:14) {
                    Image(systemName:"text.cursor").font(.system(size:24,weight:.light)).foregroundStyle(green).frame(width:42,height:48)
                    VStack(alignment:.leading,spacing:5) {
                        Text(L("选中，就读懂。")).font(.system(size:17,weight:.semibold))
                        note(L("在其他应用选中文字，按 ⌥⇧T 查看释义。"))
                    }
                    Spacer()
                }.padding(.vertical,6)
                HStack {Button(L("试一试")){state.page = .tryIt};Spacer();Button(L("预览浮窗"),action:preview)}
            }
            Section {
                Picker(L("界面语言"),selection:$state.interfaceLanguage) {
                    Text(L("跟随系统")).tag("system");Text("English").tag("en");Text("简体中文").tag("zh-Hans");Text("繁體中文").tag("zh-Hant")
                }.onChange(of:state.interfaceLanguage){_,value in UserDefaults.standard.set(value,forKey:"interfaceLanguage");NotificationCenter.default.post(name:.interfaceLanguageChanged,object:nil)}
                Toggle(L("显示菜单栏图标"),isOn:Binding(get:{appState.menuVisible},set:{menuVisibility($0)}))
                LabeledContent(L("Dock 图标"),value:L("仅在设置窗口打开时显示"))
            } header:{Text(L("外观"))} footer:{note(L("关闭窗口后，PressTrans 会继续运行。可随时从应用程序中重新打开设置。"))}
            Section(L("使用状态")) {
                HStack {Label(L("辅助功能"),systemImage:"hand.raised");Spacer();Label(appState.trusted ? L("已授权"):L("待开启"),systemImage:appState.trusted ? "checkmark.circle.fill":"exclamationmark.circle").foregroundStyle(appState.trusted ? green:.orange);if !appState.trusted {Button(L("开启…"),action:openAccessibility)}}
                HStack {Label(L("英汉离线词典"),systemImage:"book.closed");Spacer();Text(DictionaryStore.available ? L("已就绪"):L("未安装")).foregroundStyle(.secondary)}
            }
        }.formStyle(.grouped)
    }
    private var translation:some View {
        Form {
            Section {
                Toggle(isOn:$state.online) {VStack(alignment:.leading,spacing:4){Text(L("智能语境释义"));note(L("结合上下文，理解外语、术语、缩写与代码。"))}}
                    .onChange(of:state.online){_,value in TranslationPreferences.onlineEnabled=value}
                if state.online && !state.configured {HStack {note(L("在线服务尚未配置，离线词典仍可使用。"));Spacer();Button(L("配置服务")){state.page = .privacy}}}
            } footer:{note(L("优先显示离线词义；联网成功后补充语境释义，失败时保留词典结果。"))}
            Section {
                languagePicker(L("译文语言"),selection:$state.target,allowSystem:true).onChange(of:state.target){_,value in TranslationPreferences.target=value}
                languagePicker(L("解释语言"),selection:$state.explanation,allowTarget:true).onChange(of:state.explanation){_,value in TranslationPreferences.explanation=value}
                Toggle(L("原文与译文语言相同时，翻译为另一种语言"),isOn:$state.sameLanguage).onChange(of:state.sameLanguage){_,value in TranslationPreferences.sameLanguageTranslate=value}
                if state.sameLanguage {
                    languagePicker(L("另一种语言"),selection:$state.alternate).onChange(of:state.alternate){_,value in TranslationPreferences.alternate=value}
                }
            } header:{Text(L("语言偏好"))} footer:{note(L("自动识别原文语言。第一行直接呈现译文，随后按所选语言解释；同语言默认直接释义。"))}
            Section {
                LabeledContent(L("语言"),value:L("英语 → 中文"))
                LabeledContent(L("匹配方式"),value:L("词形还原 · 短语 · 拼写建议"))
            } header:{Text(L("离线词典"))} footer:{note(L("无需账户，断网也可查询。复杂句可能只提供部分词组释义。"))}
        }.formStyle(.grouped)
    }
    private var gesture:some View {
        Form {
            Section {
                Picker(L("使用"),selection:Binding(get:{appState.forceEnabled},set:{appState.setForce($0)})) {
                    Text(L("系统查词")).tag(false);Text("PressTrans").tag(true)
                }.pickerStyle(.segmented).labelsHidden().padding(.vertical,3)
                note(appState.forceStatus)
                if !appState.trusted {Button(L("开启辅助功能权限…"),action:openAccessibility)}
            } header:{Text(L("触控板重按"))} footer:{note(L("切回系统查词或退出应用，将恢复原来的查词手势设置。"))}
            Section {
                LabeledContent(L("查询选中文字")) {keycap("⌥ ⇧ T")}
                LabeledContent(L("查询指针下的词")) {keycap("⌥ ⇧ P")}
            } header:{Text(L("键盘快捷键"))} footer:{note(L("将指针放在文字上，即可用 ⌥⇧P 查询，无需先选中。与重按使用相同的取词方式。"))}
            Section {
                DisclosureGroup(L("兼容性说明"),isExpanded:$state.advanced) {
                    note(L("重按仍为实验功能，压力检测使用未公开的系统接口。不限制应用名单：优先直接读取文字，失败时可回退到屏幕识字。受保护的输入框不支持。"))
                    Text(L("最近一次取词（仅本次运行）")).font(.caption).foregroundStyle(.secondary)
                    Text(appState.captureStatus).font(.system(size:12)).textSelection(.enabled)
                    Button(L("测试取词（5 秒后）")){appState.onCaptureTest?()}
                    note(L("窗口将隐藏，请将指针放到其他应用的文字上。这只检测取词，不模拟物理重按。"))
#if CAPTURE_ACCEPTANCE
                    Picker("测试窗口",selection:$state.acceptancePID) {
                        Text("选择运行中的应用").tag(pid_t(0))
                        ForEach(NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular},id:\.processIdentifier){app in Text(app.localizedName ?? "应用").tag(app.processIdentifier)}
                    }
                    HStack {TextField("横向 %",value:$state.acceptanceX,format:.number);TextField("纵向 %",value:$state.acceptanceY,format:.number)}
                    Toggle("检测焦点选区",isOn:$state.acceptanceSelection)
                    Toggle("强制窗口 OCR",isOn:$state.acceptanceOCR)
                    if let image=appState.acceptanceImage {Image(nsImage:image).resizable().frame(width:320,height:130)}
                    Button("运行集成检测"){appState.inspectCapture(pid:state.acceptancePID,x:state.acceptanceX,y:state.acceptanceY,selection:state.acceptanceSelection,ocr:state.acceptanceOCR)}.disabled(state.acceptancePID==0)
#endif
                }
                Button(L("触控板设置…")){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)}
            }
        }.formStyle(.grouped)
    }
    private func keycap(_ text:String)->some View {Text(text).font(.system(size:12,weight:.medium,design:.monospaced)).foregroundStyle(.secondary).padding(.horizontal,9).padding(.vertical,4).background(.quaternary,in:RoundedRectangle(cornerRadius:5))}
    private var privacy:some View {
        Form {
            Section {
                Label(L("只在你主动查询时读取文字"),systemImage:"cursorarrow.click")
                Label(L("不保存查询历史，不读取剪贴板"),systemImage:"doc.on.clipboard")
                HStack {Text(L("辅助功能权限"));Spacer();Text(appState.trusted ? L("已授权"):L("未授权")).foregroundStyle(.secondary);Button(L("系统设置…"),action:openAccessibility)}
            } header:{Text(L("数据与权限"))} footer:{note(L("开启智能释义后，所选文字和附近上下文会发送至你配置的服务。关闭后，离线查询完全在本机完成。"))}
            Section {
                Toggle(L("取词失败时使用屏幕识字"),isOn:$state.ocr).onChange(of:state.ocr){_,value in ScreenTextCapture.enabled=value}
                if state.ocr {
                    HStack {note(CGPreflightScreenCaptureAccess() ? L("屏幕录制已授权"):L("需要屏幕录制权限"));Spacer();Button(L("授权…")){CGRequestScreenCaptureAccess()}}
                }
            } header:{Text(L("屏幕识字 · 实验功能"))} footer:{note(L("仅识别指针附近的一小块画面。截图不保存、不上传；识别出的目标行可用于在线释义。首次初始化可能较慢，图片和复杂排版仍在适配。需要 macOS 15.2 或更新版本。"))}
            Section {
                Picker(L("服务商"),selection:$state.provider) {ForEach(ServiceProvider.allCases,id:\.rawValue){Text($0.rawValue).tag($0)}}
                    .onChange(of:state.provider){_,value in state.baseURL=value.baseURL;state.model=value.model;state.key="";state.configured=false}
                TextField("Base URL",text:$state.baseURL)
                TextField(L("模型名称"),text:$state.model)
                note(L("填写 OpenAI Chat Completions 兼容地址。切换地址后需为新地址保存密钥。"))
                LabeledContent(L("个人账户"),value:state.configured ? L("本机密钥已配置"):L("未配置"))
                SecureField(state.configured ? L("输入新密钥以替换"):L("API Key（可选）"),text:$state.key).textFieldStyle(.roundedBorder)
                HStack {
                    Text(state.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("保存到本机")) {
                        let saved=ServicePreferences.save(provider:state.provider,baseURL:state.baseURL,model:state.model,key:state.key)
                        state.status=saved ? L("已保存"):L("保存失败，请重试");state.key="";state.configured=Credentials.load() != nil
                    }.disabled(state.key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            } header:{Text(L("在线服务"))} footer:{note(L("仅保存在本机 PressTrans 数据目录，不读取系统钥匙串。个人密钥为可选配置，不影响离线查词。"))}
        }.formStyle(.grouped)
    }
    private var manual:some View {
        VStack(alignment:.leading,spacing:16) {
            TextEditor(text:$state.text).font(.system(size:17)).scrollContentBackground(.hidden).padding(14)
                .background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Color(nsColor:.separatorColor).opacity(0.5),lineWidth:0.5))
                .frame(minHeight:160,maxHeight:260).accessibilityLabel(L("待查询文字"))
            HStack {note("\(state.text.unicodeScalars.count) / 1000");Spacer();Button(L("查询释义")){translate(state.text)}.buttonStyle(.borderedProminent).controlSize(.large).disabled(state.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || state.text.unicodeScalars.count>1000)}
            note(L("按翻译设置中的语言查询。离线词典目前仅支持英语到简体中文，其他语言需要在线服务。"))
            Spacer()
        }.padding(30).padding(.top,10)
    }
    private func languagePicker(_ title:String,selection:Binding<String>,allowSystem:Bool=false,allowTarget:Bool=false)->some View {
        VStack(alignment:.leading) {
            Picker(L(title),selection:Binding(get:{LanguageOptions.values.contains(selection.wrappedValue) || ["system","target"].contains(selection.wrappedValue) ? selection.wrappedValue:"custom"},set:{selection.wrappedValue = $0 == "custom" ? "":$0})) {
                if allowSystem {Text(L("跟随系统")).tag("system")}
                if allowTarget {Text(L("与译文相同")).tag("target")}
                ForEach(LanguageOptions.values,id:\.self){Text(LanguageOptions.title($0)).tag($0)}
                Text(L("其他语言…")).tag("custom")
            }
            if !LanguageOptions.values.contains(selection.wrappedValue) && !["system","target"].contains(selection.wrappedValue) {
                TextField(L("语言名称，如 Hindi"),text:selection)
            }
        }
    }
    private func openAccessibility(){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)}
}

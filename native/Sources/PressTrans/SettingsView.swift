import AppKit
import SwiftUI
import PressTransCore

private enum SettingsPage:String,CaseIterable,Identifiable {
    case general="通用",translation="翻译",gesture="重按与快捷键",privacy="隐私与服务",tryIt="手动查询"
    var id:String {rawValue}
    var symbol:String {switch self {case .general:"slider.horizontal.3";case .translation:"character.bubble";case .gesture:"hand.point.up.left";case .privacy:"lock.shield";case .tryIt:"text.magnifyingglass"}}
    var subtitle:String {switch self {case .general:"让理解自然发生。";case .translation:"先读懂意思，再了解细节。";case .gesture:"在阅读的地方，轻轻一按。";case .privacy:"你决定何时联网、分享哪些内容。";case .tryIt:"一个词、一句话，或一个新概念。"}}
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
    @Published var chineseMode=TranslationPreferences.chineseMode
    @Published var chineseTarget=TranslationPreferences.chineseTarget
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
    @ObservedObject private var state=SettingsState()
    private var green:Color {Color(red:0.22,green:0.43,blue:0.34)}
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:24) {
                HStack(spacing:10) {
                    if let url=Bundle.main.url(forResource:"PressTrans",withExtension:"icns"),let icon=NSImage(contentsOf:url) {
                        Image(nsImage:icon).resizable().frame(width:42,height:42)
                    }
                    VStack(alignment:.leading,spacing:3) {Text("PressTrans").font(.system(size:16,weight:.semibold));Text("按压翻译").font(.system(size:11)).foregroundStyle(.secondary)}
                }.padding(.horizontal,16).padding(.top,24)
                List(selection:$state.page) {
                    ForEach(SettingsPage.allCases) {page in
                        Label(page.rawValue,systemImage:page.symbol).font(.system(size:13)).padding(.vertical,6).tag(page)
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                VStack(alignment:.leading,spacing:6) {
                    Label("随时，读懂。",systemImage:"leaf").font(.system(size:11,weight:.medium))
                    Text("PressTrans · 预览版").font(.system(size:10)).foregroundStyle(.tertiary)
                }.foregroundStyle(.secondary).padding(20)
            }.frame(width:196).background(SidebarMaterial())
            Divider()
            VStack(alignment:.leading,spacing:0) {
                VStack(alignment:.leading,spacing:7) {
                    Text(state.page.rawValue).font(.system(size:25,weight:.bold))
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
    private func note(_ text:String)->some View {Text(text).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).lineSpacing(3)}
    private var general:some View {
        Form {
            Section {
                HStack(spacing:14) {
                    Image(systemName:"text.cursor").font(.system(size:24,weight:.light)).foregroundStyle(green).frame(width:42,height:48)
                    VStack(alignment:.leading,spacing:5) {
                        Text("选中，就读懂。").font(.system(size:17,weight:.semibold))
                        note("在其他应用选中文字，按 ⌥⇧T 查看释义。")
                    }
                    Spacer()
                }.padding(.vertical,6)
                HStack {Button("试一试"){state.page = .tryIt};Spacer();Button("预览浮窗",action:preview)}
            }
            Section {
                Toggle("显示菜单栏图标",isOn:Binding(get:{appState.menuVisible},set:{menuVisibility($0)}))
                LabeledContent("Dock 图标",value:"仅在设置窗口打开时显示")
            } header:{Text("外观")} footer:{note("关闭窗口后，PressTrans 会继续运行。可随时从应用程序中重新打开设置。")}
            Section("使用状态") {
                HStack {Label("辅助功能",systemImage:"hand.raised");Spacer();Label(appState.trusted ? "已授权":"待开启",systemImage:appState.trusted ? "checkmark.circle.fill":"exclamationmark.circle").foregroundStyle(appState.trusted ? green:.orange);if !appState.trusted {Button("开启…",action:openAccessibility)}}
                HStack {Label("英汉离线词典",systemImage:"book.closed");Spacer();Text(DictionaryStore.available ? "已就绪":"未安装").foregroundStyle(.secondary)}
            }
        }.formStyle(.grouped)
    }
    private var translation:some View {
        Form {
            Section {
                Toggle(isOn:$state.online) {VStack(alignment:.leading,spacing:4){Text("智能语境释义");note("结合上下文，理解外语、术语、缩写与代码。")}}
                    .onChange(of:state.online){_,value in TranslationPreferences.onlineEnabled=value}
                if state.online && !state.configured {HStack {note("在线服务尚未配置，离线词典仍可使用。");Spacer();Button("配置服务"){state.page = .privacy}}}
            } footer:{note("优先显示离线词义；联网成功后补充语境释义，失败时保留词典结果。")}
            Section {
                LabeledContent("外语内容",value:"翻译为中文，再解释")
                Picker("中文内容",selection:$state.chineseMode) {ForEach(ChineseMode.allCases,id:\.rawValue){Text($0.title).tag($0)}}
                    .onChange(of:state.chineseMode){_,value in TranslationPreferences.chineseMode=value}
                if state.chineseMode == .translateAndExplain {
                    Picker("中文译为",selection:$state.chineseTarget) {ForEach(OutputLanguage.allCases,id:\.rawValue){Text($0.title).tag($0)}}
                        .onChange(of:state.chineseTarget){_,value in TranslationPreferences.chineseTarget=value}
                }
            } header:{Text("语言偏好")} footer:{note("第一行直接呈现译文或释义，后面用中文解释确切含义。语言偏好用于在线释义。")}
            Section {
                LabeledContent("语言",value:"英语 → 中文")
                LabeledContent("匹配方式",value:"词形还原 · 短语 · 拼写建议")
            } header:{Text("离线词典")} footer:{note("无需账户，断网也可查询。复杂句可能只提供部分词组释义。")}
        }.formStyle(.grouped)
    }
    private var gesture:some View {
        Form {
            Section {
                Picker("使用",selection:Binding(get:{appState.forceEnabled},set:{appState.setForce($0)})) {
                    Text("系统查词").tag(false);Text("PressTrans").tag(true)
                }.pickerStyle(.segmented).labelsHidden().padding(.vertical,3)
                note(appState.forceStatus)
                if !appState.trusted {Button("开启辅助功能权限…",action:openAccessibility)}
            } header:{Text("触控板重按")} footer:{note("切回系统查词或退出应用，将恢复原来的查词手势设置。")}
            Section {
                LabeledContent("查询选中文字") {keycap("⌥ ⇧ T")}
                LabeledContent("查询指针下的词") {keycap("⌥ ⇧ P")}
            } header:{Text("键盘快捷键")} footer:{note("将指针放在文字上，即可用 ⌥⇧P 查询，无需先选中。与重按使用相同的取词方式。")}
            Section {
                DisclosureGroup("兼容性说明",isExpanded:$state.advanced) {
                    note("重按仍为实验功能，压力检测使用未公开的系统接口。不限制应用名单：优先直接读取文字，失败时可回退到屏幕识字。受保护的输入框不支持。")
                    Text("最近一次取词（仅本次运行）").font(.caption).foregroundStyle(.secondary)
                    Text(appState.captureStatus).font(.system(size:12)).textSelection(.enabled)
                    Button("测试取词（5 秒后）"){appState.onCaptureTest?()}
                    note("窗口将隐藏，请将指针放到其他应用的文字上。这只检测取词，不模拟物理重按。")
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
                Button("触控板设置…"){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)}
            }
        }.formStyle(.grouped)
    }
    private func keycap(_ text:String)->some View {Text(text).font(.system(size:12,weight:.medium,design:.monospaced)).foregroundStyle(.secondary).padding(.horizontal,9).padding(.vertical,4).background(.quaternary,in:RoundedRectangle(cornerRadius:5))}
    private var privacy:some View {
        Form {
            Section {
                Label("只在你主动查询时读取文字",systemImage:"cursorarrow.click")
                Label("不保存查询历史，不读取剪贴板",systemImage:"doc.on.clipboard")
                HStack {Text("辅助功能权限");Spacer();Text(appState.trusted ? "已授权":"未授权").foregroundStyle(.secondary);Button("系统设置…",action:openAccessibility)}
            } header:{Text("数据与权限")} footer:{note("开启智能释义后，所选文字和附近上下文会发送至 DeepSeek。关闭后，离线查询完全在本机完成。")}
            Section {
                Toggle("取词失败时使用屏幕识字",isOn:$state.ocr).onChange(of:state.ocr){_,value in ScreenTextCapture.enabled=value}
                if state.ocr {
                    HStack {note(CGPreflightScreenCaptureAccess() ? "屏幕录制已授权":"需要屏幕录制权限");Spacer();Button("授权…"){CGRequestScreenCaptureAccess()}}
                }
            } header:{Text("屏幕识字 · 实验功能")} footer:{note("仅识别指针附近的一小块画面。截图不保存、不上传；识别出的目标行可用于在线释义。首次初始化可能较慢，图片和复杂排版仍在适配。需要 macOS 15.2 或更新版本。")}
            Section {
                LabeledContent("个人账户",value:state.configured ? "本机密钥已配置":"未配置")
                SecureField(state.configured ? "输入新密钥以替换":"API Key（可选）",text:$state.key).textFieldStyle(.roundedBorder)
                HStack {
                    Text(state.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("保存到本机") {
                        let saved=Credentials.save(state.key.trimmingCharacters(in:.whitespacesAndNewlines))
                        state.status=saved ? "已保存":"保存失败，请重试";state.key="";state.configured=Credentials.load() != nil
                    }.disabled(state.key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            } header:{Text("在线服务 · DeepSeek")} footer:{note("仅保存在本机 PressTrans 数据目录，不读取系统钥匙串。个人密钥为可选配置，不影响离线查词。")}
        }.formStyle(.grouped)
    }
    private var manual:some View {
        VStack(alignment:.leading,spacing:16) {
            TextEditor(text:$state.text).font(.system(size:17)).scrollContentBackground(.hidden).padding(14)
                .background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Color(nsColor:.separatorColor).opacity(0.5),lineWidth:0.5))
                .frame(minHeight:160,maxHeight:260).accessibilityLabel("待查询文字")
            HStack {note("\(state.text.unicodeScalars.count) / 1000 字符");Spacer();Button("查询释义"){translate(state.text)}.buttonStyle(.borderedProminent).controlSize(.large).disabled(state.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || state.text.unicodeScalars.count>1000)}
            note("外语优先译成中文。中文按你的语言偏好处理；未开启在线服务时使用英汉词典。")
            Spacer()
        }.padding(30).padding(.top,10)
    }
    private func openAccessibility(){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)}
}

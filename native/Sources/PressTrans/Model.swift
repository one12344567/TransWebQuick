import AppKit
import SwiftUI
import PressTransCore

@MainActor final class LookupModel: ObservableObject {
    @Published var panelHeight: CGFloat = 350
    @Published var selection=""
    @Published var answer=""
    @Published var source=""
    @Published var context=""
    @Published var message=""
    @Published var loading=false
    @Published var complete=false
    @Published var limited=true
    @Published var preview=false
    @Published var expanded=false
    @Published var offline=false
    @Published var matchNote=""
    private var task:Task<Void,Never>?
    private var generation=UUID()
    var snapshot:CapturedContext?
    func cancel() { generation=UUID(); task?.cancel(); task=nil; loading=false }
    func clear() { cancel(); selection=""; answer=""; context=""; source=""; snapshot=nil; message=""; complete=false; expanded=false; preview=false; offline=false; matchNote="" }
    func show(_ value:CapturedContext) {
        clear(); snapshot=value; selection=value.selection; context=value.context; source=value.sourceApp; limited=value.limited
        query()
    }
    func query(detail:Bool=false) {
        guard let snapshot else { return }
        cancel(); let id=generation; loading=true; complete=false; answer=""; message=""; matchNote=""; offline=true
        let policy=TranslationPreferences.policy
        let enabled=TranslationPreferences.onlineEnabled && Credentials.load() != nil
        let online:LookupEngine.Online?
        if enabled {
            online = { sink in try await Translator.run(snapshot,detail:detail,policy:policy,onText:sink) }
        } else { online=nil }
        task=Task { [weak self] in
            let supported=TranslationPreferences.supportsOffline
            await LookupEngine.run(local:{supported ? await DictionaryStore.shared?.lookup(snapshot.selection):nil},online:online) { [weak self] update in
                await MainActor.run { [weak self] in
                    guard let self, self.generation==id else {return}
                    self.answer=update.text; self.matchNote = supported ? L(update.note):L("离线词典仅支持英语到简体中文；当前语言需要在线服务。")
                    self.message = !supported && update.offline && !update.loading ? L("当前语言的在线释义不可用，请检查服务配置或稍后重试。") : L(update.message)
                    self.loading=update.loading; self.complete=update.complete; self.offline=update.offline
                }
            }
            guard let self, self.generation==id else {return}
            if TranslationPreferences.onlineEnabled && !enabled {self.message=L("在线增强尚未配置，当前使用离线词典。")}
            self.task=nil
        }
    }

    func demo() {
        clear(); preview=true; selection="That’s a hill to die on."; source=L("设计预览"); limited=false
        context="That’s a hill to die on. I would rather keep the discussion open and listen to what the rest of the team thinks."
        answer="那是值得坚持到底的立场。\n\n“hill to die on” 指一个人愿意为之坚持、甚至付出代价的立场。结合后文，作者更倾向于开放讨论，而不是为此争执。"
        if AppLanguage.current == "en" {answer="A position worth defending, even at a cost.\n\nA ‘hill to die on’ is a belief someone is prepared to defend firmly. Here, the next sentence suggests the speaker would rather keep the discussion open."}
        complete=true
    }
}
struct LookupView: View {
    @AppStorage("interfaceLanguage") private var interfaceLanguage="system"
    @ObservedObject var model:LookupModel
    var close:()->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent=Color(red:0.32,green:0.43,blue:0.34)
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:8) {
                Text(model.offline ? L("英汉词典"):L("语境释义")).font(.system(size:12,weight:.semibold)).foregroundStyle(.secondary)
                Spacer()
                if model.preview { Text(L("样式预览")).font(.system(size:10)).foregroundStyle(.secondary) }
                Button(action:close) { Image(systemName:"xmark").font(.system(size:12,weight:.medium)).frame(width:26,height:26).contentShape(Rectangle()) }.buttonStyle(.plain).help(L("关闭 · Esc")).accessibilityLabel(L("关闭释义"))
            }
            .padding(.bottom,14)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    Text(model.selection.isEmpty ? L("选中，就读懂。"):model.selection)
                        .font(.system(size:20,weight:.semibold)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    if !model.source.isEmpty {
                        HStack(spacing:5) { Image(systemName:"macwindow"); Text(model.source); if model.limited { Text(L("· 上下文有限")) } }.font(.system(size:11)).foregroundStyle(.secondary)
                    }
                    if model.loading && model.answer.isEmpty {
                        HStack(spacing:10) { ProgressView().controlSize(.small); Text(L("正在查询…")).font(.system(size:13)).foregroundStyle(.secondary) }.padding(.vertical,18)
                    }
                    if !model.answer.isEmpty {
                        let parts=AnswerParts.split(model.answer)
                        VStack(alignment:.leading,spacing:12) {
                            Text(parts.meaning).font(.system(size:20,weight:.medium)).foregroundStyle(.primary).lineSpacing(4)
                            if !parts.explanation.isEmpty { Text(parts.explanation).font(.system(size:14)).foregroundStyle(.secondary).lineSpacing(5) }
                        }.textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    }
                    if !model.matchNote.isEmpty { Text(model.matchNote).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                    if !model.message.isEmpty && !model.loading { Label(model.message,systemImage:"info.circle").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                    if !model.context.isEmpty {
                        VStack(alignment:.leading,spacing:10) {
                            Button { withAnimation(reduceMotion ? nil:.easeInOut(duration:0.18)) { model.expanded.toggle() } } label: {
                                HStack(spacing:6) { Image(systemName:"chevron.right").rotationEffect(.degrees(model.expanded ? 90:0)); Text(L("参考上下文")); Spacer() }.font(.system(size:12)).foregroundStyle(.secondary).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if model.expanded { Text(model.context).font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10)).transition(.opacity.combined(with:.move(edge:.top))) }
                        }.padding(.top,4)
                    }
                }.padding(.trailing,4)
            }.scrollIndicators(.hidden)
            Divider().opacity(0.5).padding(.vertical,12)
            HStack {
                Text(model.loading ? L("在线增强中…"):(model.offline ? L("离线 · 英 → 中"):L("多语言 · 语境释义"))).font(.system(size:11)).foregroundStyle(.tertiary)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.answer,forType:.string) } label:{ Image(systemName:"doc.on.doc") }.buttonStyle(.plain).disabled(!model.complete).help(L("复制释义")).accessibilityLabel(L("复制释义"))
                if !model.preview && model.snapshot != nil && TranslationPreferences.onlineEnabled && Credentials.load() != nil {
                    Button(model.offline ? L("重试在线"):(model.complete ? L("展开解释"):L("重试"))) { model.query(detail:model.complete && !model.offline) }.buttonStyle(.bordered).controlSize(.small).disabled(model.loading)
                }
            }
        }.padding(20).frame(width:408,height:model.panelHeight).background(Color.clear)
    }
}

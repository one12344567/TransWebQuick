import AppKit
import SwiftUI
import PressTransCore

@MainActor final class LookupModel: ObservableObject {
    @Published var panelHeight: CGFloat = 150
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
    @Published var contextExpanded=false
    @Published var offline=false
    @Published var matchNote=""
    private var task:Task<Void,Never>?
    private var generation=UUID()
    var snapshot:CapturedContext?
    func cancel() { generation=UUID(); task?.cancel(); task=nil; loading=false }
    func clear() { cancel(); selection=""; answer=""; context=""; source=""; snapshot=nil; message=""; complete=false; expanded=false; contextExpanded=false; preview=false; offline=false; matchNote="" }
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
                    self.answer=update.text; self.matchNote = update.offline ? (supported ? L(update.note):L("离线词典仅支持英语到简体中文；当前语言需要在线服务。")):""
                    self.message = !supported && update.offline && !update.loading ? L("当前语言的在线释义不可用，请检查服务配置或稍后重试。") : L(update.message)
                    self.loading=update.loading; self.complete=update.complete; self.offline=update.offline
                }
            }
            guard let self, self.generation==id else {return}
            if TranslationPreferences.onlineEnabled && !enabled && supported {self.message=L("在线增强尚未配置，当前使用离线词典。")}
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
    @AppStorage("popupFont") private var popupFont="system"
    @AppStorage("popupFontSize") private var popupFontSize=20.0
    @AppStorage("popupInk") private var popupInk="automatic"
    @AppStorage("popupStyle") private var popupStyle="glass"
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model:LookupModel
    var close:()->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var parts:(meaning:String,explanation:String) {AnswerParts.split(model.answer)}
    private func copy(_ text:String) {NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.top,spacing:12) {
                Text(model.selection.isEmpty ? L("未获取文字"):model.selection)
                    .font(.system(size:12)).foregroundStyle(.secondary).lineLimit(model.expanded ? 3:2)
                    .textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                Button(action:close) {Image(systemName:"xmark").font(.system(size:11,weight:.medium)).foregroundStyle(.tertiary).frame(width:18,height:18).contentShape(Rectangle())}
                    .buttonStyle(.plain).help(L("关闭 · Esc")).accessibilityLabel(L("关闭释义"))
            }.padding(.bottom,10)
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    if model.loading && model.answer.isEmpty {
                        HStack(spacing:9){ProgressView().controlSize(.small);Text(L("正在查询…")).font(.system(size:13)).foregroundStyle(.secondary)}.padding(.vertical,4)
                    }
                    if !parts.meaning.isEmpty {
                        Text(parts.meaning).font(.system(size:PopupAppearance.size,weight:.medium,design:PopupAppearance.design)).foregroundStyle(PopupAppearance.ink(dark:popupStyle == "graphite" || colorScheme == .dark)).lineSpacing(3).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    }
                    if model.expanded {
                        if !parts.explanation.isEmpty {Text(parts.explanation).font(.system(size:max(12,PopupAppearance.size*0.7),design:PopupAppearance.design)).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
                        if !model.matchNote.isEmpty {Text(model.matchNote).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
                        if !model.context.isEmpty {
                            Button {withAnimation(reduceMotion ? nil:.easeInOut(duration:0.18)){model.contextExpanded.toggle()}} label:{
                                HStack(spacing:6){Text(L("上下文"));Image(systemName:"chevron.right").font(.system(size:9,weight:.semibold)).rotationEffect(.degrees(model.contextExpanded ? 90:0));Spacer()}.font(.system(size:12)).foregroundStyle(.secondary).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if model.contextExpanded {
                                if !model.source.isEmpty && !model.preview {Text(model.source + (model.limited ? " · " + L("上下文有限"):"")).font(.system(size:11)).foregroundStyle(.tertiary)}
                                Text(model.context).font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
                        }
                    }
                    if !model.message.isEmpty && !model.loading && (model.expanded || model.answer.isEmpty) {
                        Text(model.message).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.scrollIndicators(.hidden)
            Divider().opacity(0.4).padding(.top,12).padding(.bottom,10)
            HStack(spacing:12) {
                Button {
                    withAnimation(reduceMotion ? nil:.easeInOut(duration:0.18)){model.expanded.toggle();if !model.expanded {model.contextExpanded=false}}
                } label:{HStack(spacing:5){Text(model.expanded ? L("收起"):L("解释"));Image(systemName:"chevron.right").font(.system(size:9,weight:.medium)).rotationEffect(.degrees(model.expanded ? -90:0))}}
                    .buttonStyle(.plain).disabled(model.answer.isEmpty).accessibilityValue(model.expanded ? L("已展开"):L("已收起"))
                if model.offline && !model.answer.isEmpty {Text(L("词典")).font(.system(size:10)).foregroundStyle(.tertiary)}
                if model.loading && !model.answer.isEmpty {ProgressView().controlSize(.mini)}
                Spacer()
                if model.expanded || (!model.message.isEmpty && model.answer.isEmpty) {
                    Menu {
                        if !model.selection.isEmpty {Button(L("复制原文")){copy(model.selection)}}
                        if !model.answer.isEmpty {Button(L("复制完整释义")){copy(model.answer)}}
                        if !model.context.isEmpty {Button(L("复制上下文")){copy(model.context)}}
                        if !model.preview && model.snapshot != nil && TranslationPreferences.onlineEnabled && Credentials.load() != nil {
                            Divider()
                            Button(L("进一步解释")){model.query(detail:true)}.disabled(model.loading)
                            Button(L("重试在线")){model.query()}.disabled(model.loading)
                        }
                    } label:{Image(systemName:"ellipsis").frame(width:20,height:18)}
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("更多操作"))
                }
                Button {copy(model.expanded ? model.answer:parts.meaning)} label:{Image(systemName:"doc.on.doc").frame(width:20,height:18)}
                    .buttonStyle(.plain).disabled(!model.complete).help(L("复制释义")).accessibilityLabel(L("复制释义"))
            }.font(.system(size:12)).foregroundStyle(.secondary)
        }.padding(20).frame(width:380,height:model.panelHeight).background(Color.clear)
    }
}

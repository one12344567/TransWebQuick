import AppKit
import SwiftUI
import PressTransCore

@MainActor final class LookupModel: ObservableObject {
    struct DisclosureProgress:Equatable {var detail:CGFloat=0;var context:CGFloat=0;var dictionary:CGFloat=0}
    @Published var disclosure=DisclosureProgress()
    var onDisclosureChange:(()->Void)?
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
    @Published var dictionaryText=""
    @Published var dictionaryNote=""
    @Published var dictionaryExpanded=false
    @Published var usageRecord:UsageRecord?
    private var task:Task<Void,Never>?
    private var generation=UUID()
    var snapshot:CapturedContext?
    func toggleDetails() {expanded.toggle();onDisclosureChange?()}
    func toggleContext() {contextExpanded.toggle();onDisclosureChange?()}
    func toggleDictionary() {dictionaryExpanded.toggle();onDisclosureChange?()}
    func cancel() { generation=UUID(); task?.cancel(); task=nil; loading=false }
    func clear() { cancel(); selection=""; answer=""; context=""; source=""; snapshot=nil; message=""; complete=false; expanded=false; contextExpanded=false; preview=false; offline=false; matchNote="";dictionaryText="";dictionaryNote="";dictionaryExpanded=false;usageRecord=nil }
    func show(_ value:CapturedContext) {
        clear(); snapshot=value; selection=value.selection; context=value.context; source=value.sourceApp; limited=value.limited
        query()
    }
    func query(detail:Bool=false) {
        guard let snapshot else { return }
        cancel(); let id=generation; loading=true; complete=false; answer=""; message=""; matchNote=""; offline=false;dictionaryText="";dictionaryNote="";dictionaryExpanded=false;usageRecord=nil
        let policy=TranslationPreferences.policy
        let enabled=TranslationPreferences.onlineEnabled && Credentials.load() != nil
        let online:LookupEngine.Online?
        if enabled {
            online = { [weak self] sink in try await Translator.run(snapshot,detail:detail,policy:policy,onText:sink,onRecord:{[weak self] record in
                await MainActor.run { [weak self] in guard let self,self.generation==id else{return};self.usageRecord=record}
            }) }
        } else { online=nil }
        task=Task { [weak self] in
            let supported=TranslationPreferences.supportsOffline
            await LookupEngine.run(local:{supported ? await DictionaryStore.shared?.lookup(snapshot.selection):nil},online:online) { [weak self] update in
                await MainActor.run { [weak self] in
                    guard let self, self.generation==id else {return}
                    self.answer=update.text; self.matchNote = update.offline ? (supported ? L(update.note):L("离线词典仅支持英语到简体中文；当前语言需要在线服务。")):""
                    self.message = !supported && update.offline && !update.loading ? L("当前语言的在线释义不可用，请检查服务配置或稍后重试。") : L(update.message)
                    self.loading=update.loading; self.complete=update.complete; self.offline=update.offline
                    self.dictionaryText=update.reference?.text ?? "";self.dictionaryNote=update.reference.map{L($0.note)} ?? ""
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
    private var parts:(meaning:String,explanation:String) {AnswerParts.split(model.answer)}
    private func copy(_ text:String) {NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.top,spacing:12) {
                Text(model.selection.isEmpty ? L("未获取文字"):model.selection)
                    .font(.system(size:12)).foregroundStyle(.secondary).lineLimit(2)
                    .textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                Button(action:close) {Image(systemName:"xmark").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary).frame(width:32,height:32).contentShape(Rectangle())}
                    .buttonStyle(LookupButtonStyle()).help(L("关闭 · Esc")).accessibilityLabel(L("关闭释义"))
            }.frame(minHeight:32).padding(.bottom,8)
            ScrollView {
                VStack(alignment:.leading,spacing:0) {
                    if model.loading && model.answer.isEmpty {
                        HStack(spacing:9){ProgressView().controlSize(.small);Text(L("正在查询…")).font(.system(size:13)).foregroundStyle(.secondary)}.padding(.vertical,4)
                    }
                    if !parts.meaning.isEmpty {
                        Text(parts.meaning).font(.system(size:PopupAppearance.size,weight:.medium,design:PopupAppearance.design)).foregroundStyle(PopupAppearance.ink(dark:popupStyle == "graphite" || colorScheme == .dark)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                    }
                    LookupDisclosure(progress:model.disclosure.detail) {
                      VStack(alignment:.leading,spacing:14) {
                        if !parts.explanation.isEmpty {Text(parts.explanation).font(.system(size:max(12,PopupAppearance.size*0.7),design:PopupAppearance.design)).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
                        if !model.matchNote.isEmpty {Text(model.matchNote).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
                        if !model.dictionaryText.isEmpty {
                            VStack(alignment:.leading,spacing:0) {
                            Button(action:model.toggleDictionary) {
                                HStack(spacing:6){Text(L("词典参考"));Image(systemName:"chevron.right").font(.system(size:9,weight:.semibold)).rotationEffect(.degrees(model.disclosure.dictionary*90));Spacer()}.font(.system(size:12)).foregroundStyle(.secondary).padding(.horizontal,6).frame(maxWidth:.infinity,minHeight:32,alignment:.leading).contentShape(Rectangle())
                            }.buttonStyle(LookupButtonStyle()).accessibilityValue(model.dictionaryExpanded ? L("已展开"):L("已收起"))
                            LookupDisclosure(progress:model.disclosure.dictionary) {
                              VStack(alignment:.leading,spacing:8) {
                                Text(model.dictionaryText).font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                                Text(model.dictionaryNote).font(.system(size:11)).foregroundStyle(.tertiary).fixedSize(horizontal:false,vertical:true)
                              }.padding(.top,8)
                            }
                            }
                        }
                        if !model.context.isEmpty {
                            VStack(alignment:.leading,spacing:0) {
                            Button(action:model.toggleContext) {
                                HStack(spacing:6){Text(L("上下文"));Image(systemName:"chevron.right").font(.system(size:9,weight:.semibold)).rotationEffect(.degrees(model.disclosure.context*90));Spacer()}.font(.system(size:12)).foregroundStyle(.secondary).padding(.horizontal,6).frame(maxWidth:.infinity,minHeight:32,alignment:.leading).contentShape(Rectangle())
                            }.buttonStyle(LookupButtonStyle()).accessibilityValue(model.contextExpanded ? L("已展开"):L("已收起"))
                            LookupDisclosure(progress:model.disclosure.context) {
                              VStack(alignment:.leading,spacing:8) {
                                if !model.source.isEmpty && !model.preview {Text(model.source + (model.limited ? " · " + L("上下文有限"):"")).font(.system(size:11)).foregroundStyle(.tertiary)}
                                Text(model.context).font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                              }.padding(.top,8)
                            }
                            }
                        }
                        if let record=model.usageRecord {
                            Text(record.usage.map{L("本次用量")+" · \($0.total.formatted()) tokens · "+L("输入")+" \($0.input.formatted()) / "+L("输出")+" \($0.output.formatted())"} ?? L("本次用量未返回"))
                                .font(.system(size:10)).foregroundStyle(.tertiary).fixedSize(horizontal:false,vertical:true)
                        }
                      }.padding(.top,14)
                    }
                    if !model.message.isEmpty && !model.loading {
                        LookupDisclosure(progress:model.answer.isEmpty ? 1:model.disclosure.detail) {
                            Text(model.message).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).padding(.top,14)
                        }
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.scrollIndicators(.never)
            Divider().opacity(0.4).padding(.top,8).padding(.bottom,4)
            HStack(spacing:6) {
                Button(action:model.toggleDetails) {HStack(spacing:5){Text(model.expanded ? L("收起"):L("解释"));Image(systemName:"chevron.right").font(.system(size:9,weight:.medium)).rotationEffect(.degrees(model.disclosure.detail * -90))}.padding(.horizontal,8).frame(minWidth:72,minHeight:36,alignment:.leading).contentShape(Rectangle())}
                    .buttonStyle(LookupButtonStyle()).disabled(model.answer.isEmpty).accessibilityValue(model.expanded ? L("已展开"):L("已收起"))
                if model.offline && !model.answer.isEmpty {Text(L("词典")).font(.system(size:10)).foregroundStyle(.tertiary)}
                if model.loading && !model.answer.isEmpty {ProgressView().controlSize(.mini)}
                Spacer()
                    Menu {
                        if !model.selection.isEmpty {Button(L("复制原文")){copy(model.selection)}}
                        if !model.answer.isEmpty {Button(L("复制完整释义")){copy(model.answer)}}
                        if !model.context.isEmpty {Button(L("复制上下文")){copy(model.context)}}
                        if !model.preview && model.snapshot != nil && TranslationPreferences.onlineEnabled && Credentials.load() != nil {
                            Divider()
                            Button(L("进一步解释")){model.query(detail:true)}.disabled(model.loading)
                            Button(L("重试在线")){model.query()}.disabled(model.loading)
                        }
                    } label:{Image(systemName:"ellipsis").frame(width:36,height:36).contentShape(Rectangle())}
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width:36,height:36).help(L("更多操作"))
                    .opacity(model.expanded || (!model.message.isEmpty && model.answer.isEmpty) ? 1:0)
                    .allowsHitTesting(model.expanded || (!model.message.isEmpty && model.answer.isEmpty))
                    .accessibilityHidden(!model.expanded && (model.message.isEmpty || !model.answer.isEmpty))
                Button {copy(model.expanded ? model.answer:parts.meaning)} label:{Image(systemName:"doc.on.doc").frame(width:36,height:36).contentShape(Rectangle())}
                    .buttonStyle(LookupButtonStyle()).disabled(!model.complete).help(L("复制释义")).accessibilityLabel(L("复制释义"))
            }.font(.system(size:12)).foregroundStyle(.secondary)
        }.padding(.horizontal,20).padding(.top,14).padding(.bottom,12)
            .frame(width:380).frame(maxHeight:.infinity,alignment:.top).background(Color.clear)
            .transaction{$0.animation=nil;$0.disablesAnimations=true}
    }
}

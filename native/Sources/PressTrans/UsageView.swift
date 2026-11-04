import SwiftUI
import PressTransCore

@MainActor private final class UsageViewState:ObservableObject {
    @Published var page:UsagePage?
    @Published var offset=0
    @Published var selected:String?
    @Published var failed=false
    func load() async {
        let requested=offset
        do {
            let result=try await UsageHistory.shared.page(offset:requested)
            guard !Task.isCancelled,requested==offset else{return}
            page=result;failed=false
        } catch {failed=true}
    }
}
struct UsageView:View {
    @StateObject private var state=UsageViewState()
    @ObservedObject private var history=UsageHistory.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            if let page=state.page {
                HStack(alignment:.top,spacing:22) {
                    metric("今日 tokens",value:page.today)
                    metric("累计 tokens",value:page.total)
                    metric("请求次数",value:page.count)
                }
                if page.unknown>0 {Text("\(page.unknown.formatted()) · "+L("用量未返回，未计入总量")).font(.system(size:11)).foregroundStyle(.secondary)}
                if page.records.isEmpty {
                    VStack(spacing:12){Image(systemName:"chart.bar.xaxis").font(.system(size:28,weight:.light));Text(L("暂无在线查询记录")).font(.system(size:13))}
                        .foregroundStyle(.secondary).frame(maxWidth:.infinity).padding(.vertical,48)
                } else {
                    HStack {Text(L("每次查询")).font(.system(size:12,weight:.medium));Spacer();pager(page)}
                    LazyVStack(spacing:8) {ForEach(page.records){record in recordRow(record)}}
                    if page.count>50 {HStack {Spacer();pager(page)}}
                }
                HStack(alignment:.top) {
                    Text(L("仅存用量，不保存查询正文。"))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount:page.bytes,countStyle:.file)).monospacedDigit()
                }.font(.system(size:11)).foregroundStyle(.secondary)
            } else if !state.failed {ProgressView().controlSize(.small)}
            if state.failed || history.unavailable {Text(L("用量记录暂不可用，请检查本机存储空间。" )).font(.system(size:12)).foregroundStyle(.secondary)}
        }.task(id:state.offset){await state.load()}
            .onReceive(NotificationCenter.default.publisher(for:.usageHistoryChanged)){_ in Task{await state.load()}}
    }
    private func metric(_ label:String,value:Int)->some View {
        VStack(alignment:.leading,spacing:7) {Text(L(label)).font(.system(size:11)).foregroundStyle(.secondary);Text(value.formatted()).font(.system(size:23,weight:.medium,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)}.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func pager(_ page:UsagePage)->some View {
        HStack(spacing:12) {
            Button {state.selected=nil;state.offset=max(0,state.offset-50)} label:{Image(systemName:"chevron.left")}.disabled(state.offset==0).accessibilityLabel(L("上一页"))
            Text("\(state.offset/50+1) / \(max(1,(page.count+49)/50))").monospacedDigit().foregroundStyle(.secondary)
            Button {state.selected=nil;state.offset+=50} label:{Image(systemName:"chevron.right")}.disabled(state.offset+50>=page.count).accessibilityLabel(L("下一页"))
        }.buttonStyle(.plain).font(.system(size:11))
    }
    private func recordRow(_ record:UsageRecord)->some View {
        let expanded=state.selected==record.id
        return VStack(alignment:.leading,spacing:12) {
            Button {withAnimation(reduceMotion ? nil:.easeInOut(duration:0.16)){state.selected=expanded ? nil:record.id}} label:{
                HStack(spacing:12) {
                    VStack(alignment:.leading,spacing:5) {
                        Text(record.date.formatted(date:.abbreviated,time:.standard)).font(.system(size:12))
                        Text(record.model).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength:12)
                    Text(record.usage.map{"\($0.total.formatted()) tokens"} ?? (record.status=="running" ? L("查询中"):L("未返回"))).font(.system(size:12)).monospacedDigit()
                    Image(systemName:"chevron.right").font(.system(size:9,weight:.medium)).foregroundStyle(.tertiary).rotationEffect(.degrees(expanded ? 90:0))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(expanded ? L("已展开"):L("已收起"))
            if expanded {
                Divider().opacity(0.45)
                HStack {Text(record.provider);Spacer();Text(L(record.detail ? "详细释义":"简短释义"));Text("·");Text(status(record.status))}.font(.system(size:11)).foregroundStyle(.secondary)
                if let usage=record.usage {
                    HStack(spacing:20){counter("输入",usage.input);counter("输出",usage.output);if let cached=usage.cached {counter("缓存命中",cached)};if let reasoning=usage.reasoning {counter("推理",reasoning)}}
                } else {Text(L("服务未返回完整用量；取消或断流也可能产生费用。" )).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
            }
        }.padding(13).background(Color(nsColor:.controlBackgroundColor).opacity(0.8),in:RoundedRectangle(cornerRadius:10))
    }
    private func counter(_ title:String,_ count:Int)->some View {
        VStack(alignment:.leading,spacing:4){Text(L(title)).foregroundStyle(.secondary);Text(count.formatted()).monospacedDigit()}.font(.system(size:11)).frame(maxWidth:.infinity,alignment:.leading)
    }
    private func status(_ value:String)->String {
        switch value {case "completed":L("已完成");case "failed":L("失败");case "cancelled":L("已取消");case "running":L("查询中");default:L("已中断")}
    }
}

import SwiftUI

/// Local, finite illustrations. They never capture a screen, request permission or call a provider.
enum FeatureDemoKind:String {case online,ocr,force}
private final class DemoTimeline:ObservableObject {
    @Published var phase=0
    @Published var replay=0
}
struct FeatureDemo:View {
    let kind:FeatureDemoKind
    var enabled=true
    var trigger=0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var timeline=DemoTimeline()
    private var phase:Int {get{timeline.phase} nonmutating set{timeline.phase=newValue}}
    private var replay:Int {get{timeline.replay} nonmutating set{timeline.replay=newValue}}
    private var title:String {switch kind {case .online:L("在线释义");case .ocr:L("屏幕识字");case .force:L("触控板重按")}}
    private var finished:Bool {phase>=2}
    private var caption:String {
        if !enabled {return L("关闭时")}
        switch kind {
        case .online:return finished ? L("结合上下文"):L("词典释义")
        case .ocr:return finished ? L("识别并查询"):L("图片中的文字")
        case .force:return finished ? L("原地查看释义"):L("在单词上重按")
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(title).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                Text(L("效果演示")).font(.system(size:10)).foregroundStyle(.tertiary)
                Spacer()
                Button {replay+=1} label:{Image(systemName:"play.fill").font(.system(size:10)).frame(width:24,height:22)}
                    .buttonStyle(.plain).help(L("重播演示")).accessibilityLabel(L("重播演示"))
            }
            HStack(alignment:.center,spacing:20) {
                sample.frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"arrow.right").font(.system(size:12)).foregroundStyle(.tertiary)
                result.frame(maxWidth:.infinity,alignment:.leading)
            }.frame(height:70)
            Text(caption).font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(14)
            .background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:10))
            .accessibilityElement(children:.contain)
            .task(id:"\(kind.rawValue)-\(enabled)-\(replay)-\(reduceMotion)-\(trigger)") {
                phase=0
                guard enabled else{return}
                if reduceMotion {phase=2;return}
                do {
                    try await Task.sleep(nanoseconds:600_000_000)
                    withAnimation(.easeInOut(duration:0.25)){phase=1}
                    try await Task.sleep(nanoseconds:900_000_000)
                    withAnimation(.easeInOut(duration:0.25)){phase=2}
                } catch {return}
            }
    }
    @ViewBuilder private var sample:some View {
        switch kind {
        case .online:
            VStack(alignment:.leading,spacing:6) {
                Text("The server is").font(.system(size:13))
                Text("down.").font(.system(size:16,weight:.medium))
                    .padding(.horizontal,4).background(finished ? Color.yellow.opacity(0.28):.clear,in:RoundedRectangle(cornerRadius:3))
            }
        case .ocr:
            ZStack {
                RoundedRectangle(cornerRadius:8).fill(Color(nsColor:.controlBackgroundColor))
                HStack(spacing:7){Image(systemName:"photo").font(.system(size:14)).foregroundStyle(.secondary);Text("Welcome").font(.system(size:16,weight:.medium))}
                RoundedRectangle(cornerRadius:6).strokeBorder(Color.accentColor.opacity(phase>=1 ? 0.65:0),style:StrokeStyle(lineWidth:1,dash:[4,3])).padding(5)
            }.frame(height:58)
        case .force:
            ZStack(alignment:.bottomTrailing) {
                Text("serendipity").font(.system(size:16,weight:.medium)).padding(7)
                    .background(phase>=1 ? Color.yellow.opacity(0.3):.clear,in:RoundedRectangle(cornerRadius:4))
                Image(systemName:"cursorarrow").font(.system(size:16)).offset(x:8,y:10).scaleEffect(phase==1 ? 0.85:1)
            }
        }
    }
    private var result:some View {
        VStack(alignment:.leading,spacing:5) {
            switch kind {
            case .online:
                Text(finished ? L("服务器暂时无法访问。"):"down").font(.system(size:14,weight:finished ? .medium:.regular))
                if !finished {Text(L("向下；往下")).font(.system(size:12)).foregroundStyle(.secondary)}
            case .ocr:
                if finished {Text("Welcome").font(.system(size:11)).foregroundStyle(.secondary);Text(L("欢迎")).font(.system(size:16,weight:.medium))}
                else {Text(L("图片文字不可直接选中")).font(.system(size:12)).foregroundStyle(.secondary)}
            case .force:
                if finished {Text(L("意外发现的美好")).font(.system(size:15,weight:.medium))}
                else {Image(systemName:"ellipsis").foregroundStyle(.tertiary)}
            }
        }.frame(maxWidth:.infinity,minHeight:52,alignment:.leading).padding(.horizontal,10)
            .background(Color(nsColor:.controlBackgroundColor).opacity(finished ? 0.9:0),in:RoundedRectangle(cornerRadius:8))
    }
}

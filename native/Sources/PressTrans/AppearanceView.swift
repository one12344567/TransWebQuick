import AppKit
import SwiftUI

enum PopupAppearance {
    static var style:String {UserDefaults.standard.string(forKey:"popupStyle") ?? "glass"}
    static var size:CGFloat {let value=UserDefaults.standard.double(forKey:"popupFontSize");return value == 0 ? 20:min(max(value,16),24)}
    static var opacity:Double {let value=UserDefaults.standard.double(forKey:"popupOpacity");return value == 0 ? 0.92:min(max(value,0.80),1)}
    static var design:Font.Design {switch UserDefaults.standard.string(forKey:"popupFont") {case "serif":.serif;case "rounded":.rounded;default:.default}}
    static func nsFont(size:CGFloat,weight:NSFont.Weight = .regular)->NSFont {
        let font=NSFont.systemFont(ofSize:size,weight:weight)
        let design:NSFontDescriptor.SystemDesign = self.design == .serif ? .serif:self.design == .rounded ? .rounded:.default
        return font.fontDescriptor.withDesign(design).flatMap{NSFont(descriptor:$0,size:size)} ?? font
    }
    static func ink(dark:Bool)->Color {
        switch UserDefaults.standard.string(forKey:"popupInk") {
        case "blue":return dark ? Color(red:0.64,green:0.80,blue:1):Color(red:0.15,green:0.30,blue:0.48)
        case "green":return dark ? Color(red:0.65,green:0.85,blue:0.72):Color(red:0.16,green:0.35,blue:0.25)
        case "plum":return dark ? Color(red:0.85,green:0.72,blue:0.94):Color(red:0.38,green:0.23,blue:0.46)
        default:return .primary
        }
    }
}

struct AppearanceView:View {
    var showPopover:()->Void
    @AppStorage("settingsStyle") private var menuStyle="glass"
    @AppStorage("popupStyle") private var popupStyle="glass"
    @AppStorage("popupFont") private var font="system"
    @AppStorage("popupFontSize") private var fontSize=20.0
    @AppStorage("popupInk") private var ink="automatic"
    @AppStorage("popupOpacity") private var opacity=0.92
    @AppStorage("preciseHighlightEnabled") private var preciseHighlight=true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var dark:Bool {popupStyle == "graphite" || colorScheme == .dark}
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            section("设置窗口") {
                HStack(spacing:12) {
                    menuTile("A",value:"glass")
                    menuTile("B",value:"paper")
                }
            }
            section("悬浮窗") {
                HStack(spacing:10) {
                    popupTile("轻透",value:"glass")
                    popupTile("纸白",value:"paper")
                    popupTile("石墨",value:"graphite")
                }
                preview.padding(.top,14)
            }
            VStack(spacing:15) {
                HStack {Text(L("字体"));Spacer();GlassMenuPicker(title:L("字体"),value:font == "serif" ? L("衬线"):font == "rounded" ? L("圆体"):L("系统"),selection:$font) {
                    Text(L("系统")).tag("system");Text(L("衬线")).tag("serif");Text(L("圆体")).tag("rounded")
                }.frame(width:200)}
                HStack {Text(L("字号"));Spacer();HStack {Text("Aa").font(.system(size:11));Slider(value:$fontSize,in:16...24,step:1).accessibilityLabel(L("字号"));Text("Aa").font(.system(size:17))}.frame(width:200)}
                HStack {Text(L("文字配色"));Spacer();HStack(spacing:16) {
                    swatch("automatic",title:"自动",color:.primary)
                    swatch("blue",title:"海蓝",color:Color(red:0.25,green:0.43,blue:0.65))
                    swatch("green",title:"苔绿",color:Color(red:0.28,green:0.49,blue:0.36))
                    swatch("plum",title:"雾紫",color:Color(red:0.49,green:0.34,blue:0.58))
                }.frame(width:200,alignment:.leading)}
                HStack {Text(L("透明度"));Spacer();HStack {Image(systemName:"square.dashed");Slider(value:$opacity,in:0.80...1).accessibilityLabel(L("透明度"));Image(systemName:"square.fill")}.foregroundStyle(.secondary).frame(width:200).disabled(popupStyle != "glass" || reduceTransparency || contrast == .increased)}
            }.font(.system(size:13))
            HStack {
                Text(L("清晰高亮"));Spacer()
                Toggle(L("清晰高亮"),isOn:$preciseHighlight).labelsHidden().toggleStyle(.switch).controlSize(.small).frame(width:200,alignment:.leading)
            }.font(.system(size:13)).help(L("仅在本机读取目标文字的小块画面，黄色避开笔画；无录屏权限时使用描边。"))
            HStack {Button(L("预览浮窗"),action:showPopover).buttonStyle(.link);Spacer();Button(L("恢复默认")){menuStyle="glass";popupStyle="glass";font="system";fontSize=20;ink="automatic";opacity=0.92;preciseHighlight=true}.buttonStyle(.link)}.font(.system(size:12))
        }
    }
    private func section<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:10){Text(L(title)).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary);content()}
    }
    private func menuTile(_ label:String,value:String)->some View {
        Button {menuStyle=value} label:{
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:7) {
                    if value == "glass" {RoundedRectangle(cornerRadius:3).fill(.primary.opacity(0.08)).frame(width:25)}
                    VStack(alignment:.leading,spacing:7) {
                        if value == "paper" {HStack(spacing:4){ForEach(0..<3){_ in Capsule().fill(.primary.opacity(0.18)).frame(width:14,height:3)}}}
                        ForEach(0..<3){_ in HStack{Capsule().fill(.primary.opacity(0.15)).frame(width:28,height:3);Spacer();Capsule().fill(.primary.opacity(0.08)).frame(width:36,height:7)}}
                    }.padding(.vertical,8)
                }.frame(height:48).padding(8).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:7))
                HStack {Text(label).font(.system(size:12,weight:.medium));Spacer();if menuStyle==value {Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.system(size:12))}}
            }.padding(9).frame(maxWidth:.infinity).overlay{RoundedRectangle(cornerRadius:10).strokeBorder(menuStyle==value ? Color.accentColor.opacity(0.65):Color.primary.opacity(0.1),lineWidth:menuStyle==value ? 1.5:0.5)}
        }.buttonStyle(.plain).accessibilityLabel(L("设置窗口")+" "+label).accessibilityAddTraits(menuStyle==value ? .isSelected:[])
    }
    private func popupTile(_ title:String,value:String)->some View {
        Button {popupStyle=value} label:{
            VStack(alignment:.leading,spacing:7) {
                VStack(alignment:.leading,spacing:5) {Text("Hello").font(.system(size:9)).opacity(0.6);Text(L("你好")).font(.system(size:13,weight:.medium))}
                    .frame(maxWidth:.infinity,alignment:.leading).padding(9).background(value == "graphite" ? Color(white:0.19):Color(nsColor:.controlBackgroundColor).opacity(value == "glass" ? 0.75:1),in:RoundedRectangle(cornerRadius:7))
                    .foregroundStyle(value == "graphite" ? Color.white:Color.primary)
                HStack{Text(L(title)).font(.system(size:11));Spacer();if popupStyle==value {Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.system(size:11))}}
            }.padding(8).frame(maxWidth:.infinity).overlay{RoundedRectangle(cornerRadius:10).strokeBorder(popupStyle==value ? Color.accentColor.opacity(0.65):Color.primary.opacity(0.1),lineWidth:popupStyle==value ? 1.5:0.5)}
        }.buttonStyle(.plain).accessibilityLabel(L(title)).accessibilityAddTraits(popupStyle==value ? .isSelected:[])
    }
    private func swatch(_ value:String,title:String,color:Color)->some View {
        Button {ink=value} label:{Circle().fill(color).frame(width:19,height:19).padding(3).overlay{Circle().strokeBorder(ink==value ? Color.primary.opacity(0.7):.clear,lineWidth:1)}}.buttonStyle(.plain).help(L(title)).accessibilityLabel(L(title)).accessibilityAddTraits(ink==value ? .isSelected:[])
    }
    private var preview:some View {
        ZStack {
            HStack(spacing:0) {Color(red:0.77,green:0.83,blue:0.88);Color(red:0.88,green:0.83,blue:0.73)}.opacity(0.45)
            VStack(alignment:.leading,spacing:10) {
                Text("serendipity").font(.system(size:12)).foregroundStyle(.secondary)
                Text(L("意外发现的美好")).font(.system(size:fontSize,weight:.medium,design:PopupAppearance.design)).foregroundStyle(PopupAppearance.ink(dark:dark))
                Divider().opacity(0.4)
                HStack {Text(L("解释"));Spacer();Image(systemName:"doc.on.doc")}.font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth:360,alignment:.leading)
                .background(Color(nsColor:dark ? .windowBackgroundColor:.textBackgroundColor).opacity(popupStyle == "glass" && !reduceTransparency && contrast != .increased ? opacity:1),in:RoundedRectangle(cornerRadius:14))
                .overlay{RoundedRectangle(cornerRadius:14).strokeBorder(.primary.opacity(0.1),lineWidth:0.5)}
                .shadow(color:.black.opacity(0.1),radius:8,y:4)
                .environment(\.colorScheme,dark ? .dark:.light)
                .padding(18)
        }.clipShape(RoundedRectangle(cornerRadius:10)).accessibilityElement(children:.ignore)
            .accessibilityLabel(L("实时预览")+" · serendipity · "+L("意外发现的美好"))
    }
}

import AppKit
import SwiftUI

/// Glass belongs to the control layer. Text pages keep a stable, legible surface.
private struct ReadableControlGlass:ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    var radius:CGFloat=9
    @ViewBuilder func body(content:Content)->some View {
        if #available(macOS 26.0,*), !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular.interactive(!reduceMotion),in:RoundedRectangle(cornerRadius:radius))
        } else {
            content.background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:radius))
                .overlay{RoundedRectangle(cornerRadius:radius).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.45:0.14),lineWidth:contrast == .increased ? 1:0.5)}
        }
    }
}
extension View {
    func readableControlGlass(radius:CGFloat=9)->some View {modifier(ReadableControlGlass(radius:radius))}
}

/// Retains the system menu, selected-item checkmark and keyboard navigation without the tinted arrow block.
struct GlassMenuPicker<Selection:Hashable,Options:View>:View {
    let title:String
    let value:String
    @Binding var selection:Selection
    @ViewBuilder var options:()->Options
    var body:some View {
        Menu {
            Picker(title,selection:$selection,content:options).pickerStyle(.inline)
        } label:{
            Text(value).font(.system(size:13)).foregroundStyle(.primary).lineLimit(1)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden)
            .padding(.leading,12).padding(.trailing,28).frame(maxWidth:.infinity).frame(height:30)
            .overlay(alignment:.trailing) {
                Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold)).foregroundStyle(.secondary)
                    .padding(.trailing,12).allowsHitTesting(false).accessibilityHidden(true)
            }.readableControlGlass()
            .accessibilityLabel(title).accessibilityValue(value).help(value)
    }
}


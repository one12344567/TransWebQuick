import SwiftUI

/// Reserves only the revealed height, while laying text out at its full size. No text scaling or fade.
private struct DisclosureLayout:Layout {
    var progress:CGFloat
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) -> CGSize {
        let size=subviews.first?.sizeThatFits(ProposedViewSize(width:proposal.width,height:nil)) ?? .zero
        return CGSize(width:size.width,height:size.height*min(1,max(0,progress)))
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        subviews.first?.place(at:bounds.origin,anchor:.topLeading,proposal:ProposedViewSize(width:bounds.width,height:nil))
    }
}
struct LookupDisclosure<Content:View>:View {
    let progress:CGFloat
    @ViewBuilder var content:()->Content
    var body:some View {
        if progress>0 {
          DisclosureLayout(progress:progress){content()}
            .clipped().contentShape(Rectangle())
            .allowsHitTesting(progress>0.95).accessibilityHidden(progress<0.95)
        }
    }
}
private final class LookupHover:ObservableObject {@Published var inside=false}
/// The clear padding is part of the button label, so the entire target accepts the first click.
struct LookupButtonStyle:ButtonStyle {
    @StateObject private var hover=LookupHover()
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius:7).fill(Color.primary.opacity(enabled ? (configuration.isPressed ? 0.12:hover.inside ? 0.06:0):0)))
            .contentShape(Rectangle()).onHover{hover.inside=$0}
            .opacity(enabled ? 1:0.45)
    }
}

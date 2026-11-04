import AppKit
import SwiftUI

/// Native blur and a bounded reading tint share the same pointer-shaped surface.
@MainActor final class LookupSurface:NSView {
    private let effect=NSVisualEffectView()
    private let tone=NSView()
    private let toneMask=CAShapeLayer()
    private let outline=CAShapeLayer()
    private let innerRim=CAShapeLayer()
    private let host:NSHostingView<LookupView>
    var pointsUp=true {didSet{needsLayout=true}}
    var pointerX:CGFloat? {didSet{needsLayout=true}}
    static let tip:CGFloat=10
    init(model:LookupModel,close:@escaping()->Void) {
        host=NSHostingView(rootView:LookupView(model:model,close:close))
        super.init(frame:.zero)
        wantsLayer=true
        effect.material = .popover;effect.blendingMode = .behindWindow;effect.state = .active
        tone.wantsLayer=true;tone.layer?.mask=toneMask
        addSubview(effect);addSubview(tone);addSubview(host)
        layer?.addSublayer(outline);layer?.addSublayer(innerRim)
        outline.fillColor=NSColor.clear.cgColor;innerRim.fillColor=NSColor.clear.cgColor
        outline.lineWidth=0.65;innerRim.lineWidth=0.5
        setAccessibilityElement(false)
    }
    required init?(coder:NSCoder){nil}
    override func layout() {
        super.layout()
        let inset:CGFloat=pointerX == nil ? 0:Self.tip
        let desiredAppearance=PopupAppearance.style == "graphite" ? NSAppearance(named:.darkAqua):nil
        if appearance?.name != desiredAppearance?.name {appearance=desiredAppearance}
        effect.frame=bounds;tone.frame=bounds
        host.frame=NSRect(x:0,y:pointsUp ? 0:inset,width:bounds.width,height:bounds.height-inset)
        let body=NSRect(x:0.5,y:pointsUp ? 0.5:inset+0.5,width:bounds.width-1,height:bounds.height-inset-1)
        let shape=NSBezierPath(roundedRect:body,xRadius:14,yRadius:14)
        if let pointerX {
            let x=min(max(pointerX,32),bounds.width-32)
            let base=pointsUp ? body.maxY-1:body.minY+1
            let apex=pointsUp ? bounds.maxY-0.5:0.5
            shape.move(to:NSPoint(x:x-12,y:base))
            shape.curve(to:NSPoint(x:x-3,y:apex+(pointsUp ? -1:1)),controlPoint1:NSPoint(x:x-8,y:base),controlPoint2:NSPoint(x:x-5,y:apex+(pointsUp ? -4:4)))
            shape.curve(to:NSPoint(x:x+3,y:apex+(pointsUp ? -1:1)),controlPoint1:NSPoint(x:x-1,y:apex),controlPoint2:NSPoint(x:x+1,y:apex))
            shape.curve(to:NSPoint(x:x+12,y:base),controlPoint1:NSPoint(x:x+5,y:apex+(pointsUp ? -4:4)),controlPoint2:NSPoint(x:x+8,y:base))
            shape.close()
        }
        let mask=NSImage(size:bounds.size,flipped:false){_ in NSColor.black.setFill();shape.fill();return true}
        effect.maskImage=mask
        toneMask.path=shape.cgPath
        let reduce=NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let darkSurface=effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let color=darkSurface ? NSColor(calibratedWhite:0.16,alpha:1):NSColor(calibratedWhite:0.985,alpha:1)
        tone.layer?.backgroundColor=color.withAlphaComponent(PopupAppearance.style == "glass" && !reduce ? PopupAppearance.opacity:1).cgColor
        // The OS supplies the material and window shadow. The subtle rim adds definition on white pages.
        let dark=effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        outline.path=CGPath(roundedRect:body,cornerWidth:14,cornerHeight:14,transform:nil)
        outline.strokeColor=NSColor.black.withAlphaComponent(dark ? 0.3:0.13).cgColor
        innerRim.path=CGPath(roundedRect:body.insetBy(dx:0.8,dy:0.8),cornerWidth:13,cornerHeight:13,transform:nil)
        innerRim.strokeColor=NSColor.white.withAlphaComponent(dark ? 0.14:0.62).cgColor
        window?.invalidateShadow()
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();needsLayout=true}
}

/// A click-through visual overlay. It neither edits nor selects text in the originating app.
@MainActor final class WordHighlight {
    private let window:NSPanel
    private var generation=UUID()
    init() {
        window=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=false
        window.ignoresMouseEvents=true;window.hidesOnDeactivate=false;window.isReleasedWhenClosed=false
        window.level = .floating;window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let view=NSView();view.wantsLayer=true;view.layer?.cornerRadius=4
        view.layer?.backgroundColor=NSColor(calibratedRed:1,green:0.88,blue:0.04,alpha:0.42).cgColor
        view.layer?.borderWidth=0.6;view.layer?.borderColor=NSColor(calibratedRed:0.78,green:0.56,blue:0,alpha:0.25).cgColor
        view.setAccessibilityElement(false);window.contentView=view
    }
    func show(rect:CGRect) {
        generation=UUID()
        guard rect.width.isFinite,rect.height.isFinite,rect.width>1,rect.height>4,rect.width<800,rect.height<100 else{hide();return}
        window.setFrame(rect.insetBy(dx:-3,dy:-1),display:false)
        window.alphaValue=0;window.orderFrontRegardless()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else{window.alphaValue=1;return}
        NSAnimationContext.runAnimationGroup{ctx in ctx.duration=0.11;window.animator().alphaValue=1}
        let spring=CASpringAnimation(keyPath:"transform.scale")
        spring.fromValue=0.95;spring.toValue=1;spring.mass=1;spring.stiffness=420;spring.damping=30;spring.duration=0.24
        window.contentView?.layer?.add(spring,forKey:"pressHighlight")
    }
    func hide() {
        let current=UUID();generation=current
        guard window.isVisible else{return}
        NSAnimationContext.runAnimationGroup({ctx in
            ctx.duration=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0:0.1;window.animator().alphaValue=0
        },completionHandler:{[weak self] in Task { @MainActor in guard let self,self.generation==current else{return};self.window.orderOut(nil) }})
    }
}

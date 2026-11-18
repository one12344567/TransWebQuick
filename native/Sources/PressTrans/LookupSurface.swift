import AppKit
import SwiftUI
import PressTransCore

private final class LookupHostingView:NSHostingView<LookupView> {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
}
/// Native blur and a bounded reading tint share the same pointer-shaped surface.
@MainActor final class LookupSurface:NSView {
    private let effect=NSVisualEffectView()
    private let tone=NSView()
    private let toneMask=CAShapeLayer()
    private let outline=CAShapeLayer()
    private let innerRim=CAShapeLayer()
    private let host:NSHostingView<LookupView>
    private struct MaskGeometry: Equatable {
        var width: CGFloat
        var pointerX: CGFloat?
        var pointsUp: Bool
    }

    private var maskGeometry: MaskGeometry?
    private var surfaceSize = CGSize.zero
    private var appearanceNeedsUpdate = true
    var pointsUp = true { didSet { if oldValue != pointsUp { needsLayout = true } } }
    var pointerX: CGFloat? { didSet { if oldValue != pointerX { needsLayout = true } } }
    static let tip:CGFloat=10
    init(model:LookupModel,close:@escaping()->Void) {
        host=LookupHostingView(rootView:LookupView(model:model,close:close))
        super.init(frame:.zero)
        wantsLayer=true
        host.sizingOptions=[];host.clipsToBounds=true
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
        guard bounds.width > 1, bounds.height > 1 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if appearanceNeedsUpdate {
            appearanceNeedsUpdate = false
            updateSurfaceAppearance()
        }

        let geometry = MaskGeometry(
            width: bounds.width,
            pointerX: pointerX.map { min(max($0, 32), bounds.width - 32) },
            pointsUp: pointsUp
        )
        let needsMask = geometry != maskGeometry
        guard needsMask || surfaceSize != bounds.size else { return }
        surfaceSize = bounds.size
        maskGeometry = geometry

        let inset = geometry.pointerX == nil ? 0 : Self.tip
        effect.frame = bounds
        tone.frame = bounds
        host.frame = NSRect(x: 0, y: pointsUp ? 0 : inset, width: bounds.width, height: max(0, bounds.height - inset))
        host.layoutSubtreeIfNeeded()

        if needsMask {
            effect.maskImage = Self.materialMask(for: geometry)
            // AppKit follows window resizes. The silhouette can also change without a frame change.
            window?.invalidateShadow()
        }
        let body = Self.bodyRect(size: bounds.size, geometry: geometry)
        toneMask.path = Self.silhouette(size: bounds.size, geometry: geometry).cgPath
        outline.path = CGPath(roundedRect: body, cornerWidth: 14, cornerHeight: 14, transform: nil)
        innerRim.path = CGPath(roundedRect: body.insetBy(dx: 0.8, dy: 0.8), cornerWidth: 13, cornerHeight: 13, transform: nil)
    }

    private static func bodyRect(size: CGSize, geometry: MaskGeometry) -> CGRect {
        let inset = geometry.pointerX == nil ? 0 : tip
        return CGRect(x: 0.5, y: geometry.pointsUp ? 0.5 : inset + 0.5,
                      width: size.width - 1, height: max(0, size.height - inset - 1))
    }

    private static func silhouette(size: CGSize, geometry: MaskGeometry) -> NSBezierPath {
        let body = bodyRect(size: size, geometry: geometry)
        let shape = NSBezierPath(roundedRect: body, xRadius: 14, yRadius: 14)
        if let x = geometry.pointerX {
            let up = geometry.pointsUp
            let base = up ? body.maxY - 1 : body.minY + 1
            let apex = up ? size.height - 0.5 : 0.5
            shape.move(to: NSPoint(x: x - 12, y: base))
            shape.curve(to: NSPoint(x: x - 3, y: apex + (up ? -1 : 1)),
                        controlPoint1: NSPoint(x: x - 8, y: base), controlPoint2: NSPoint(x: x - 5, y: apex + (up ? -4 : 4)))
            shape.curve(to: NSPoint(x: x + 3, y: apex + (up ? -1 : 1)),
                        controlPoint1: NSPoint(x: x - 1, y: apex), controlPoint2: NSPoint(x: x + 1, y: apex))
            shape.curve(to: NSPoint(x: x + 12, y: base),
                        controlPoint1: NSPoint(x: x + 5, y: apex + (up ? -4 : 4)), controlPoint2: NSPoint(x: x + 8, y: base))
            shape.close()
        }
        return shape
    }

    private static func materialMask(for geometry: MaskGeometry) -> NSImage {
        // Both caps contain the complete pointer and corner, including their antialiased edge.
        // Only the straight strip between them stretches as the panel changes height.
        let cap: CGFloat = tip + 14 + 2
        let size = NSSize(width: geometry.width, height: cap * 2 + 1)
        let shape = silhouette(size: size, geometry: geometry)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            shape.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cap, left: 0, bottom: cap, right: 0)
        image.resizingMode = .stretch
        return image
    }

    func invalidateSurfaceAppearance() {
        appearanceNeedsUpdate = true
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        invalidateSurfaceAppearance()
    }

    private func updateSurfaceAppearance() {
        let style = PopupAppearance.style
        let override = style == "graphite" ? NSAppearance(named: .darkAqua) : nil
        if appearance?.name != override?.name { appearance = override }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let workspace = NSWorkspace.shared
        let opaque = workspace.accessibilityDisplayShouldReduceTransparency || workspace.accessibilityDisplayShouldIncreaseContrast
        let opacity = style == "glass" && !opaque ? PopupAppearance.opacity : 1
        tone.layer?.backgroundColor = NSColor(calibratedWhite: dark ? 0.16 : 0.985, alpha: opacity).cgColor
        outline.strokeColor = NSColor.black.withAlphaComponent(dark ? 0.3 : 0.13).cgColor
        innerRim.strokeColor = NSColor.white.withAlphaComponent(dark ? 0.14 : 0.62).cgColor
    }

    func animateReveal() {
        guard let layer else{return}
        layer.removeAnimation(forKey:"lookupReveal")
        let pivot=CGPoint(x:pointerX ?? bounds.midX,y:pointsUp ? bounds.maxY:bounds.minY)
        let x=pivot.x-layer.anchorPoint.x*bounds.width,y=pivot.y-layer.anchorPoint.y*bounds.height
        var start=CATransform3DMakeTranslation(x,y,0)
        start=CATransform3DScale(start,0.96,0.96,1)
        start=CATransform3DTranslate(start,-x,-y,0)
        let spring=CASpringAnimation(keyPath:"transform")
        spring.fromValue=NSValue(caTransform3D:start);spring.toValue=NSValue(caTransform3D:CATransform3DIdentity)
        spring.mass=1;spring.stiffness=320;spring.damping=34;spring.initialVelocity=0;spring.duration=0.4
        layer.add(spring,forKey:"lookupReveal")
    }
}

/// A click-through visual overlay. It neither edits nor selects text in the originating app.
@MainActor final class WordHighlight {
    private let window:NSPanel
    private var generation=UUID()
    private let fill=CAShapeLayer()
    private let imageView=NSImageView()
    private var maskTask:Task<Void,Never>?
    init() {
        window=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=false
        window.ignoresMouseEvents=true;window.hidesOnDeactivate=false;window.isReleasedWhenClosed=false
        window.level = .floating;window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let view=NSView();view.wantsLayer=true
        fill.fillColor=NSColor.clear.cgColor
        fill.strokeColor=NSColor(calibratedRed:0.96,green:0.71,blue:0.02,alpha:0.95).cgColor;fill.lineWidth=1.25
        view.layer?.addSublayer(fill)
        imageView.imageScaling = .scaleAxesIndependently;imageView.setAccessibilityElement(false);view.addSubview(imageView)
        view.setAccessibilityElement(false);window.contentView=view
    }
    func show(rects:[CGRect]) {
        maskTask?.cancel();maskTask=nil;generation=UUID()
        let current=generation
        window.orderOut(nil);imageView.image=nil
        let aligned=rects.prefix(24).compactMap {rect->CGRect? in
            guard rect.width>1,rect.height>4,rect.width<1600,rect.height<60,
                  let screen=NSScreen.screens.first(where:{$0.frame.intersects(rect)}) else{return nil}
            return HighlightGeometry.aligned(rect.intersection(screen.frame),scale:screen.backingScaleFactor)
        }
        guard let first=aligned.first else{hide();return}
        let frame=aligned.dropFirst().reduce(first){$0.union($1)}
        window.setFrame(frame,display:false)
        let path=CGMutablePath()
        for rect in aligned {path.addRoundedRect(in:rect.offsetBy(dx:-frame.minX,dy:-frame.minY).insetBy(dx:0.25,dy:0.25),cornerWidth:min(2,rect.height*0.1),cornerHeight:min(2,rect.height*0.1))}
        CATransaction.begin();CATransaction.setDisableActions(true)
        fill.frame=CGRect(origin:.zero,size:frame.size);fill.path=path
        CATransaction.commit()
        imageView.frame=CGRect(origin:.zero,size:frame.size)
        let precise=UserDefaults.standard.object(forKey:"preciseHighlightEnabled") as? Bool ?? true
        if precise,CGPreflightScreenCaptureAccess() {
            let top=NSScreen.screens.first?.frame.maxY ?? 0
            let region=HighlightGeometry.appKitRect(frame,primaryTop:top)
            let targets=aligned.map{HighlightGeometry.appKitRect($0,primaryTop:top)}
            maskTask=Task { [weak self] in
                let mask=await GlyphHighlightCapture.shared.mask(region:region,targets:targets)
                guard let self,!Task.isCancelled,self.generation==current else{return}
                self.fill.isHidden=mask != nil
                self.imageView.image=mask.map{NSImage(cgImage:$0,size:frame.size)}
                self.reveal()
            }
        } else {fill.isHidden=false;reveal()}
    }
    private func reveal() {
        window.alphaValue=0;window.orderFrontRegardless()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else{window.alphaValue=1;return}
        // Geometry stays fixed throughout the reveal, so the original glyphs never drift relative to the tint.
        NSAnimationContext.runAnimationGroup{ctx in ctx.duration=0.14;ctx.timingFunction=CAMediaTimingFunction(name:.easeOut);window.animator().alphaValue=1}
    }
    func hide() {
        maskTask?.cancel();maskTask=nil
        let current=UUID();generation=current
        guard window.isVisible else{imageView.image=nil;return}
        NSAnimationContext.runAnimationGroup({ctx in
            ctx.duration=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0:0.1;window.animator().alphaValue=0
        },completionHandler:{[weak self] in Task { @MainActor in guard let self,self.generation==current else{return};self.window.orderOut(nil);self.imageView.image=nil }})
    }
}

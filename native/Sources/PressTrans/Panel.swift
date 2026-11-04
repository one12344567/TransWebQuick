import AppKit
import SwiftUI
import Combine
import PressTransCore

final class LookupPanel:NSPanel {
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { false }
    var dismiss:(()->Void)?
    override func cancelOperation(_ sender:Any?) { dismiss?() }
}
@MainActor final class PanelController:NSObject {
    let model=LookupModel()
    private var panel:LookupPanel!
    private var globalMonitor:Any?, localMonitor:Any?
    private var observers:[NSObjectProtocol]=[]
    private var visibility=UUID()
    private var changes:AnyCancellable?
    private var anchor:CGRect?
    private var lastDisclosure=[false,false,false]
    private var panelHeight:CGFloat=154
    private var presentationPoint=CGPoint.zero
    private var displayLink:CADisplayLink?
    private var lastFrameTime:CFTimeInterval=0
    private var heightMotion=DisclosureMotion(154)
    private var detailMotion=DisclosureMotion(0),contextMotion=DisclosureMotion(0),dictionaryMotion=DisclosureMotion(0)
    private var applyingPresentation=false
    private var resizeQueued=false
    private var dismissing=false
    private var menuTracking=false
    private var surface:LookupSurface!
    private let highlight=WordHighlight()
    private var placedBelow=true
    private var showTask:Task<Void,Never>?
    private func desiredHeight() -> CGFloat {
        func height(_ text:String,_ font:NSFont,spacing:CGFloat=0)->CGFloat {
            guard !text.isEmpty else{return 0}
            let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=spacing
            return ceil((text as NSString).boundingRect(with:NSSize(width:340,height:4000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font,.paragraphStyle:paragraph]).height)
        }
        let parts=AnswerParts.split(model.answer)
        // Header, padding and toolbar stay fixed; only visible content contributes to height.
        var result:CGFloat=115 // padding 26 + header 32 + gap 8 + divider/gaps 13 + toolbar 36
        if model.loading && model.answer.isEmpty {result+=28}
        result+=height(parts.meaning,PopupAppearance.nsFont(size:PopupAppearance.size,weight:.medium),spacing:3)
        if model.expanded {
            var sections:[CGFloat]=[]
            if !parts.explanation.isEmpty {sections.append(height(parts.explanation,PopupAppearance.nsFont(size:max(12,PopupAppearance.size*0.7)),spacing:4))}
            if !model.matchNote.isEmpty {sections.append(height(model.matchNote,.systemFont(ofSize:11)))}
            if !model.dictionaryText.isEmpty {sections.append(32 + (model.dictionaryExpanded ? 16+height(model.dictionaryText,.systemFont(ofSize:12),spacing:4)+height(model.dictionaryNote,.systemFont(ofSize:11)):0))}
            if !model.context.isEmpty {sections.append(32 + (model.contextExpanded ? 8+height(model.context,.systemFont(ofSize:12),spacing:4)+(!model.source.isEmpty && !model.preview ? 22:0):0))}
            if model.usageRecord != nil {sections.append(28)}
            result+=sections.reduce(0,+)+CGFloat(sections.count)*14
        }
        if !model.message.isEmpty && !model.loading && (model.expanded || model.answer.isEmpty) {result+=14+height(model.message,.systemFont(ofSize:12))}
        let screen=screenAnchor().flatMap{area in NSScreen.screens.first(where:{$0.frame.intersects(area)})} ?? NSScreen.main
        return min(max(result,154),min(model.expanded ? 560:320,(screen?.visibleFrame.height ?? 800)-40))
    }
    private func screenAnchor()->CGRect? {
        guard let anchor,let primary=NSScreen.screens.first else{return nil}
        return HighlightGeometry.appKitRect(anchor,primaryTop:primary.frame.maxY)
    }
    private func targetFrame() -> NSRect {
        let area=screenAnchor() ?? NSRect(origin:presentationPoint,size:.zero)
        let screen=NSScreen.screens.first(where:{$0.frame.intersects(area) || $0.frame.contains(area.origin)}) ?? NSScreen.main!
        let bounds=screen.visibleFrame, height=panelHeight+(anchor == nil ? 0:LookupSurface.tip)
        let y=placedBelow ? area.minY-height-6:area.maxY+6
        let frame=NSRect(x:min(max(area.midX-190,bounds.minX+12),bounds.maxX-392),y:min(max(y,bounds.minY+12),bounds.maxY-height-12),width:380,height:height)
        surface.pointsUp=placedBelow;surface.pointerX=anchor == nil ? nil:area.midX-frame.minX
        return frame
    }
    private func resize() {
        guard panel.isVisible,!dismissing else{return}
        let disclosure=[model.expanded,model.contextExpanded,model.dictionaryExpanded]
        let interactive=lastDisclosure != disclosure
        var height=desiredHeight()
        if model.loading && !interactive {height=max(CGFloat(heightMotion.target),ceil(height/16)*16)}
        guard interactive || abs(height-CGFloat(heightMotion.target))>1 else{return}
        lastDisclosure=disclosure
        heightMotion.retarget(Double(height));detailMotion.retarget(model.expanded ? 1:0)
        contextMotion.retarget(model.contextExpanded ? 1:0);dictionaryMotion.retarget(model.dictionaryExpanded ? 1:0)
        if (interactive || displayLink != nil) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if displayLink==nil {
                lastFrameTime=CACurrentMediaTime()
                displayLink=surface.displayLink(target:self,selector:#selector(advanceLayout(_:)))
                displayLink?.add(to:.main,forMode:.common)
            }
        } else {finishLayout()}
    }
    @objc private func advanceLayout(_ link:CADisplayLink) {
        guard panel.isVisible else{stopLayout();return}
        let now=CACurrentMediaTime(),dt=max(0,now-lastFrameTime);lastFrameTime=now
        heightMotion.advance(dt);detailMotion.advance(dt);contextMotion.advance(dt);dictionaryMotion.advance(dt)
        applyLayout()
        if abs(heightMotion.value-heightMotion.target)<0.15 && abs(heightMotion.velocity)<2 && detailMotion.settled && contextMotion.settled && dictionaryMotion.settled {finishLayout()}
    }
    private func applyLayout() {
        applyingPresentation=true
        CATransaction.begin();CATransaction.setDisableActions(true)
        var transaction=Transaction(animation:nil);transaction.disablesAnimations=true
        withTransaction(transaction) {
            model.disclosure = .init(detail:min(1,max(0,detailMotion.value)),context:min(1,max(0,contextMotion.value)),dictionary:min(1,max(0,dictionaryMotion.value)))
            panelHeight=heightMotion.value
            panel.setFrame(targetFrame(),display:false)
            surface.layoutSubtreeIfNeeded()
        }
        CATransaction.commit()
        applyingPresentation=false
    }
    private func finishLayout() {
        stopLayout()
        heightMotion.snap(heightMotion.target);detailMotion.snap(detailMotion.target)
        contextMotion.snap(contextMotion.target);dictionaryMotion.snap(dictionaryMotion.target)
        applyLayout()
    }
    private func stopLayout() {displayLink?.invalidate();displayLink=nil}
    override init() {
        super.init()
        panel=LookupPanel(contentRect:NSRect(x:0,y:0,width:380,height:440),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="PressTrans";panel.setAccessibilityRole(.window);panel.setAccessibilitySubrole(.floatingWindow)
        panel.level = .floating; panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=true
        panel.isReleasedWhenClosed=false; panel.hidesOnDeactivate=false; panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        surface=LookupSurface(model:model,close:{[weak self] in self?.hide()});panel.contentView=surface
        panel.dismiss={ [weak self] in self?.hide() }
        model.onDisclosureChange={[weak self] in self?.resize()}
        changes=model.objectWillChange.sink { [weak self] _ in
            guard let self,!self.applyingPresentation,!self.resizeQueued else{return}
            self.resizeQueued=true
            // Coalesce one model update, without delaying a user's click behind streaming throttling.
            DispatchQueue.main.async { [weak self] in self?.resizeQueued=false;self?.resize() }
        }
        globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.scrollWheel,.keyDown]) { [weak self] event in
            Task { @MainActor in if self?.menuTracking != true && (event.type != .keyDown || event.keyCode==53) { self?.hide() } }
        }
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.leftMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible, !self.menuTracking else { return event }
            if event.type == .keyDown && event.keyCode==53 { self.hide(); return nil }
            if event.type == .leftMouseDown && event.window !== self.panel { self.hide() }
            return event
        }
        observers.append(NotificationCenter.default.addObserver(forName:UserDefaults.didChangeNotification,object:nil,queue:.main){[weak self] _ in
            Task { @MainActor in self?.surface.needsLayout=true;self?.resize() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main){[weak self] _ in Task { @MainActor in self?.surface.needsLayout=true;if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {self?.finishLayout()} }})
        observers.append(NotificationCenter.default.addObserver(forName:NSMenu.didBeginTrackingNotification,object:nil,queue:.main){[weak self] _ in MainActor.assumeIsolated {self?.menuTracking=true}})
        observers.append(NotificationCenter.default.addObserver(forName:NSMenu.didEndTrackingNotification,object:nil,queue:.main){[weak self] _ in MainActor.assumeIsolated {self?.menuTracking=false}})
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main){[weak self] note in
            if let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier { Task { @MainActor in self?.hide() } }
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main){[weak self] _ in Task { @MainActor in self?.hide() }})
    }
    func show(anchor:CGRect?=nil,highlightRects:[CGRect]=[]) {
        showTask?.cancel();stopLayout();visibility=UUID();dismissing=false
        self.anchor=anchor
        presentationPoint=NSEvent.mouseLocation
        panelHeight=desiredHeight();lastDisclosure=[model.expanded,model.contextExpanded,model.dictionaryExpanded]
        heightMotion.snap(panelHeight);detailMotion.snap(model.expanded ? 1:0)
        contextMotion.snap(model.contextExpanded ? 1:0);dictionaryMotion.snap(model.dictionaryExpanded ? 1:0)
        model.disclosure = .init(detail:detailMotion.value,context:contextMotion.value,dictionary:dictionaryMotion.value)
        if let area=screenAnchor() {
            let bounds=(NSScreen.screens.first(where:{$0.frame.intersects(area)}) ?? NSScreen.main!).visibleFrame
            placedBelow=area.minY-bounds.minY >= min(400,panelHeight)+20
            let fragments=highlightRects.isEmpty ? [area]:highlightRects.map{HighlightGeometry.appKitRect($0,primaryTop:NSScreen.screens.first?.frame.maxY ?? 0)}
            highlight.show(rects:fragments)
        } else {placedBelow=true;highlight.hide()}
        let target=targetFrame(), reduce=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.orderOut(nil);panel.alphaValue=0
        panel.setFrame(target,display:false)
        surface.layoutSubtreeIfNeeded()
        let current=visibility
        showTask=Task { [weak self] in
            if !reduce && anchor != nil {try? await Task.sleep(nanoseconds:35_000_000)}
            guard let self,!Task.isCancelled,self.visibility==current else{return}
            if self.model.preview {self.panel.makeKeyAndOrderFront(nil)} else {self.panel.orderFrontRegardless()}
            NSAnimationContext.runAnimationGroup({ctx in
                ctx.duration=reduce ? 0:0.16;ctx.timingFunction=CAMediaTimingFunction(name:.easeOut)
                self.panel.animator().alphaValue=1
            },completionHandler:nil)
            if !reduce {
                self.surface.animateReveal()
            }
        }
    }
    func hide() {
        dismissing=true;showTask?.cancel();showTask=nil;stopLayout();highlight.hide()
        guard panel.isVisible else {visibility=UUID();model.cancel();return}
        model.cancel(); let id=UUID(); visibility=id
        NSAnimationContext.runAnimationGroup({ context in
            context.duration=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0:0.10
            panel.animator().alphaValue=0
        },completionHandler:{[weak self] in
            Task { @MainActor in guard let self,self.visibility==id else{return}; self.panel.orderOut(nil); self.model.clear() }
        })
    }
}

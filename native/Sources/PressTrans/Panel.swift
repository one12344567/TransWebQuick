import AppKit
import SwiftUI
import Combine
import PressTransCore
import PressTransCore

final class LookupPanel:NSPanel {
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { false }
    var dismiss:(()->Void)?
    override func cancelOperation(_ sender:Any?) { dismiss?() }
}
@MainActor final class PanelController {
    let model=LookupModel()
    private var panel:LookupPanel!
    private var globalMonitor:Any?, localMonitor:Any?
    private var observers:[NSObjectProtocol]=[]
    private var visibility=UUID()
    private var changes:AnyCancellable?
    private var anchor:CGRect?
    private var lastExpanded=false
    private var menuTracking=false
    private var surface:LookupSurface!
    private let highlight=WordHighlight()
    private var placedBelow=true
    private var showTask:Task<Void,Never>?
    private func desiredHeight() -> CGFloat {
        func height(_ text:String,_ font:NSFont,spacing:CGFloat=0)->CGFloat {
            guard !text.isEmpty else{return 0}
            let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=spacing
            return ceil((text as NSString).boundingRect(with:NSSize(width:330,height:4000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font,.paragraphStyle:paragraph]).height)
        }
        let parts=AnswerParts.split(model.answer)
        // Header, padding and toolbar stay fixed; only visible content contributes to height.
        var result:CGFloat=92 + min(height(model.selection,.systemFont(ofSize:12)),model.expanded ? 45:30)
        if model.loading && model.answer.isEmpty {result+=28}
        result+=height(parts.meaning,PopupAppearance.nsFont(size:PopupAppearance.size,weight:.medium),spacing:3)
        if model.expanded {
            result+=20
            if !parts.explanation.isEmpty {result+=14+height(parts.explanation,PopupAppearance.nsFont(size:max(12,PopupAppearance.size*0.7)),spacing:4)}
            if !model.matchNote.isEmpty {result+=14+height(model.matchNote,.systemFont(ofSize:11))}
            if !model.dictionaryText.isEmpty {result+=28}
            if model.dictionaryExpanded {result+=28+height(model.dictionaryText,.systemFont(ofSize:12),spacing:4)+height(model.dictionaryNote,.systemFont(ofSize:11))}
            if model.usageRecord != nil {result+=40}
            if model.contextExpanded && !model.source.isEmpty && !model.preview {result+=28}
            if !model.context.isEmpty {result+=28}
            if model.contextExpanded {result+=14+height(model.context,.systemFont(ofSize:12),spacing:4)}
        }
        if !model.message.isEmpty && !model.loading && (model.expanded || model.answer.isEmpty) {result+=14+height(model.message,.systemFont(ofSize:12))}
        let screen=screenAnchor().flatMap{area in NSScreen.screens.first(where:{$0.frame.intersects(area)})} ?? NSScreen.main
        return min(max(result,142),min(model.expanded ? 560:320,(screen?.visibleFrame.height ?? 800)-40))
    }
    private func screenAnchor()->CGRect? {
        guard let anchor,let primary=NSScreen.screens.first else{return nil}
        return HighlightGeometry.appKitRect(anchor,primaryTop:primary.frame.maxY)
    }
    private func targetFrame() -> NSRect {
        let area=screenAnchor() ?? NSRect(origin:NSEvent.mouseLocation,size:.zero)
        let screen=NSScreen.screens.first(where:{$0.frame.intersects(area) || $0.frame.contains(area.origin)}) ?? NSScreen.main!
        let bounds=screen.visibleFrame, height=model.panelHeight+(anchor == nil ? 0:LookupSurface.tip)
        let y=placedBelow ? area.minY-height-6:area.maxY+6
        let frame=NSRect(x:min(max(area.midX-190,bounds.minX+12),bounds.maxX-392),y:min(max(y,bounds.minY+12),bounds.maxY-height-12),width:380,height:height)
        surface.pointsUp=placedBelow;surface.pointerX=anchor == nil ? nil:area.midX-frame.minX
        return frame
    }
    private func resize() {
        guard panel.isVisible else{return}
        var height=desiredHeight()
        if model.loading && lastExpanded == model.expanded {height=max(model.panelHeight,ceil(height/16)*16)}
        guard abs(height-model.panelHeight)>1 else{return}
        let animate = lastExpanded != model.expanded || !model.loading;lastExpanded=model.expanded
        model.panelHeight=height
        if animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration=0.22;ctx.timingFunction=CAMediaTimingFunction(controlPoints:0.2,0.8,0.2,1);panel.animator().setFrame(targetFrame(),display:true) }
        } else {panel.setFrame(targetFrame(),display:true)}
    }
    init() {
        panel=LookupPanel(contentRect:NSRect(x:0,y:0,width:380,height:440),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="PressTrans";panel.setAccessibilityRole(.window);panel.setAccessibilitySubrole(.floatingWindow)
        panel.level = .floating; panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=true
        panel.isReleasedWhenClosed=false; panel.hidesOnDeactivate=false; panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        surface=LookupSurface(model:model,close:{[weak self] in self?.hide()});panel.contentView=surface
        panel.dismiss={ [weak self] in self?.hide() }
        changes=model.objectWillChange.throttle(for:.milliseconds(100),scheduler:RunLoop.main,latest:true).sink { [weak self] _ in
            // Published notifications precede assignment. Resize on the next run-loop turn.
            DispatchQueue.main.async {self?.resize()}
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
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main){[weak self] _ in Task { @MainActor in self?.surface.needsLayout=true }})
        observers.append(NotificationCenter.default.addObserver(forName:NSMenu.didBeginTrackingNotification,object:nil,queue:.main){[weak self] _ in MainActor.assumeIsolated {self?.menuTracking=true}})
        observers.append(NotificationCenter.default.addObserver(forName:NSMenu.didEndTrackingNotification,object:nil,queue:.main){[weak self] _ in MainActor.assumeIsolated {self?.menuTracking=false}})
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main){[weak self] note in
            if let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier { Task { @MainActor in self?.hide() } }
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main){[weak self] _ in Task { @MainActor in self?.hide() }})
    }
    func show(anchor:CGRect?=nil,highlightRects:[CGRect]=[]) {
        showTask?.cancel();visibility=UUID()
        self.anchor=anchor
        model.panelHeight=desiredHeight();lastExpanded=model.expanded
        if let area=screenAnchor() {
            let bounds=(NSScreen.screens.first(where:{$0.frame.intersects(area)}) ?? NSScreen.main!).visibleFrame
            placedBelow=area.minY-bounds.minY >= min(400,model.panelHeight)+20
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
        showTask?.cancel();showTask=nil;highlight.hide()
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

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
@MainActor final class PanelController {
    let model=LookupModel()
    private var panel:LookupPanel!
    private var globalMonitor:Any?, localMonitor:Any?
    private var observers:[NSObjectProtocol]=[]
    private var visibility=UUID()
    private var changes:AnyCancellable?
    private var anchor:CGRect?
    private var lastExpanded=false
    private func desiredHeight() -> CGFloat {
        func height(_ text:String,_ font:NSFont)->CGFloat {
            guard !text.isEmpty else{return 0}
            return ceil((text as NSString).boundingRect(with:NSSize(width:360,height:2000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height)
        }
        let parts=AnswerParts.split(model.answer)
        var result:CGFloat=150 + height(model.selection.isEmpty ? "选中，就读懂。":model.selection,.systemFont(ofSize:20,weight:.semibold))
        if !model.source.isEmpty {result+=30}
        if model.loading && model.answer.isEmpty {result+=58}
        result+=height(parts.meaning,.systemFont(ofSize:21,weight:.medium))*1.15
        if !parts.explanation.isEmpty {result+=16+height(parts.explanation,.systemFont(ofSize:14))*1.3}
        if !model.matchNote.isEmpty {result+=height(model.matchNote,.systemFont(ofSize:11))+16}
        if !model.message.isEmpty && !model.loading {result+=height(model.message,.systemFont(ofSize:12))+16}
        if !model.context.isEmpty {result+=34}
        if model.expanded {result+=height(model.context,.systemFont(ofSize:12))*1.3+30}
        return min(max(result,240),min(580,(NSScreen.main?.visibleFrame.height ?? 800)-24))
    }
    private func targetFrame() -> NSRect {
        let mouse=NSEvent.mouseLocation
        var area=NSRect(origin:mouse,size:.zero)
        if let anchor, let primary=NSScreen.screens.first {area=NSRect(x:anchor.minX,y:primary.frame.maxY-anchor.maxY,width:anchor.width,height:anchor.height)}
        let screen=NSScreen.screens.first(where:{$0.frame.intersects(area) || $0.frame.contains(area.origin)}) ?? NSScreen.main!
        let bounds=screen.visibleFrame, height=model.panelHeight
        let y=area.maxY+12+height<=bounds.maxY-12 ? area.maxY+12 : area.minY-height-12
        return NSRect(x:min(max(area.minX,bounds.minX+12),bounds.maxX-420),y:min(max(y,bounds.minY+12),bounds.maxY-height-12),width:408,height:height)
    }
    private func resize() {
        guard panel.isVisible else{return}
        let height=desiredHeight()
        guard abs(height-model.panelHeight)>1 else{return}
        let animate=model.expanded != lastExpanded;lastExpanded=model.expanded
        model.panelHeight=height
        if animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration=0.18;panel.animator().setFrame(targetFrame(),display:true) }
        } else {panel.setFrame(targetFrame(),display:true)}
    }
    init() {
        panel=LookupPanel(contentRect:NSRect(x:0,y:0,width:408,height:440),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .floating; panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=true
        panel.isReleasedWhenClosed=false; panel.hidesOnDeactivate=false; panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.contentView=NSHostingView(rootView:LookupView(model:model,close:{ [weak self] in self?.hide() }))
        panel.dismiss={ [weak self] in self?.hide() }
        changes=model.objectWillChange.debounce(for:.milliseconds(40),scheduler:RunLoop.main).sink { [weak self] _ in self?.resize() }
        globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.scrollWheel,.keyDown]) { [weak self] event in
            Task { @MainActor in if event.type != .keyDown || event.keyCode==53 { self?.hide() } }
        }
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.leftMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown && event.keyCode==53 { self.hide(); return nil }
            if event.type == .leftMouseDown && event.window !== self.panel { self.hide() }
            return event
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main){[weak self] note in
            if let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier { Task { @MainActor in self?.hide() } }
        })
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main){[weak self] _ in Task { @MainActor in self?.hide() }})
    }
    func show(anchor:CGRect?=nil) {
        visibility=UUID()
        self.anchor=anchor
        model.panelHeight=desiredHeight();lastExpanded=model.expanded
        let target=targetFrame()
        panel.setFrame(target.offsetBy(dx:0,dy:-5),display:false); panel.alphaValue=0; panel.orderFrontRegardless()
        let reduce=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration=reduce ? 0:0.16; context.timingFunction=CAMediaTimingFunction(name:.easeOut)
            panel.animator().setFrame(target,display:true); panel.animator().alphaValue=1
        }
    }
    func hide() {
        guard panel.isVisible else { return }
        model.cancel(); let id=UUID(); visibility=id
        NSAnimationContext.runAnimationGroup({ context in
            context.duration=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0:0.10
            panel.animator().alphaValue=0
        },completionHandler:{[weak self] in
            Task { @MainActor in guard let self,self.visibility==id else{return}; self.panel.orderOut(nil); self.model.clear() }
        })
    }
}

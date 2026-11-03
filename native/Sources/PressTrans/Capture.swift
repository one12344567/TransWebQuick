import AppKit
import ApplicationServices
import PressTransCore

struct CaptureResult { let context: CapturedContext; let anchor: CGRect?; let processID: pid_t }
enum CaptureFailure: LocalizedError {
    case permission, noSelection, secure, unsupported
    var errorDescription: String? {
        switch self {
        case .permission: return "先为 PressTrans 开启辅助功能权限，然后回到原应用选中文字。"
        case .noSelection: return "没有读到选中文字。请先选中一个词或句子，再按 ⌥⇧T。"
        case .secure: return "此处是受保护的输入区域，无法查询。"
        case .unsupported: return "未能直接读取指针下的文字。可在设置中开启屏幕识字，或选中文字后按 ⌥⇧T。"
        }
    }
}
final class TextCapture {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    static func capture(processID:pid_t, appName:String, point:CGPoint?=nil) throws -> CaptureResult {
        guard AXIsProcessTrusted() else { throw CaptureFailure.permission }
        let root = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(root, 0.3)
        if let point {
            var hit:AXUIElement?
            if AXUIElementCopyElementAtPosition(root,Float(point.x),Float(point.y),&hit) == .success {
                var candidate=hit
                for _ in 0..<24 {
                    guard let element=candidate else{break}
                    try rejectSecure(element)
                    if let result=try captureMarkers(element,processID:processID,appName:appName,point:point) {return result}
                    do {return try captureElement(element,processID:processID,appName:appName,point:point)}
                    catch CaptureFailure.secure {throw CaptureFailure.secure}
                    catch {}
                    if let result=captureStaticText(element,processID:processID,appName:appName,point:point) {return result}
                    guard let parent=value(element,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{break}
                    candidate=(parent as! AXUIElement)
                }
            }
        }
        guard let focusedValue=value(root,kAXFocusedUIElementAttribute),CFGetTypeID(focusedValue)==AXUIElementGetTypeID() else{throw CaptureFailure.unsupported}
        var focused:AXUIElement?=(focusedValue as! AXUIElement)
        for _ in 0..<24 {
            guard let element=focused else{break}
            try rejectSecure(element)
            if let result=try captureMarkers(element,processID:processID,appName:appName,point:point) {return result}
            do {return try captureElement(element,processID:processID,appName:appName,point:point)}
            catch CaptureFailure.secure {throw CaptureFailure.secure}
            catch {}
            guard let parent=value(element,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{break}
            focused=(parent as! AXUIElement)
        }
        throw point == nil ? CaptureFailure.noSelection:CaptureFailure.unsupported
    }
    private static func rejectSecure(_ element:AXUIElement) throws {
        if (value(element,kAXSubroleAttribute) as? String)==kAXSecureTextFieldSubrole {throw CaptureFailure.secure}
    }
    private static func parameter(_ element:AXUIElement,_ name:String,_ argument:CFTypeRef)->CFTypeRef? {
        var result:CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(element,name as CFString,argument,&result) == .success ? result:nil
    }
    // Some browser engines expose glyph bounds but not point -> text marker.
    // Inspect only the hit text leaf, with a bounded number of range queries.
    private static func captureStaticText(_ element:AXUIElement,processID:pid_t,appName:String,point:CGPoint)->CaptureResult? {
        let role=value(element,kAXRoleAttribute) as? String
        guard role==kAXStaticTextRole || role=="AXLink" else{return nil}
        var text:String?
        if let range=parameter(element,"AXTextMarkerRangeForUIElement",element),
           let count=parameter(element,"AXLengthForTextMarkerRange",range) as? NSNumber,count.intValue>0,count.intValue<=3000 {
            text=parameter(element,"AXStringForTextMarkerRange",range) as? String
        }
        if text == nil {text=value(element,kAXValueAttribute) as? String}
        guard let text,!text.isEmpty,text.utf16.count<=3000 else{return nil}
        let deadline=Date().addingTimeInterval(0.35)
        var found:CaptureResult?,queries=0
        text.enumerateSubstrings(in:text.startIndex..<text.endIndex,options:.byWords) {word,wordRange,_,stop in
            guard queries<96,Date()<deadline else{stop=true;return}
            queries+=1
            let ns=NSRange(wordRange,in:text)
            var range=CFRange(location:ns.location,length:ns.length)
            guard let argument=AXValueCreate(.cfRange,&range),let box=rect(element,argument),box.width>0,box.height>0,
                  box.insetBy(dx:-1,dy:-1).contains(point),let word,
                  let context=ContextBuilder.make(selection:word,surrounding:text,sourceApp:appName) else{return}
            found=CaptureResult(context:context,anchor:box,processID:processID);stop=true
        }
        return found
    }
    private static func rect(_ element:AXUIElement,_ range:CFTypeRef)->CGRect? {
        guard let value=parameter(element,kAXBoundsForRangeParameterizedAttribute,range),CFGetTypeID(value)==AXValueGetTypeID() else{return nil}
        var rect=CGRect.zero
        return AXValueGetValue(value as! AXValue,.cgRect,&rect) ? rect:nil
    }
    // Safari/WebKit and Chromium expose page text as opaque text markers, not CFRange.
    // Keep markers inside the query; never serialize them or scan the document tree.
    private static func captureMarkers(_ element:AXUIElement,processID:pid_t,appName:String,point:CGPoint?) throws -> CaptureResult? {
        func text(_ range:CFTypeRef,limit:Int)->String? {
            guard let count=parameter(element,"AXLengthForTextMarkerRange",range) as? NSNumber,
                  count.intValue>0,count.intValue<=limit,
                  let text=parameter(element,"AXStringForTextMarkerRange",range) as? String,
                  !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return nil}
            return text
        }
        func bounds(_ range:CFTypeRef)->CGRect? {
            guard let raw=parameter(element,"AXBoundsForTextMarkerRange",range),CFGetTypeID(raw)==AXValueGetTypeID() else{return nil}
            var rect=CGRect.zero
            guard AXValueGetValue(raw as! AXValue,.cgRect,&rect),rect.width>0,rect.height>0,
                  rect.origin.x.isFinite,rect.origin.y.isFinite,rect.width.isFinite,rect.height.isFinite else{return nil}
            return rect
        }
        var selected:String?, anchor:CGRect?, marker:CFTypeRef?
        if let range=value(element,"AXSelectedTextMarkerRange"),let selection=text(range,limit:2000) {
            let rect=bounds(range)
            if point == nil || rect?.insetBy(dx:-2,dy:-2).contains(point!) == true {
                selected=selection;anchor=rect
                marker=MarkerBridge.start(range) ?? parameter(element,"AXStartTextMarkerForTextMarkerRange",range)
                if marker == nil,let rect {
                    var start=CGPoint(x:rect.minX+min(2,rect.width/2),y:rect.minY+min(6,rect.height/2))
                    if let position=AXValueCreate(.cgPoint,&start) {marker=parameter(element,"AXTextMarkerForPosition",position)}
                }
            }
        }
        if selected == nil, var point {
            guard let position=AXValueCreate(.cgPoint,&point),
                  let hit=parameter(element,"AXTextMarkerForPosition",position) else{return nil}
            // At word boundaries the left/right candidates differ. Accept only a candidate
            // whose actual glyph bounds contain the pointer, never a nearby guessed word.
            for name in ["AXLeftWordTextMarkerRangeForTextMarker","AXRightWordTextMarkerRangeForTextMarker"] {
                if let range=parameter(element,name,hit),let word=text(range,limit:2000),
                   let rect=bounds(range),rect.insetBy(dx:-1,dy:-1).contains(point) {
                    selected=word;anchor=rect;marker=hit;break
                }
            }
        }
        guard let selected else{return nil}
        var surrounding:String?
        if let marker {
            for name in ["AXParagraphTextMarkerRangeForTextMarker","AXSentenceTextMarkerRangeForTextMarker"] {
                if let range=parameter(element,name,marker),let context=text(range,limit:3000),context.contains(selected) {
                    surrounding=context;break
                }
            }
        }
        guard let context=ContextBuilder.make(selection:selected,surrounding:surrounding,sourceApp:appName) else{return nil}
        return CaptureResult(context:context,anchor:anchor,processID:processID)
    }
    private static func captureElement(_ focused:AXUIElement,processID:pid_t,appName:String,point:CGPoint?) throws -> CaptureResult {
        if (value(focused, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole { throw CaptureFailure.secure }
        var range = CFRange()
        var rangeValue = value(focused, kAXSelectedTextRangeAttribute)
        var hasRange = rangeValue.map { CFGetTypeID($0) == AXValueGetTypeID() && AXValueGetValue($0 as! AXValue, .cfRange, &range) } ?? false
        guard !hasRange || (range.location >= 0 && range.length <= 2000) else {throw CaptureFailure.unsupported}
        var selected = value(focused, kAXSelectedTextAttribute) as? String
        if let point {
            let selectedHere=rangeValue.flatMap{rect(focused,$0)}?.insetBy(dx:-2,dy:-2).contains(point) ?? false
            if !selectedHere || range.length==0 {
                var location=point
                guard let position=AXValueCreate(.cgPoint,&location),
                      let raw=parameter(focused,kAXRangeForPositionParameterizedAttribute,position),CFGetTypeID(raw)==AXValueGetTypeID(),
                      AXValueGetValue(raw as! AXValue,.cfRange,&range),range.location>=0 else{throw CaptureFailure.unsupported}
                let index=range.location
                let count=(value(focused,kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
                let start=max(0,index-80),end=min(count ?? index+80,index+80)
                var nearby=CFRange(location:start,length:max(0,end-start))
                guard let argument=AXValueCreate(.cfRange,&nearby),let text=parameter(focused,kAXStringForRangeParameterizedAttribute,argument) as? String else{throw CaptureFailure.unsupported}
                guard let word=TextTarget.range(in:text,atUTF16:index-start) else{throw CaptureFailure.noSelection}
                selected=(text as NSString).substring(with:word)
                range=CFRange(location:start+word.location,length:word.length)
                rangeValue=AXValueCreate(.cfRange,&range);hasRange=true
            }
        }
        if (selected?.isEmpty ?? true), hasRange, range.length > 0 {
            var output: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute as CFString, rangeValue!, &output) == .success { selected = output as? String }
        }
        guard let selected, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CaptureFailure.noSelection }
        var surrounding: String?
        // Ask for a bounded range first instead of fetching an entire document.
        if hasRange, range.location >= 0, range.length > 0 {
            let count = (value(focused, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
            let start = max(0, range.location - 600)
            let end = min(count ?? range.location + range.length, range.location + range.length + 1200)
            var contextRange = CFRange(location: start, length: max(0, end - start))
            if let argument = AXValueCreate(.cfRange, &contextRange) {
                var output: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute as CFString, argument, &output) == .success { surrounding = output as? String }
            }
        }
        // Only read full values of reasonably-sized text controls.
        if surrounding == nil, let count = value(focused, kAXNumberOfCharactersAttribute) as? NSNumber, count.intValue <= 12000 {
            surrounding = value(focused, kAXValueAttribute) as? String
        }
        guard let context = ContextBuilder.make(selection: selected, surrounding: surrounding, sourceApp: appName) else { throw CaptureFailure.noSelection }
        var anchor: CGRect?
        if hasRange, let rangeValue {
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(focused, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result) == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.width > 0 { anchor = rect }
            }
        }
        return CaptureResult(context: context, anchor: anchor, processID: processID)
    }
}

// The opaque marker C ABI is exported by ApplicationServices but not declared in
// all SDKs. Resolve it optionally; absence simply leaves context unavailable.
private enum MarkerBridge {
    static let framework=dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",RTLD_LAZY)
    static func start(_ range:CFTypeRef)->CFTypeRef? {
        guard let framework,let type=dlsym(framework,"AXTextMarkerRangeGetTypeID"),let copy=dlsym(framework,"AXTextMarkerRangeCopyStartMarker") else{return nil}
        let typeID=unsafeBitCast(type,to:(@convention(c)()->CFTypeID).self)
        guard CFGetTypeID(range)==typeID() else{return nil}
        let copyStart=unsafeBitCast(copy,to:(@convention(c)(CFTypeRef)->Unmanaged<CFTypeRef>?).self)
        return copyStart(range)?.takeRetainedValue()
    }
}

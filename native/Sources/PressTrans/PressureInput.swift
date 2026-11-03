import AppKit
import PressTransCore

// Undocumented macOS interface, loaded only for the opt-in experimental trigger.
// ABI references: mkalten/twongseng multitouch.h and OpenMultitouchSupport.
// No third-party binary is loaded; no touch history or coordinates are retained.
private typealias ContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32) -> Void
private final class PressureRelay: @unchecked Sendable {
    static let shared=PressureRelay()
    private let lock=NSLock()
    private var sink:(@Sendable (Float)->Void)?
    private var last:Double=0
    func set(_ sink:(@Sendable (Float)->Void)?) {lock.lock();self.sink=sink;last=0;lock.unlock()}
    func report(_ pressure:Float) {
        guard pressure.isFinite, pressure>=300, pressure<10000 else{return}
        lock.lock()
        let now=ProcessInfo.processInfo.systemUptime
        let callback = now-last>0.025 ? sink:nil
        if callback != nil {last=now}
        lock.unlock();callback?(pressure)
    }
}
private let contactCallback:ContactCallback = { _,buffer,count,_,_ in
    // Single-finger presses only. Expected 96-byte record, pressure float at byte 52.
    guard count==1, let buffer else{return}
    let state=buffer.load(fromByteOffset:20,as:Int32.self)
    guard (1...7).contains(state) else{return}
    PressureRelay.shared.report(buffer.load(fromByteOffset:52,as:Float.self))
}
@MainActor final class PressureInput {
    private typealias Create = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias Start = @convention(c) (UnsafeMutableRawPointer?,Int32)->Int32
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer?)->Int32
    private typealias Release = @convention(c) (UnsafeMutableRawPointer?)->Void
    private typealias Register = @convention(c) (UnsafeMutableRawPointer?,ContactCallback)->Void
    // Keep one handle for the process lifetime: callbacks may be unwinding during stop.
    private static let library=dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",RTLD_NOW|RTLD_LOCAL)
    private var device:UnsafeMutableRawPointer?
    private var stopFunction:Stop?, releaseFunction:Release?, unregister:Register?
    private var global:Any?, local:Any?
    private var detector=PressGesture()
    private var token=UUID()
    private var action:((CGPoint)->Void)?
    func start(action:@escaping(CGPoint)->Void) -> Bool {
        guard device==nil, AXIsProcessTrusted(), let library=Self.library else{return false}
        func symbol<T>(_ name:String,_ type:T.Type)->T? {dlsym(library,name).map{unsafeBitCast($0,to:type)}}
        guard let create=symbol("MTDeviceCreateDefault",Create.self), let start=symbol("MTDeviceStart",Start.self),
              let stop=symbol("MTDeviceStop",Stop.self), let release=symbol("MTDeviceRelease",Release.self),
              let register=symbol("MTRegisterContactFrameCallback",Register.self),let unregister=symbol("MTUnregisterContactFrameCallback",Register.self),
              let device=create() else{return false}
        self.device=device;stopFunction=stop;releaseFunction=release;self.unregister=unregister;self.action=action
        detector=PressGesture();token=UUID();let current=token
        let mask:NSEvent.EventTypeMask=[.leftMouseDown,.leftMouseUp,.leftMouseDragged]
        global=NSEvent.addGlobalMonitorForEvents(matching:mask){[weak self] event in self?.event(event)}
        local=NSEvent.addLocalMonitorForEvents(matching:mask){[weak self] event in self?.event(event);return event}
        guard global != nil, local != nil else {self.stop();return false}
        PressureRelay.shared.set{[weak self] pressure in
            Task { @MainActor in
                guard let self,self.token==current else{return}
                if let point=self.detector.pressure(pressure,time:ProcessInfo.processInfo.systemUptime) {self.action?(point)}
            }
        }
        register(device,contactCallback)
        guard start(device,0)==0 else {self.stop();return false}
        return true
    }
    private func event(_ event:NSEvent) {
        switch event.type {
        case .leftMouseDown:detector.down(at:NSEvent.mouseLocation,clicks:event.clickCount,time:ProcessInfo.processInfo.systemUptime)
        case .leftMouseUp:detector.up()
        case .leftMouseDragged:detector.move(to:NSEvent.mouseLocation)
        default:break
        }
    }
    func stop() {
        token=UUID();PressureRelay.shared.set(nil);detector.up();action=nil
        if let global {NSEvent.removeMonitor(global)};if let local {NSEvent.removeMonitor(local)}
        global=nil;local=nil
        if let device {unregister?(device,contactCallback);_ = stopFunction?(device);releaseFunction?(device)}
        device=nil
    }
}

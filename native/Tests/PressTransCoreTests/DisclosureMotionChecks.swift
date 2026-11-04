import PressTransCore

func checkDisclosureMotion() {
    var motion=DisclosureMotion(0);motion.retarget(1)
    var previous=0.0
    for _ in 0..<120 {
        motion.advance(1.0/120)
        precondition(motion.value>=previous && motion.value<=1,"Expansion must not bounce past its endpoint")
        previous=motion.value
    }
    precondition(motion.settled && motion.value==1 && motion.velocity==0)
    var slow=DisclosureMotion(154),fast=slow
    slow.retarget(500);fast.retarget(500)
    for _ in 0..<12 {slow.advance(1.0/60)}
    for _ in 0..<24 {fast.advance(1.0/120)}
    precondition(abs(slow.value-fast.value)<0.00001,"Motion must not change with display refresh rate")
    precondition(slow.value>480 && slow.value<500)
    let position=slow.value,velocity=slow.velocity
    slow.retarget(154)
    precondition(slow.value==position && slow.velocity==velocity,"Rapid reversal must preserve continuity")
    for _ in 0..<120 {slow.advance(1.0/120)}
    precondition(slow.settled && slow.value==154)
    fast.snap(154)
    precondition(fast.settled && fast.velocity==0,"Reduce Motion and dismissal must stop motion")
    fast.advance(.nan);fast.advance(-1)
    precondition(fast.value==154)
    print("Disclosure motion checks passed: monotonic reveal, 60/120 Hz equivalence, continuous reversal, settling, immediate stop")
}

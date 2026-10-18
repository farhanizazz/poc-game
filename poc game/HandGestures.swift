import Foundation
import CoreGraphics

enum HandShape: String, Sendable { case open, fist, unknown }

nonisolated struct HandShapeClassifier {
    // Finger tips extend away from the wrist for an open palm and fold inward for a fist.
    static func classify(wrist: CGPoint, tips: [CGPoint], knuckles: [CGPoint]) -> HandShape {
        guard tips.count == knuckles.count, tips.count >= 3 else { return .unknown }
        func distance(_ p: CGPoint) -> Double { hypot(p.x-wrist.x, p.y-wrist.y) }
        let ratios = zip(tips,knuckles).compactMap { tip, pip -> Double? in
            let base = distance(pip); return base > 0.015 ? distance(tip)/base : nil
        }
        if ratios.filter({ $0 > 1.35 }).count >= 3 { return .open }
        if ratios.filter({ $0 < 1.20 }).count >= 3 { return .fist }
        return .unknown
    }
}

struct HandGestureDetector {
    struct Event { let move: Move; let duration: Double }
    private var guardSince: Double?
    private var start: Double?
    private var origin = CGPoint.zero
    private var startReach = 0.0
    private var lastTime = 0.0
    private var lastPoint = CGPoint.zero
    private var strokeShape: HandShape = .unknown
    private var ready = false
    private var cooldown = 0.0
    mutating func reset() { self = HandGestureDetector() }
    mutating func sample(time: Double, wrist: CGPoint, elbow: CGPoint, shoulder: CGPoint,
                         shoulderSpan: Double, shape: HandShape, neutral: CGPoint) -> Event? {
        guard shoulderSpan >= 0.05, shape != .unknown else { reset(); return nil }
        if lastTime > 0 && (time <= lastTime || time-lastTime > 0.2) { reset() }
        let sampleDT = time-lastTime
        lastTime = time
        let p = CGPoint(x:(wrist.x-shoulder.x)/shoulderSpan, y:(wrist.y-shoulder.y)/shoulderSpan)
        let speed = sampleDT > 0 ? hypot(p.x-lastPoint.x,p.y-lastPoint.y)/sampleDT : 0
        lastPoint = p
        let inGuard = hypot(p.x-neutral.x,p.y-neutral.y) < 0.30
        if !ready {
            if time < cooldown { return nil }
            if inGuard {
                if guardSince == nil { guardSince = time }
                if time-(guardSince ?? time) >= 0.15 { ready = true; origin = p; startReach = hypot(p.x,p.y) }
            } else { guardSince = nil }
            return nil
        }
        let dx = p.x-origin.x, dy = p.y-origin.y
        if start == nil && hypot(dx,dy) >= 0.15 { start = time; strokeShape = shape }
        guard let start else { return nil }
        let duration = time-start
        if shape != strokeShape || duration > 1.2 {
            ready = false; self.start = nil; guardSince = nil; return nil
        }
        guard duration >= 0.08, speed >= 0.8 else { return nil }
        var move: Move?
        if shape == .open, abs(dy) >= 0.65, abs(dy) > abs(dx)*1.5 {
            move = dy < 0 ? .sliceUp : .sliceDown
        } else if shape == .fist {
            let a = CGPoint(x:shoulder.x-elbow.x,y:shoulder.y-elbow.y)
            let b = CGPoint(x:wrist.x-elbow.x,y:wrist.y-elbow.y)
            let lengths = hypot(a.x,a.y)*hypot(b.x,b.y)
            let extended = lengths > 0.0001 && (a.x*b.x+a.y*b.y)/lengths < -0.80
            let reachGain = hypot(p.x,p.y)-startReach
            if extended && reachGain > 0.30 {
                if dy < -0.55 && -dy > abs(dx)*1.3 { move = .punchUp }
                else if abs(dx) > 0.65 && abs(dx) > abs(dy)*1.3 { move = dx < 0 ? .punchLeft : .punchRight }
            }
        }
        guard let move else { return nil }
        ready = false; self.start = nil; guardSince = nil; cooldown = time+0.25
        return Event(move:move,duration:duration)
    }
}

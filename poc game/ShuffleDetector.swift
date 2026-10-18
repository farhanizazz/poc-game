import Foundation

// Motion-event heuristic, not inertial position integration. Fixed upright waist placement.
struct ShuffleDetector {
    struct Event { let direction: Int; let start: Double; let end: Double }
    private var start: Double?
    private var lastActive = 0.0
    private var direction = 0
    private var lastSample = 0.0
    private var cooldown = 0.0
    mutating func reset() { self = ShuffleDetector() }
    mutating func sample(time: Double, lateral: Double, upright: Bool) -> Event? {
        guard time.isFinite, lateral.isFinite else { reset(); return nil }
        if !upright || (lastSample > 0 && (time-lastSample > 0.15 || time <= lastSample)) { reset(); lastSample = time; return nil }
        lastSample = time
        guard time >= cooldown else { return nil }
        if start == nil, abs(lateral) > 0.10 {
            start = time; lastActive = time; direction = lateral > 0 ? 1 : -1
        }
        guard let began = start else { return nil }
        if abs(lateral) > 0.045 { lastActive = time }
        if time-began > 4 { reset(); cooldown = time+0.4; return nil }
        if time-lastActive >= 0.25 {
            let event = Event(direction: direction, start: began, end: lastActive)
            start = nil; cooldown = time+0.25
            return event.end-event.start >= 0.2 ? event : nil
        }
        return nil
    }
}

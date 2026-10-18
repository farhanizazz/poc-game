import Foundation

@main struct IMUChecks {
    @MainActor static func main() {
        var detector = ShuffleDetector()
        var events: [ShuffleDetector.Event] = []
        for i in 0..<100 {
            let t = Double(i)*0.02
            let a = i >= 10 && i < 20 ? 0.16 : i >= 20 && i < 35 ? -0.12 : 0
            if let event = detector.sample(time:t, lateral:a, upright:true) { events.append(event) }
        }
        assert(events.count == 1 && events[0].direction == 1)
        assert(abs(events[0].start-0.2) < 0.001 && abs(events[0].end-0.68) < 0.001)
        // Stationary samples and a brief tap cannot masquerade as a shuffle.
        detector.reset()
        for i in 0..<100 { assert(detector.sample(time:Double(i)*0.02, lateral:i == 10 ? 0.3 : 0, upright:true) == nil) }
        detector.reset()
        for i in 0..<50 { assert(detector.sample(time:Double(i)*0.02, lateral:0.2, upright:false) == nil) }
        let g = GameModel(); g.startIMU(); g.tracking = true; g.centerIMU()
        var now = ProcessInfo.processInfo.systemUptime+0.1
        for (direction, duration) in [(1,1.0),(-1,2.0),(1,1.0)] {
            g.receiveIMU(direction:direction,start:now,end:now+duration); now += duration+0.5
        }
        assert(g.phase == .running && g.imuLeftSign == 1 && g.secondsPerLane == 1)
        for _ in 0..<40 { g.newCue(); assert(g.cue.allSatisfy(\.directional)) }
        g.positionX = g.center.x; g.cue = [.left]; g.cueIndex = 0; g.prepareStep()
        g.imuAcceptAfter = 0
        let beat = g.stepStartedUptime+g.stepBeat
        g.receiveIMU(direction:-1,start:beat-1,end:beat)
        assert(g.history.count == 1 && !g.history[0].success && g.paused, "Wrong direction pauses for recentering")
        g.history = []; g.paused = false; g.cue = [.left]; g.cueIndex = 0; g.prepareStep()
        g.stepStartedUptime = beat-g.stepBeat
        g.receiveIMU(direction:1,start:g.stepStartedUptime-1,end:beat)
        assert(g.history.isEmpty, "A pre-cue movement cannot score")
        g.receiveIMU(direction:1,start:beat-1,end:beat)
        assert(g.history.count == 1 && g.metrics.0 == 1 && abs(g.metrics.1-1) < 0.0001)
        g.receiveIMU(direction:1,start:beat-1,end:beat)
        assert(g.history.count == 1, "Duplicate after completion cannot score")
        g.cue = [.right]; g.cueIndex = 0; g.prepareStep(); g.paused = true
        g.receiveIMU(direction:-1,start:g.stepStartedUptime+0.1,end:g.stepStartedUptime+1)
        assert(g.history.count == 1)
        g.centerIMU(); assert(!g.paused && g.positionX == g.center.x && g.cue.isEmpty)
        g.start(demo: true); assert(!g.imuMode)
        print("PASS: IMU burst duration/direction, tap and orientation rejection, calibration, shuffle-only cues, timestamp scoring, wrong/stale/duplicate events, pause/recenter, mode switch")
    }
}

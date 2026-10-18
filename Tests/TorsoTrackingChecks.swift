import Foundation
import Vision

@main struct TorsoTrackingChecks {
    @MainActor static func main() {
        func frame(x: Double = 0.5, y: Double = 0.55) -> BodyFrame {
            var points: [String: CGPoint] = [:]
            func put(_ joint: VNHumanBodyPoseObservation.JointName, _ x: Double, _ y: Double) {
                points[joint.rawValue.rawValue] = CGPoint(x:x,y:y)
            }
            put(.root, x, y)
            put(.leftHip, x-0.07, y); put(.rightHip, x+0.07, y)
            put(.leftShoulder, x-0.1, y-0.3); put(.rightShoulder, x+0.1, y-0.3)
            return BodyFrame(points:points, valid:true, timestamp:Date())
        }
        let g = GameModel(); g.start(demo:false)
        var clock = Date()
        for x in [0.5, 0.27, 0.73, 0.5] {
            for _ in 0..<12 {
                clock = clock.addingTimeInterval(0.1)
                var f = frame(x:x); f.timestamp = clock; g.consume(f)
            }
        }
        assert(g.phase == .running && g.tracking, "No knee or ankle joints are needed for calibration")
        assert(abs(g.bodyHeight-0.3) < 0.001, "Calibration scales from shoulders to hips")
        g.cue = [.left]; g.prepareStep()
        g.cueAge = 0.3; g.consume(frame(x:0.4))
        g.cueAge = g.stepBeat; g.consume(frame(x:g.leftX))
        assert(g.history.count == 1 && g.history[0].coordination == 1)
        // Arm cues require a visible wrist, but no knees, ankles, or finger landmarks.
        g.cue = [.armTouch]; g.cueIndex = 0; g.prepareStep()
        let beforeTouch = g.history.count
        g.consume(frame())
        assert(!g.tracking && g.stepTrackingInterrupted && g.history.count == beforeTouch)
        var visible = frame()
        let wristKey = VNHumanBodyPoseObservation.JointName.leftWrist.rawValue.rawValue
        visible.points[wristKey] = CGPoint(x:0.4,y:0.3)
        g.consume(visible)
        assert(g.tracking && !g.stepTrackingInterrupted && g.cueAge == 0)
        g.armTarget = CGPoint(x:0.7,y:0.3); g.armTargetRadius = 0.06
        g.cueAge = g.stepBeat-0.1; g.consume(visible)
        visible.points[wristKey] = CGPoint(x:0.7,y:0.3)
        g.cueAge = g.stepBeat; g.consume(visible)
        assert(g.history.count == beforeTouch+1 && g.touchGrade == .perfect)
        for _ in 0..<10 { g.consume(visible) }
        assert(g.history.count == beforeTouch+1, "Holding a hand cannot repeat a touch")
        // Vision processing delay is excluded from arrival timing, including late delivery.
        let timed = GameModel(); timed.start(demo:false); timed.phase = .running; timed.tracking = true
        timed.cue = [.left]; timed.prepareStep()
        let now = ProcessInfo.processInfo.systemUptime
        timed.stepStartedUptime = now-(timed.stepBeat+timed.stepHalfWindow+0.05)
        timed.cueAge = timed.stepBeat+timed.stepHalfWindow+0.05
        var departure = frame(x:0.44); departure.capturedUptime = now-0.25
        timed.consume(departure)
        var onTime = frame(x:0.39); onTime.capturedUptime = now-0.10
        timed.consume(onTime)
        assert(timed.history.count == 1 && timed.history[0].success, "Processing latency must not turn an on-time arrival into a miss")
        let timeout = GameModel(); timeout.start(demo:false); timeout.phase = .running; timeout.tracking = true
        timeout.cue = [.left]; timeout.prepareStep()
        timeout.stepStartedUptime = ProcessInfo.processInfo.systemUptime-timeout.stepDuration-0.1
        timeout.tick()
        assert(timeout.history.isEmpty, "An in-flight frame gets a bounded delivery allowance")
        timeout.stepStartedUptime -= 0.3; timeout.tick()
        assert(timeout.history.count == 1 && !timeout.history[0].success, "Missing arrivals still time out")
        let late = GameModel(); late.start(demo:false); late.phase = .running; late.tracking = true
        late.cue = [.right]; late.prepareStep()
        late.stepStartedUptime = now-late.stepDuration-0.2
        var latePose = frame(x:0.8); latePose.capturedUptime = now-0.05
        late.consume(latePose)
        assert(late.history.count == 1 && !late.history[0].success, "Delivery grace must not widen the scoring window")
        timed.cue = [.right]; timed.cueIndex = 0; timed.prepareStep()
        var stale = frame(x:0.8); stale.capturedUptime = now-1
        timed.consume(stale)
        assert(!timed.tracking && timed.stepTrackingInterrupted && timed.history.count == 1)
        // Every Vision cue, including arm touches, resumes with a fresh deadline.
        timed.cue = [.armTouch]; timed.cueIndex = 0; timed.prepareStep()
        timed.paused = true; timed.tick(); timed.paused = false
        timed.consume(visible)
        assert(!timed.stepTrackingInterrupted && timed.cueAge == 0 && timed.history.count == 1)
        // Missing mandatory torso joints pause scoring, even if upstream says valid.
        for joint in [VNHumanBodyPoseObservation.JointName.root,.leftHip,.rightHip,.leftShoulder,.rightShoulder] {
            var f = frame(); f.points.removeValue(forKey:joint.rawValue.rawValue)
            let count = g.history.count; g.consume(f)
            assert(!g.tracking && g.history.count == count)
        }
        var invalid = frame(); invalid.valid = false; g.consume(invalid)
        assert(!g.tracking, "Low confidence does not score")
        // Leg positions do not influence torso scale or validity when present.
        var full = frame()
        full.points[VNHumanBodyPoseObservation.JointName.leftAnkle.rawValue.rawValue] = CGPoint(x:0.4,y:0.99)
        assert(abs(full.torso!.height-0.3) < 0.001)
        g.startIMU(); g.tracking = false; g.consume(frame())
        assert(!g.tracking, "Vision snapshots cannot affect IMU mode")
        let skills = GameModel(); skills.startSkills(input:.vision,combined:true)
        skills.phase = .running; skills.cue = [.left]; skills.obstaclePassTimes = [3]; skills.prepareStep()
        skills.consume(frame())
        assert(!skills.tracking && skills.stepTrackingInterrupted,"Combined tasks require both wrists")
        var both = frame()
        both.points[wristKey] = CGPoint(x:0.4,y:0.3)
        let rightWristKey = VNHumanBodyPoseObservation.JointName.rightWrist.rawValue.rawValue
        both.points[rightWristKey] = CGPoint(x:0.6,y:0.3)
        skills.consume(both)
        assert(skills.tracking && !skills.stepTrackingInterrupted && skills.history.isEmpty)
        assert(skills.skills.leftShoulder.x < skills.skills.rightShoulder.x,"Preserve anatomical shoulder identity after mirroring")
        skills.armTarget = CGPoint(x:0.4,y:0.3); skills.skills.targetSpawnAge = 0.5
        both.points.removeValue(forKey:rightWristKey); skills.consume(both)
        assert(!skills.tracking && skills.history.isEmpty)
        both.points[rightWristKey] = CGPoint(x:0.6,y:0.3); skills.consume(both)
        assert(skills.armTarget == nil && skills.skills.targetSpawnAge == nil && skills.history.isEmpty)
        print("PASS: cropped calibration, torso scaling, shuffle arrival, arm contacts and wrist-loss recovery without knees or feet, mandatory joints/confidence, IMU isolation")
    }
}

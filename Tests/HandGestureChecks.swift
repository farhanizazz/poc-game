import Foundation
import Vision

@main struct HandGestureChecks {
    @MainActor static func main() {
        let wrist = CGPoint.zero
        assert(HandShapeClassifier.classify(wrist:wrist,tips:Array(repeating:CGPoint(x:0,y:0.2),count:4),knuckles:Array(repeating:CGPoint(x:0,y:0.1),count:4)) == .open)
        assert(HandShapeClassifier.classify(wrist:wrist,tips:Array(repeating:CGPoint(x:0,y:0.08),count:4),knuckles:Array(repeating:CGPoint(x:0,y:0.1),count:4)) == .fist)
        assert(HandShapeClassifier.classify(wrist:wrist,tips:[],knuckles:[]) == .unknown)
        func stroke(end: CGPoint, shape: HandShape, bent: Bool = false) -> [Move] {
            var detector = HandGestureDetector(); var moves: [Move] = []
            let neutral = CGPoint(x:0,y:0.5)
            for i in 0..<11 {
                assert(detector.sample(time:100+Double(i)*0.02,wrist:neutral,elbow:CGPoint(x:0.3,y:0.4),shoulder:.zero,shoulderSpan:1,shape:shape,neutral:neutral) == nil)
            }
            for i in 1...20 {
                let t = Double(i)/20
                let p = CGPoint(x:end.x*t,y:0.5+(end.y-0.5)*t)
                let elbow = bent ? CGPoint(x:1,y:1) : CGPoint(x:p.x/2,y:p.y/2)
                if let event = detector.sample(time:100.2+Double(i)*0.02,wrist:p,elbow:elbow,shoulder:.zero,shoulderSpan:1,shape:shape,neutral:neutral) { moves.append(event.move) }
            }
            // Holding the final pose cannot generate a second strike.
            for i in 1...20 {
                if let event = detector.sample(time:100.6+Double(i)*0.02,wrist:end,elbow:CGPoint(x:end.x/2,y:end.y/2),shoulder:.zero,shoulderSpan:1,shape:shape,neutral:neutral) { moves.append(event.move) }
            }
            return moves
        }
        assert(stroke(end:CGPoint(x:0,y:-0.3),shape:.open) == [.sliceUp])
        assert(stroke(end:CGPoint(x:0,y:1.3),shape:.open) == [.sliceDown])
        assert(stroke(end:CGPoint(x:0,y:-1),shape:.fist) == [.punchUp])
        assert(stroke(end:CGPoint(x:-1.2,y:0.5),shape:.fist) == [.punchLeft])
        assert(stroke(end:CGPoint(x:1.2,y:0.5),shape:.fist) == [.punchRight])
        assert(stroke(end:CGPoint(x:1.2,y:0.5),shape:.open).isEmpty, "Open lateral sweep is not a punch")
        assert(stroke(end:CGPoint(x:0,y:-1),shape:.fist,bent:true).isEmpty, "Punch must extend the arm")
        let g = GameModel(); g.startHands(demo:true)
        for _ in 0..<3 { for _ in 0..<10 { g.calibrateHands(guardOK:true,left:CGPoint(x:0,y:0.5),right:CGPoint(x:0,y:0.5),dt:0.1) } }
        assert(g.phase == .running && g.handMode)
        for _ in 0..<30 { g.newCue(); assert(g.cue.allSatisfy(\.handAction)) }
        g.history = []; g.evaluation = []; g.zoneTime = 61
        for _ in 0..<2 {
            for move in Move.handMoves + Move.handMoves {
                g.cue = [move]; g.cueIndex = 0; g.prepareStep(); g.cueAge = g.stepBeat
                g.receiveHand(move,duration:0.4)
            }
        }
        assert(g.windows == 2 && g.phase == .recovery && g.metrics.0 == 1 && g.metrics.1 == 1)
        g.rest = 0; g.enterBoss()
        for move in Move.handMoves {
            g.cue = [move]; g.cueIndex = 0; g.prepareStep(); g.cueAge = g.stepBeat
            g.receiveHand(move,duration:0.4)
        }
        g.bossTime = 30; g.lastTick = Date().addingTimeInterval(-0.05); g.tick()
        assert(g.won && g.phase == .result)
        g.continueRun(); g.cue = [.sliceUp]; g.cueIndex = 0; g.prepareStep(); g.cueAge = g.stepBeat
        g.receiveHand(.punchUp,duration:0.4)
        assert(g.history.last?.success == false && g.metrics.0 == 0 && g.metrics.1 == 0)
        g.cue = [.sliceDown]; g.cueIndex = 0; g.prepareStep(); g.cueAge = 0.5
        g.receiveHand(.sliceDown,duration:0.4)
        assert(g.history.last?.coordination == 0, "Early strikes miss the beat")
        g.startHands(demo:false)
        let tracker = BodyTracker()
        func pose(shape: HandShape, time: Date) -> BodyFrame {
            var points: [String:CGPoint] = [:]
            func put(_ j: VNHumanBodyPoseObservation.JointName, _ x: Double, _ y: Double) { points[j.rawValue.rawValue] = CGPoint(x:x,y:y) }
            put(.root,0.5,0.55); put(.leftHip,0.43,0.55); put(.rightHip,0.57,0.55)
            put(.leftShoulder,0.4,0.25); put(.rightShoulder,0.6,0.25)
            put(.leftElbow,0.35,0.38); put(.rightElbow,0.65,0.38)
            put(.leftWrist,0.4,0.35); put(.rightWrist,0.6,0.35)
            return BodyFrame(points:points,valid:true,timestamp:time,handShapes:[VNHumanBodyPoseObservation.JointName.leftWrist.rawValue.rawValue:shape,VNHumanBodyPoseObservation.JointName.rightWrist.rawValue.rawValue:shape])
        }
        var time = Date()
        for shape in [HandShape.open,.fist,.open] {
            for _ in 0..<12 { time = time.addingTimeInterval(0.1); tracker.route(pose(shape:shape,time:time),to:g) }
        }
        assert(g.phase == .running && g.tracking, "Camera routing can complete three hand calibration steps")
        tracker.route(pose(shape:.unknown,time:time.addingTimeInterval(0.1)),to:g)
        assert(!g.tracking, "Uncertain hand shape freezes scoring")
        g.start(demo:true); assert(!g.handMode)
        print("PASS: palm/fist classification, all five actions, direction/extension checks, no repeated holds, hand calibration, beat scoring, balanced boss gate/pass, tracking loss, mode isolation")
    }
}

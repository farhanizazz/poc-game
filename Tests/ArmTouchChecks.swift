import Foundation

@main struct ArmTouchChecks {
    @MainActor static func main() {
        func game(demo: Bool = true) -> GameModel {
            let g = GameModel(); g.start(demo:demo); g.phase = .running; g.tracking = true
            g.cue = [.armTouch]; g.prepareStep()
            g.armTarget = CGPoint(x:0.5,y:0.3); g.armTargetRadius = 0.05
            return g
        }
        func near(_ a: Double,_ b: Double) { assert(abs(a-b) < 0.00001,"\(a) != \(b)") }
        for sign in [-1.0,1.0] {
            for (error,expected) in [(0.0,TouchGrade.perfect),(0.1,.perfect),(0.15,.great),(0.2,.great),(0.3,.good),(0.5,.good),(0.51,.bad)] {
                let g = game(); g.receiveArmTouch(age:g.stepBeat+sign*error)
                assert(g.touchGrade == expected && g.history.count == 1)
                near(g.metrics.0,0); near(g.metrics.1,expected.coordination)
                assert(g.history[0].success == (expected != .bad))
                assert(g.combo == (expected == .bad ? 0 : 1))
            }
        }
        let hold = game()
        hold.observeArm(wrists:[CGPoint(x:0.5,y:0.3),nil],age:hold.stepBeat)
        hold.observeArm(wrists:[CGPoint(x:0.5,y:0.3),nil],age:hold.stepBeat+0.05)
        assert(hold.history.isEmpty,"Standing on a newly spawned target earns nothing")
        hold.observeArm(wrists:[CGPoint(x:0.4,y:0.3),nil],age:hold.stepBeat+0.1)
        hold.observeArm(wrists:[CGPoint(x:0.5,y:0.3),nil],age:hold.stepBeat+0.2)
        assert(hold.history.count == 1 && hold.touchGrade == .great)
        hold.observeArm(wrists:[CGPoint(x:0.5,y:0.3),nil],age:hold.stepBeat+0.25)
        assert(hold.history.count == 1)
        let swipe = game()
        swipe.observeArm(wrists:[nil,CGPoint(x:0.35,y:0.3)],age:swipe.stepBeat-0.1)
        swipe.observeArm(wrists:[nil,CGPoint(x:0.65,y:0.3)],age:swipe.stepBeat+0.02)
        assert(swipe.history.count == 1 && swipe.touchGrade == .perfect,"A fast crossing cannot be missed between frames")
        near(swipe.history[0].timingError!,-0.06)
        let miss = game()
        miss.observeArm(wrists:[CGPoint(x:0.35,y:0.4),nil],age:miss.stepBeat-0.1)
        miss.observeArm(wrists:[CGPoint(x:0.65,y:0.4),nil],age:miss.stepBeat)
        assert(miss.history.isEmpty,"Near misses are not contact")
        miss.remaining = 0; miss.lastTick = Date().addingTimeInterval(-0.04); miss.tick()
        assert(miss.touchGrade == .bad && miss.history.count == 1 && miss.metrics.1 == 0)
        let lost = game()
        lost.observeArm(wrists:[CGPoint(x:0.35,y:0.3),nil],age:lost.stepBeat-0.1)
        lost.observeArm(wrists:[nil,nil],age:lost.stepBeat-0.05)
        lost.observeArm(wrists:[CGPoint(x:0.5,y:0.3),nil],age:lost.stepBeat)
        assert(lost.history.isEmpty,"Do not bridge missing wrist observations")
        let gap = game()
        gap.observeArm(wrists:[CGPoint(x:0.35,y:0.3),nil],age:gap.stepBeat-0.4)
        gap.observeArm(wrists:[CGPoint(x:0.65,y:0.3),nil],age:gap.stepBeat)
        assert(gap.history.isEmpty,"Do not infer a crossing across a long frame gap")
        let frozen = game(); frozen.paused = true; frozen.receiveArmTouch(age:frozen.stepBeat)
        assert(frozen.history.isEmpty)
        frozen.paused = false; frozen.interruptShuffle(); frozen.receiveArmTouch(age:frozen.stepBeat)
        assert(frozen.history.isEmpty)
        let keyboard = game(); keyboard.cueAge = keyboard.stepBeat; keyboard.input(.armTouch)
        assert(keyboard.touchGrade == .perfect)
        let camera = game(demo:false); camera.cueAge = camera.stepBeat; camera.input(.armTouch)
        assert(camera.history.isEmpty,"Keyboard input cannot bypass Vision contact")
        let mixed = game()
        mixed.history = [Attempt(move:.left,success:true,reaction:1,agility:0.8,coordination:1)]
        mixed.receiveArmTouch(age:mixed.stepBeat+0.3)
        near(mixed.metrics.0,0.8); near(mixed.metrics.1,0.8)
        mixed.phase = .boss; mixed.cue = [.armTouch]; mixed.cueIndex = 0; mixed.prepareStep()
        mixed.receiveArmTouch(age:mixed.stepBeat)
        assert(mixed.bossHistory.count == 1 && mixed.bossHistory[0].coordination == 1)
        for _ in 0..<100 {
            let normal = game(); normal.newCue()
            assert(normal.cue.allSatisfy { $0.directional || $0 == .armTouch })
            let imu = game(); imu.startIMU(); imu.phase = .running; imu.tracking = true; imu.newCue()
            assert(imu.cue.allSatisfy(\.directional),"Waist IMU remains shuffle-only")
        }
        print("PASS: four timing grades, coordination aggregation, agility isolation, geometric and swept contact, either wrist, parked hands, duplicates, misses, tracking gaps, pauses, demo, boss scoring, mode separation")
    }
}

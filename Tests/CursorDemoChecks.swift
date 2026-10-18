import Foundation

@main struct CursorDemoChecks {
    @MainActor static func main() {
        func near(_ a: Double,_ b: Double) { assert(abs(a-b) < 0.00001,"\(a) != \(b)") }
        func game() -> GameModel {
            let g = GameModel(); g.start(demo:true)
            for x in [0.5,0.27,0.73,0.5] {
                for _ in 0..<10 { g.calibrate(position:CGPoint(x:x,y:0.5),height:0.5,dt:0.1) }
            }
            assert(g.phase == .running)
            return g
        }
        let calibration = GameModel(); calibration.start(demo:true)
        for (x,target) in [(0.05,0.27),(0.5,0.5),(0.95,0.73)] {
            calibration.updateDemoCursor(position:CGPoint(x:x,y:0.4),insideWindow:true)
            near(calibration.demoTargetX,target)
        }
        calibration.updateDemoCursor(position:nil,insideWindow:false)
        calibration.calibrate(position:CGPoint(x:0.5,y:0.5),height:0.5,dt:0.1)
        near(calibration.hold,0)
        let regions = game(); regions.cue = []
        let g = game(); g.cue = [.left]; g.prepareStep()
        for (x,target) in [(0.0,g.leftX),(0.32,g.leftX),(1.0/3,g.center.x),(0.5,g.center.x),(2.0/3,g.center.x),(0.68,g.rightX),(1.2,g.rightX)] {
            regions.updateDemoCursor(position:CGPoint(x:x,y:0.5),insideWindow:true)
            near(regions.demoTargetX,target); near(regions.positionX,target)
            assert(regions.lane == regions.laneAt(target))
        }
        // Lane entry updates both the avatar and timing score before any tick.
        let instant = game(); instant.cue = [.left]; instant.prepareStep()
        instant.cueAge = instant.stepBeat; instant.lastTick = Date()
        instant.updateDemoCursor(position:CGPoint(x:0.1,y:0.5),insideWindow:true)
        near(instant.positionX,instant.leftX)
        assert(instant.lane == -1 && instant.history.count == 1 && instant.history[0].success)
        for _ in 0..<10 { instant.updateDemoCursor(position:CGPoint(x:0.1,y:0.5),insideWindow:true) }
        assert(instant.history.count == 1,"Hovering cannot repeatedly score the same arrival")
        g.combo = 7; g.cueAge = 0.7; g.remaining = 1.3
        let elapsed = g.elapsed, age = g.cueAge, remaining = g.remaining, position = g.positionX
        let departure = g.shuffleDeparture
        g.updateDemoCursor(position:nil,insideWindow:false)
        for _ in 0..<20 { g.lastTick = Date().addingTimeInterval(-0.1); g.tick() }
        assert(g.demoPointerOutside && !g.reliable && !g.paused)
        near(g.elapsed,elapsed); near(g.cueAge,age); near(g.remaining,remaining); near(g.positionX,position)
        assert(g.combo == 7 && g.history.isEmpty && g.shuffleDeparture == departure && !g.stepTrackingInterrupted)
        g.updateDemoCursor(position:CGPoint(x:0.5,y:0.5),insideWindow:true)
        assert(!g.demoPointerOutside && g.reliable)
        near(g.cueAge,age)
        g.lastTick = Date().addingTimeInterval(-0.04); g.tick()
        assert(g.cueAge > age && g.cueAge < age+0.1,"Continue the same cue without reissuing it")
        g.paused = true
        g.updateDemoCursor(position:nil,insideWindow:false)
        g.updateDemoCursor(position:CGPoint(x:0.9,y:0.5),insideWindow:true)
        assert(g.paused,"Cursor return must not undo a manual pause")
        let boss = game(); boss.phase = .boss; boss.bossTime = 12
        boss.updateDemoCursor(position:nil,insideWindow:false); boss.tick(); near(boss.bossTime,12)
        let arm = game(); arm.cue = [.armTouch]; arm.prepareStep()
        arm.armTarget = CGPoint(x:0.5,y:0.3); arm.armTargetRadius = 0.05
        arm.cueAge = arm.stepBeat-0.08; arm.lastTick = Date()
        arm.updateDemoCursor(position:CGPoint(x:0.4,y:0.3),insideWindow:true)
        arm.cueAge = arm.stepBeat; arm.lastTick = Date()
        arm.updateDemoCursor(position:CGPoint(x:0.5,y:0.3),insideWindow:true)
        assert(arm.touchGrade == .perfect && arm.history.count == 1)
        let parked = game(); parked.cue = [.armTouch]; parked.prepareStep()
        parked.armTarget = CGPoint(x:0.5,y:0.3); parked.cueAge = parked.stepBeat
        parked.updateDemoCursor(position:CGPoint(x:0.5,y:0.3),insideWindow:true)
        assert(parked.history.isEmpty,"A parked pointer must leave and re-enter a new target")
        let vision = GameModel(); vision.start(demo:false)
        vision.updateDemoCursor(position:nil,insideWindow:false)
        assert(!vision.demoPointerOutside,"Cursor exits must not affect Vision")
        let hands = game(); hands.handMode = true; hands.demoTargetX = 0.5
        hands.updateDemoCursor(position:CGPoint(x:0.9,y:0.5),insideWindow:true)
        near(hands.demoTargetX,0.5)
        print("PASS: cursor lane regions, calibration, instant movement and arrival scoring, exact window-exit freeze/resume, manual pause, boss freeze, hover contacts, parked targets, mode isolation")
    }
}

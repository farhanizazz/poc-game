import Foundation

@main struct CursorSpeedChecks {
    @MainActor static func main() {
        func near(_ a: Double,_ b: Double) { assert(abs(a-b) < 0.00001,"\(a) != \(b)") }
        func game() -> GameModel {
            let g = GameModel(); g.start(demo:true); g.phase = .running
            g.demoCursor = CGPoint(x:0.5,y:0.5); g.positionX = 0.5
            g.secondsPerLane = 0.5; g.cue = [.left]; g.prepareStep()
            return g
        }
        func sample(_ g: GameModel,_ x: Double,_ age: Double) {
            g.updateDemoCursor(position:CGPoint(x:x,y:0.5),insideWindow:true,observedAge:age)
        }
        let fast = game(), slow = game()
        // Both arrive exactly on beat. Only cursor movement duration changes.
        for (g,duration) in [(fast,0.2),(slow,0.8)] {
            let end = g.stepBeat
            sample(g,0.5,end-duration)
            sample(g,0.4,end-duration/2)
            assert(g.positionX == g.center.x && g.history.isEmpty,"Measure movement before lane entry, without moving the avatar early")
            sample(g,0.3,end)
            assert(g.lane == -1 && g.positionX == g.leftX && g.history.count == 1 && g.history[0].success)
            near(g.history[0].coordination,1)
            near(g.history[0].travelSeconds!,duration*0.9)
            near(g.demoCursorSpeed!,0.6/(duration*0.9))
        }
        near(fast.metrics.0,1); near(slow.metrics.0,1)
        assert(fast.demoCursorSpeed! > slow.demoCursorSpeed!,"Cursor speed is diagnostic; equal arrivals earn equal agility")
        let waiting = game(), immediate = game()
        for (g,wait) in [(waiting,1.3),(immediate,0.0)] {
            sample(g,0.5,wait); sample(g,0.4,wait+0.1); sample(g,0.3,wait+0.2)
        }
        near(waiting.history[0].travelSeconds!,immediate.history[0].travelSeconds!)
        near(waiting.metrics.0,1); near(immediate.metrics.0,0)
        assert(waiting.history[0].coordination != immediate.history[0].coordination,"Waiting for MOVE NOW changes response scoring, not measured travel speed")
        let jitter = game()
        sample(jitter,0.51,0.1); sample(jitter,0.49,0.4); sample(jitter,0.5,0.8)
        assert(jitter.cursorDepartureAge == nil && jitter.history.isEmpty)
        let crossing = game(); crossing.positionX = crossing.leftX; crossing.demoCursor = CGPoint(x:0.2,y:0.5)
        crossing.cue = [.right]; crossing.prepareStep()
        let beat = crossing.stepBeat
        sample(crossing,0.2,beat-0.6); sample(crossing,0.5,beat-0.3)
        assert(crossing.lane == 0 && crossing.history.isEmpty,"Crossing center is not the requested right arrival")
        sample(crossing,0.7,beat)
        assert(crossing.history.count == 1 && crossing.lane == 1)
        near(crossing.history[0].travelSeconds!,0.58)
        let parked = game(); sample(parked,0.5,0.1)
        parked.cueAge = 0.5; sample(parked,0.4,0.5)
        parked.updateDemoCursor(position:nil,insideWindow:false)
        parked.tick()
        sample(parked,0.3,0.5)
        assert(parked.history.count == 1 && parked.history[0].travelSeconds == nil && parked.metrics.0 == 0,"Never infer cursor speed across an outside-window gap")
        let unknown = game(); unknown.demoCursor = nil; unknown.prepareStep()
        sample(unknown,0.3,unknown.stepBeat)
        assert(unknown.history.count == 1 && unknown.history[0].success && unknown.history[0].travelSeconds == nil)
        let calibration = GameModel(); calibration.start(demo:true)
        func calibrateFrame(_ x: Double) {
            calibration.updateDemoCursor(position:CGPoint(x:x,y:0.5),insideWindow:true)
            calibration.calibrate(position:CGPoint(x:calibration.demoTargetX,y:0.5),height:0.5,dt:0.1)
        }
        for _ in 0..<10 { calibrateFrame(0.5) }
        for route in [[0.48,0.43,0.38,0.33,0.3],[0.35,0.45,0.55,0.65,0.7],[0.65,0.6,0.55]] {
            for x in route { calibrateFrame(x) }
            for _ in 0..<10 { calibrateFrame(route.last!) }
        }
        assert(calibration.phase == .running && calibration.calibrationSamples.count == 3,"Cursor calibration must measure all three trips")
        assert(calibration.secondsPerLane > 0.05 && calibration.secondsPerLane < 1)
        let vision = GameModel(); vision.start(demo:false); vision.phase = .running; vision.tracking = true
        vision.cue = [.left]; vision.prepareStep()
        vision.cueAge = 0.3; vision.observeShuffle(x:0.44)
        vision.cueAge = vision.stepBeat; vision.observeShuffle(x:vision.leftX)
        assert(vision.history.count == 1 && vision.history[0].travelSeconds != nil && vision.demoCursorSpeed == nil)
        print("PASS: measured cursor travel, calibration baseline, distance-normalized speed, diagnostic speed independent of response agility, waiting/jitter rejection, crossing center, immediate movement, unknown/interrupted trips, Vision isolation")
    }
}

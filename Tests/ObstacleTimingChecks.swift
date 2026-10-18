import Foundation

@main struct ObstacleTimingChecks {
    @MainActor static func main() {
        func near(_ a: Double, _ b: Double) { assert(abs(a-b) < 0.00001,"\(a) != \(b)") }
        func game(_ mode: String = "vision", move: Move = .left, origin: Double = 0.5) -> GameModel {
            let g = GameModel(); g.start(demo:mode == "cursor")
            g.imuMode = mode == "imu"; g.imuLeftSign = 1; g.imuAcceptAfter = 0
            g.tracking = true; g.phase = .running; g.secondsPerLane = 0.5
            g.positionX = origin; g.demoCursor = CGPoint(x:origin,y:0.5)
            g.cue = [move]; g.prepareStep()
            return g
        }
        func arrive(_ g: GameModel, at age: Double) {
            let target = g.targetX(g.currentMove!)
            if g.imuMode {
                let base = ProcessInfo.processInfo.systemUptime+10
                g.stepStartedUptime = base
                g.receiveIMU(direction:target < g.positionX ? 1 : -1,start:base+age-0.2,end:base+age)
            } else if g.demo {
                g.updateDemoCursor(position:CGPoint(x:0.4,y:0.5),insideWindow:true,observedAge:age-0.1)
                g.updateDemoCursor(position:CGPoint(x:0.2,y:0.5),insideWindow:true,observedAge:age)
            } else {
                g.observeShuffle(x:0.44,observedAge:age-0.1)
                g.observeShuffle(x:target,observedAge:age)
            }
        }
        let timing = game()
        near(timing.stepHalfWindow,0.75)
        near(timing.stepWindowOpen,timing.stepBeat-0.75)
        near(timing.stepWindowClose,timing.stepDuration)
        assert(timing.stepWindowOpen > 0 && timing.timingLabel.contains("WAIT"))
        timing.cueAge = timing.stepWindowOpen
        assert(timing.timingOpen && timing.timingLabel.contains("MOVE NOW"))
        // Changing difficulty during a step cannot shift its deadlines.
        let opening = timing.stepWindowOpen, close = timing.stepWindowClose
        timing.zoneTime = 180; near(timing.stepWindowOpen,opening); near(timing.stepWindowClose,close)
        let crossing = game(move:.right,origin:0.3)
        near(crossing.stepHalfWindow,1.25)
        assert(crossing.stepHalfWindow > timing.stepHalfWindow,"Longer routes get calibrated travel allowance")
        // All input modes share exact boundary, early, ideal, late, and missed-arrival rules.
        for mode in ["vision","cursor","imu"] {
            for offset in [-0.0001,0,0.65,0.75,0.85,1.2,1.5,1.5001] {
                let g = game(mode)
                let window = g.stepHalfWindow
                arrive(g,at:g.stepWindowOpen+offset)
                assert(g.history.count == 1)
                let attempt = g.history[0], valid = offset >= 0 && offset <= 2*window
                assert(attempt.success == valid,"\(mode) at offset \(offset)")
                near(attempt.responseSeconds!,offset)
                near(attempt.agility,valid ? min(1,(window+0.1)/max(0.001,offset)) : 0)
                near(attempt.coordination,max(0,1-max(0,abs(offset-window)-0.1)/(window-0.1)))
                if abs(offset-window) <= 0.1+0.000001 { near(attempt.agility,1); near(attempt.coordination,1) }
            }
        }
        // Extra obstacle preview time never enters response time.
        let short = game(), long = game()
        long.stepBeat += 3; long.stepDuration = long.stepWindowClose
        arrive(short,at:short.stepBeat); arrive(long,at:long.stepBeat)
        near(short.history[0].responseSeconds!,long.history[0].responseSeconds!)
        near(short.metrics.0,long.metrics.0)
        let early = game(); early.cue = [.left,.right]; early.prepareStep(); early.combo = 7
        early.observeShuffle(x:early.leftX,observedAge:early.stepWindowOpen-0.01)
        assert(early.history.count == 1 && early.combo == 0 && early.currentMove == .right)
        early.observeShuffle(x:early.leftX,observedAge:early.stepBeat)
        assert(early.history.count == 1,"Holding an early lane cannot later earn credit")
        early.observeShuffle(x:early.center.x,observedAge:early.stepWindowOpen)
        early.observeShuffle(x:early.rightX,observedAge:early.stepBeat)
        assert(early.history.count == 2 && early.history[1].success)
        for mode in ["vision","imu"] {
            let interrupted = game(mode); interrupted.interruptShuffle()
            if mode == "imu" { arrive(interrupted,at:interrupted.stepBeat) }
            else { interrupted.observeShuffle(x:0.44,observedAge:interrupted.stepBeat) }
            assert(interrupted.history.isEmpty && interrupted.cueAge == 0 && !interrupted.stepTrackingInterrupted)
        }
        let paused = game("cursor"); paused.cueAge = paused.stepWindowOpen+0.1
        paused.remaining = paused.stepDuration-paused.cueAge
        let age = paused.cueAge
        paused.updateDemoCursor(position:nil,insideWindow:false)
        paused.lastTick = Date().addingTimeInterval(-0.1); paused.tick(); near(paused.cueAge,age)
        paused.updateDemoCursor(position:CGPoint(x:0.5,y:0.5),insideWindow:true,observedAge:age)
        assert(!paused.stepTrackingInterrupted && paused.history.isEmpty)
        let timeout = game("cursor"); timeout.remaining = 0
        timeout.lastTick = Date().addingTimeInterval(-0.05); timeout.tick()
        assert(timeout.history.count == 1 && timeout.metrics.0 == 0 && timeout.history[0].responseSeconds == nil)
        let performance = game()
        let items = [Attempt(move:.left,success:true,reaction:0,agility:0.8,coordination:1)]
        near(performance.performance(items),0.9)
        performance.history = items; performance.zoneTime = 0; near(performance.difficulty,0.27)
        performance.phase = .boss; performance.bossHistory = items; performance.bossTime = 30; performance.tick()
        assert(performance.won,"Runner boss performance must ignore the legacy reaction metric")
        performance.handMode = true; near(performance.performance(items),0)
        let handItems = [Attempt(move:.sliceUp,success:true,reaction:0,agility:0.8,coordination:1)]
        near(performance.performance(handItems),0.72)
        let low = game(), high = game(); high.zone = 4; high.zoneTime = 180
        high.history = [Attempt(move:.left,success:true,reaction:0,agility:1,coordination:1)]
        low.newCue(); high.newCue()
        assert(low.cue.count == 1 && high.cue.count == 3)
        low.finishCue(); high.finishCue(); assert(high.rest < low.rest)
        print("PASS: obstacle preview, calibrated windows, cross-input response/timing parity, boundaries, early and late arrivals, ideal plateau, consecutive cues, interruption, cursor pause, timeout, progression and mode-specific performance")
    }
}

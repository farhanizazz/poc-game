import Foundation

@main struct ObstacleDodgeChecks {
    @MainActor static func main() {
        func near(_ a: Double,_ b: Double) { assert(abs(a-b) < 0.00001,"\(a) != \(b)") }
        func game(imu: Bool = false) -> GameModel {
            let g = GameModel(); g.startObstacles(demo:!imu,imu:imu)
            g.phase = .running; g.tracking = true; g.secondsPerLane = 0.5
            g.imuLeftSign = 1; g.imuAcceptAfter = 0
            g.pendingMoves = [.left,.right,.center,.left,.right,.center,.left,.right,.center,.left]
            g.newCue(); return g
        }
        let early = game()
        assert(early.obstacleMode && !early.handMode && !early.usesBeat && !early.timingOpen)
        assert(early.cue.count == 3 && early.cue.allSatisfy(\.directional))
        assert(early.obstaclePassTimes.count == early.cue.count)
        early.observeShuffle(x:early.leftX,observedAge:0.1)
        assert(early.history.isEmpty && early.cueIndex == 0,"Early safe arrival must not resolve or accelerate an obstacle")
        early.observeShuffle(x:early.leftX,observedAge:early.stepDuration)
        early.cueAge = early.stepDuration; early.remaining = 0; early.lastTick = Date(); early.tick()
        assert(early.history.count == 1 && early.history[0].success && early.cueIndex == 1)
        near(early.metrics.0,1); near(early.metrics.1,1)
        near(early.history[0].responseSeconds!,0.1)
        assert(early.history[0].timingError == nil && early.feedback.contains("DODGED"))
        let leave = game()
        leave.observeShuffle(x:leave.leftX,observedAge:0.1)
        leave.observeShuffle(x:leave.rightX,observedAge:leave.stepDuration-0.01)
        leave.resolveObstacle()
        assert(!leave.history[0].success && leave.combo == 0 && leave.metrics.0 == 0 && leave.metrics.1 == 0)
        let late = game()
        late.observeShuffle(x:late.leftX,observedAge:late.stepDuration+0.001)
        late.resolveObstacle()
        assert(!late.history[0].success,"Moving after physical passage cannot rescue a collision during delivery grace")
        let edge = game()
        edge.observeShuffle(x:edge.leftX,observedAge:edge.stepDuration)
        edge.resolveObstacle(); assert(edge.history[0].success,"Safe at passage counts without a beat window")
        let delayed = game()
        delayed.observeShuffle(x:delayed.rightX,observedAge:delayed.stepDuration+0.1)
        delayed.observeShuffle(x:delayed.leftX,observedAge:delayed.stepDuration-0.05)
        delayed.cueAge = delayed.stepDuration+0.3; delayed.remaining = -0.3
        let before = delayed.stepStartedUptime+delayed.stepDuration
        delayed.resolveObstacle()
        assert(delayed.history[0].success,"Pre-passage observations can arrive during delivery grace")
        near(delayed.stepStartedUptime,before); near(delayed.cueAge,0.3)
        near(delayed.remaining,delayed.stepDuration-0.3)
        let low = game(), high = game()
        high.zone = 4; high.zoneTime = 180
        high.history = [Attempt(move:.left,success:true,reaction:0,agility:1,coordination:1)]
        for g in [low,high] {
            g.positionX = g.center.x
            g.pendingMoves = [.left,.right,.center,.left,.right,.center,.left,.right,.center,.left]
            g.newCue()
            for index in 1..<g.cue.count {
                assert(g.cue[index] != g.cue[index-1] && g.obstaclePassTimes[index] > g.obstaclePassTimes[index-1])
            }
        }
        assert(low.cue.count == 3 && high.cue.count == 8)
        assert(high.obstaclePassTimes[1]-high.obstaclePassTimes[0] < low.obstaclePassTimes[1]-low.obstaclePassTimes[0])
        high.phase = .boss; high.newCue(); assert(high.cue.count == 10)
        let paused = game(); paused.cueAge = 0.5
        paused.updateDemoCursor(position:nil,insideWindow:false)
        paused.lastTick = Date().addingTimeInterval(-0.1); paused.tick()
        near(paused.cueAge,0.5); assert(paused.history.isEmpty && !paused.stepTrackingInterrupted)
        paused.updateDemoCursor(position:CGPoint(x:0.5,y:0.5),insideWindow:true,observedAge:0.5)
        paused.paused = true; paused.tick(); assert(paused.stepTrackingInterrupted)
        paused.paused = false; paused.tick()
        assert(!paused.stepTrackingInterrupted && paused.history.isEmpty && paused.cueAge < 0.1)
        let imu = game(imu:true)
        let base = ProcessInfo.processInfo.systemUptime+10
        imu.stepStartedUptime = base
        imu.receiveIMU(direction:1,start:base+0.1,end:base+0.3)
        assert(imu.lane == -1 && imu.history.isEmpty && !imu.paused)
        imu.receiveIMU(direction:1,start:base+0.1,end:base+0.3)
        assert(imu.lane == -1,"Duplicate IMU bursts cannot move again")
        imu.receiveIMU(direction:-1,start:base+0.4,end:base+0.6)
        assert(imu.lane == 0 && !imu.paused,"Leaving the safe lane is allowed; collision decides the outcome")
        imu.resolveObstacle(); assert(!imu.history[0].success)
        let balanced = game(); balanced.zoneTime = 61
        for _ in 0..<2 {
            for move in [Move.left,.right,.left,.right,.left,.right,.left,.right,.center,.center] {
                balanced.record(move,success:true,coordination:1,response:0.1)
                balanced.finishCue()
            }
        }
        assert(balanced.windows == 2 && balanced.phase == .recovery)
        balanced.rest = 0; balanced.enterBoss(); balanced.newCue()
        balanced.bossHistory = [Attempt(move:.left,success:true,reaction:0,agility:1,coordination:1)]
        balanced.bossTime = 30; balanced.tick(); assert(balanced.won)
        balanced.continueRun(); assert(balanced.obstacleMode && balanced.zone == 2)
        balanced.start(demo:true); assert(!balanced.obstacleMode)
        balanced.startObstacles(demo:true); balanced.startHands(demo:true)
        assert(!balanced.obstacleMode && balanced.handMode)
        print("PASS: no beat window, early movement, collision-time position, leaving safe lanes, late corrections, timestamped delivery, continuous wave schedule, difficulty count/spacing, boss waves, pause/restart, IMU direction/duplicates, mastery gates, mode isolation")
    }
}

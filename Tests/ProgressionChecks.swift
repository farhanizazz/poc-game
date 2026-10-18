import Foundation

@main struct ProgressionChecks {
    @MainActor static func main() {
        func game() -> GameModel {
            let g = GameModel(); g.start(demo: true)
            for x in [0.5, 0.27, 0.73, 0.5] {
                for _ in 0..<10 { g.calibrate(position: CGPoint(x:x,y:0.5),height:0.5,dt:0.1) }
            }
            assert(g.phase == .running)
            return g
        }
        func near(_ a: Double, _ b: Double) { assert(abs(a-b) < 0.0001, "\(a) != \(b)") }
        let g = game()
        g.zoneTime = 180
        near(g.difficulty, 0.55)
        assert(g.responseWindow >= g.baselineReaction * 1.2)
        // Response duration and arrival precision are independent shuffle scores.
        g.stepTravelBaseline = 1; g.stepHalfWindow = 0.5; g.cueAge = 2
        g.record(.left, success: true, travel: 1.25, error: 0, response: 0.75)
        near(g.metrics.0, 0.8); near(g.metrics.1, 1)
        g.record(.armTouch, success: true, error: 0)
        near(g.metrics.0, 0.8); near(g.metrics.1, 1)
        g.history = []
        g.record(.center, success: true, travel: 0.8, error: 0.3, response: 0.8)
        near(g.metrics.0, 0.75); near(g.metrics.1, 0.5)
        g.history = []
        g.record(.right, success: false, travel: 0.5, error: -0.7)
        near(g.metrics.0, 0); near(g.metrics.1, 0)
        g.record(.center, success: false)
        near(g.metrics.0, 0); near(g.metrics.1, 0)
        // Arrival requires actual departure and reaching the calibrated target zone.
        let arrival = game(); arrival.cue = [.left]; arrival.prepareStep()
        arrival.cueAge = 0.2; arrival.observeShuffle(x: 0.45)
        assert(arrival.lane == 0 && arrival.history.isEmpty, "Leaving center tolerance is not yet a lane arrival")
        arrival.cueAge = arrival.stepBeat; arrival.observeShuffle(x: (arrival.leftX+arrival.center.x)/2)
        assert(arrival.lane == -1, "Avatar and scoring change at the same boundary")
        assert(arrival.history.count == 1 && arrival.history[0].travelSeconds != nil)
        near(arrival.history[0].coordination, 1)
        let crossing = game(); crossing.positionX = crossing.leftX; crossing.cue = [.right]; crossing.prepareStep()
        crossing.cueAge = 0.3; crossing.observeShuffle(x: 0.4)
        crossing.cueAge = 0.6; crossing.observeShuffle(x: crossing.center.x)
        assert(crossing.history.isEmpty, "Crossing center en route to right is not an arrival")
        crossing.cueAge = crossing.stepBeat; crossing.observeShuffle(x: crossing.rightX)
        assert(crossing.history.count == 1)
        let overshoot = game(); overshoot.cue = [.right]; overshoot.prepareStep()
        overshoot.cueAge = 0.2; overshoot.observeShuffle(x: 0.56)
        overshoot.cueAge = overshoot.stepBeat; overshoot.observeShuffle(x: 0.98)
        assert(overshoot.history.count == 1 && overshoot.history[0].success && overshoot.lane == 1)
        let early = game(); early.combo = 5; early.cue = [.left]; early.prepareStep()
        early.cueAge = 0.2; early.observeShuffle(x: early.leftX)
        assert(early.history.count == 1 && !early.history[0].success && early.combo == 0, "Early spatial arrival must still obey the beat")
        // Already at the target cannot repeatedly earn credit.
        crossing.cue = [.right]; crossing.prepareStep()
        crossing.cueAge = crossing.stepBeat; crossing.observeShuffle(x: crossing.rightX)
        assert(crossing.history.count == 1)
        crossing.observeShuffle(x: crossing.rightX+0.08)
        assert(crossing.history.count == 1, "Swaying within the same lane cannot earn duplicate credit")
        // Tracking interruption discards a partial trip and reissues without a failure.
        let lost = game(); lost.cue = [.left]; lost.prepareStep()
        lost.cueAge = 0.4; lost.observeShuffle(x: 0.4); lost.interruptShuffle()
        lost.cueAge = 1.2; lost.observeShuffle(x: 0.5)
        assert(lost.history.isEmpty && lost.shuffleDeparture == nil && lost.cueAge == 0)
        lost.demo = false; lost.tracking = false
        let elapsed = lost.elapsed
        lost.lastTick = Date().addingTimeInterval(-0.05); lost.tick()
        near(lost.elapsed, elapsed)
        // Boss gates use speed/timing averages over balanced left/right/center samples.
        let boss = game(); boss.zoneTime = 61
        for _ in 0..<2 {
            for move in [Move.left,.right,.left,.right,.left,.right,.left,.right,.center,.center] {
                boss.stepTravelBaseline = 1; boss.cueAge = 1
                boss.record(move, success: true, travel: 0.9, error: 0, response: 0.5); boss.finishCue()
            }
        }
        assert(boss.windows == 2 && boss.phase == .recovery)
        boss.enterBoss(); assert(boss.phase == .recovery)
        boss.rest = 0; boss.enterBoss(); assert(boss.phase == .boss)
        for move in [Move.left,.right,.center] {
            boss.stepTravelBaseline = 1; boss.cueAge = 1
            boss.record(move, success: true, travel: 0.9, error: 0, response: 0.5)
        }
        boss.bossTime = 30; boss.lastTick = Date().addingTimeInterval(-0.05); boss.tick()
        assert(boss.won && boss.phase == .result)
        boss.continueRun(); assert(boss.zone == 2 && boss.history.isEmpty)
        let bad = game(); bad.zoneTime = 120
        for _ in 0..<30 { bad.record(.left, success: true, travel: 0.5, error: 0, response: 0.5); bad.finishCue() }
        assert(bad.windows == 0 && bad.phase == .running)
        bad.phase = .boss; bad.bossHistory = [Attempt(move: .left, success: false, reaction: 0, agility: 1, coordination: 0)]
        bad.bossTime = 30; bad.lastTick = Date().addingTimeInterval(-0.05); bad.tick()
        assert(!bad.won, "Fast shuffles with poor timing cannot pass")
        let timeout = game(); timeout.cue = [.center]; timeout.prepareStep(); timeout.remaining = 0
        timeout.lastTick = Date().addingTimeInterval(-0.05); timeout.tick()
        near(timeout.metrics.0, 0); near(timeout.metrics.1, 0)
        assert(timeout.history.count == 1)
        let demo = game(); demo.cue = [.left]; demo.prepareStep(); demo.input(.left)
        assert(demo.positionX == demo.leftX && demo.lane == -1 && demo.history.count == 1 && !demo.history[0].success, "Demo input arrives instantly; early arrival still misses the beat")
        demo.start(demo: true); assert(demo.history.isEmpty && demo.secondsPerLane == 1)
        // The optional gate changes only the consecutive-group requirement.
        func candidate() -> GameModel {
            let result = game(); result.zoneTime = 61
            result.history = [Attempt(move:.left,success:true,reaction:1,agility:1,coordination:1)]
            return result
        }
        let strict = candidate(); strict.finishCue()
        assert(strict.requireConsecutiveGroups && strict.phase == .running)
        let optional = candidate(); optional.requireConsecutiveGroups = false; optional.finishCue()
        assert(optional.phase == .recovery && optional.windows == 0)
        optional.start(demo:true); assert(!optional.requireConsecutiveGroups,"Keep the user's choice across session restarts")
        let tooSoon = candidate(); tooSoon.requireConsecutiveGroups = false; tooSoon.zoneTime = 59; tooSoon.finishCue()
        assert(tooSoon.phase == .running)
        let lowSkill = candidate(); lowSkill.requireConsecutiveGroups = false
        lowSkill.history = [Attempt(move:.left,success:false,reaction:0,agility:0.7,coordination:1)]; lowSkill.finishCue()
        assert(lowSkill.phase == .running)
        let untracked = candidate(); untracked.requireConsecutiveGroups = false; untracked.demoPointerOutside = true; untracked.finishCue()
        assert(untracked.phase == .running)
        print("PASS: calibration, response normalization, independent arrival timing, center returns, crossing detection, duplicate prevention, tracking interruption, timeout, boss gates/pass/fail, demo travel, restart")
    }
}

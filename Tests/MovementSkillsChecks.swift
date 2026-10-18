import Foundation

@main struct MovementSkillsChecks {
    @MainActor static func main() {
        func near(_ a: Double,_ b: Double) { assert(abs(a-b) < 0.00001,"\(a) != \(b)") }
        func game(combined: Bool = false) -> GameModel {
            let g = GameModel(); g.startSkills(input:.vision,combined:combined)
            g.tracking = true; g.phase = .running; g.secondsPerLane = 0.5
            for from in -1...1 { for to in -1...1 where from != to { g.skills.references[SkillsRoute(from:from,to:to)] = 0.5*Double(abs(to-from)) } }
            g.cue = [.left]; g.obstaclePassTimes = [3]; g.prepareStep()
            return g
        }
        func moveLeft(_ g: GameModel) {
            g.observeShuffle(x:0.5,observedAge:0)
            g.observeShuffle(x:0.44,observedAge:0.1)
            g.observeShuffle(x:g.leftX,observedAge:0.4)
            assert(g.skills.movement.duration == nil,"Arrival must first be confirmed")
            g.observeShuffle(x:g.leftX,observedAge:0.5)
            near(g.skills.movement.confirmedArrival!,0.4)
        }
        func touch(_ g: GameModel,hand: Int,age: Double) {
            let target = g.armTarget!, outside = CGPoint(x:target.x+0.15,y:target.y)
            g.observeArm(wrists:[outside,outside],age:age-0.08)
            g.observeArm(wrists:hand == 0 ? [target,outside] : [outside,target],age:age)
        }
        let calibration = GameModel(); calibration.startSkills(input:.vision,combined:false); calibration.tracking = true
        for x in [0.5,0.27,0.73,0.5] { for _ in 0..<10 { calibration.calibrate(position:CGPoint(x:x,y:0.5),height:0.4,dt:0.1) } }
        assert(calibration.phase == .running && calibration.skills.references.isEmpty,"Start gameplay directly after lane setup")
        calibration.cue = [.left]; calibration.obstaclePassTimes = [3]; calibration.prepareStep()
        calibration.recordSkillsObstacle(avoided:false,move:.left)
        assert(calibration.skills.samples.isEmpty && !calibration.history.last!.agilityEligible,"Incomplete movement cannot establish a baseline")
        calibration.prepareStep(); calibration.observeShuffle(x:0.44,observedAge:0.1)
        calibration.interruptShuffle(); calibration.observeShuffle(x:0.5,observedAge:0.2)
        assert(calibration.skills.samples.isEmpty,"Interrupted partial travel cannot establish a baseline")
        // Each route learns three real gameplay movements, excluded from agility scoring.
        let routes = (-1...1).flatMap { from in (-1...1).filter { $0 != from }.map { SkillsRoute(from:from,to:$0) } }
        for route in routes {
            for duration in [0.4,0.8,0.6] {
                calibration.positionX = calibration.skillsLaneX(route.from)
                let move: Move = route.to == -1 ? .left : route.to == 1 ? .right : .center
                calibration.cue = [move]; calibration.cueIndex = 0; calibration.obstaclePassTimes = [3]; calibration.prepareStep()
                calibration.skills.movement.duration = duration; calibration.skills.movement.confirmedArrival = 1
                calibration.recordSkillsObstacle(avoided:true,move:move)
                assert(!calibration.history.last!.agilityEligible)
            }
            near(calibration.skills.references[route]!,0.6)
        }
        assert(calibration.skills.references.count == 6)
        near(calibration.metrics.0,0)
        let references = calibration.skills.references
        calibration.positionX = calibration.center.x; calibration.cue = [.left]; calibration.prepareStep()
        calibration.skills.movement.duration = 1; calibration.skills.movement.confirmedArrival = 1
        calibration.recordSkillsObstacle(avoided:true,move:.left)
        assert(calibration.history.last!.agilityEligible); near(calibration.metrics.0,0.6)
        assert(calibration.skills.references == references,"Gameplay cannot modify established session references")
        // Identical movement with different waiting time has identical movement duration.
        for wait in [0.0,3.0] {
            var movement = SkillsMovement(origin:0.5,previous:(0.5,wait))
            movement.observe(x:0.6,lane:0,target:1,age:wait+1,tolerance:0.05)
            movement.observe(x:0.7,lane:1,target:1,age:wait+1.5,tolerance:0.05)
            movement.observe(x:0.7,lane:1,target:1,age:wait+1.6,tolerance:0.05)
            near(movement.duration!,1)
            near(movement.confirmedArrival!,wait+1.5)
        }
        var jitter = SkillsMovement(origin:0.5,previous:(0.5,0))
        jitter.observe(x:0.6,lane:0,target:1,age:1,tolerance:0.05)
        jitter.observe(x:0.7,lane:1,target:1,age:1.5,tolerance:0.05)
        jitter.observe(x:0.5,lane:0,target:1,age:1.55,tolerance:0.05)
        assert(jitter.duration == nil)
        jitter.observe(x:0.7,lane:1,target:1,age:1.6,tolerance:0.05)
        jitter.observe(x:0.7,lane:1,target:1,age:1.7,tolerance:0.05)
        near(jitter.confirmedArrival!,1.6)
        let hit = game(); moveLeft(hit)
        let measured = hit.skills.movement.duration!
        hit.observeShuffle(x:hit.rightX,observedAge:1)
        hit.resolveObstacle()
        assert(hit.history[0].collision == true && hit.history[0].agility == 1 && !hit.history[0].success)
        near(hit.history[0].travelSeconds!,measured)
        let slowReference = game(); slowReference.skills.references[SkillsRoute(from:0,to:-1)] = 0.1; slowReference.prepareStep()
        moveLeft(slowReference); slowReference.resolveObstacle()
        near(slowReference.metrics.0,0.1/measured)
        let miss = game(); miss.resolveObstacle(); assert(miss.metrics.0 == 0 && miss.history[0].movementRequired)
        let noMove = game(); noMove.positionX = noMove.leftX; noMove.prepareStep(); noMove.resolveObstacle()
        assert(!noMove.history[0].movementRequired && noMove.history[0].collision == false)
        let correct = game(combined:true); moveLeft(correct)
        assert(correct.armTarget != nil && correct.skills.targetSpawnAge == 0.5)
        touch(correct,hand:correct.skills.assignedHand,age:0.65)
        assert(correct.skills.outcome == .correct && correct.skills.maintainedLane == true && correct.history.isEmpty)
        correct.resolveObstacle(); assert(correct.history[0].success)
        let wrong = game(combined:true); moveLeft(wrong)
        touch(wrong,hand:1-wrong.skills.assignedHand,age:0.65)
        touch(wrong,hand:wrong.skills.assignedHand,age:0.85)
        assert(wrong.skills.outcome == .wrongHand,"Only one hand attempt is scored per obstacle")
        wrong.resolveObstacle(); assert(wrong.history[0].agility == 1 && wrong.history[0].collision == false && !wrong.history[0].success)
        let laneLost = game(combined:true); moveLeft(laneLost)
        laneLost.observeShuffle(x:laneLost.center.x,observedAge:0.55)
        laneLost.observeShuffle(x:laneLost.leftX,observedAge:0.6)
        touch(laneLost,hand:laneLost.skills.assignedHand,age:0.75)
        assert(laneLost.skills.outcome == .correct && laneLost.skills.maintainedLane == false)
        laneLost.resolveObstacle(); assert(!laneLost.history[0].success)
        let parked = game(combined:true); moveLeft(parked)
        let target = parked.armTarget!
        parked.observeArm(wrists:[target,target],age:0.6); parked.observeArm(wrists:[target,target],age:0.8)
        assert(parked.skills.outcome == .pending)
        parked.resolveObstacle(); assert(parked.history[0].handOutcome == .missed)
        let interrupted = game(combined:true); moveLeft(interrupted)
        let assigned = interrupted.skills.assignedHand
        interrupted.interruptShuffle(); interrupted.observeShuffle(x:0.5,observedAge:1)
        assert(interrupted.history.isEmpty && interrupted.armTarget == nil && interrupted.skills.movement.duration == nil && interrupted.skills.assignedHand == assigned)
        let quality = game(combined:true)
        let perfect = Attempt(move:.left,success:true,reaction:0,agility:1,movementRequired:true,handOutcome:.correct,laneMaintained:true,collision:false)
        let mistake = Attempt(move:.left,success:false,reaction:0,agility:1,movementRequired:true,handOutcome:.wrongHand,laneMaintained:false,collision:false)
        assert(quality.skillsComponents([perfect]).consistency == nil)
        near(quality.rates([perfect,perfect]).1,1)
        near(quality.skillsComponents([mistake,mistake,mistake]).consistency!,0)
        near(quality.rates([perfect,mistake,perfect]).1,0.5*(5.0/6)+0.3*(2.0/3))
        let rolling = game()
        for _ in 0..<20 { rolling.appendAttempt(Attempt(move:.left,success:true,reaction:0,agility:0.6,collision:false)) }
        for _ in 0..<30 { rolling.appendAttempt(Attempt(move:.left,success:true,reaction:0,movementRequired:false,collision:false)) }
        near(rolling.metrics.0,0.6); assert(rolling.history.count == 40)
        let single = game(), combined = game(combined:true)
        for g in [single,combined] { g.positionX = g.center.x; g.pendingMoves = [.left,.right,.center]; g.newCue() }
        near(combined.obstaclePassTimes[0]-single.obstaclePassTimes[0],1)
        near(combined.obstaclePassTimes[1]-single.obstaclePassTimes[1],2)
        let imu = GameModel(); imu.startSkills(input:.imu,combined:true); assert(!imu.skillsCombined)
        imu.tracking = true; imu.imuLeftSign = 1; imu.phase = .running
        for _ in 0..<3 {
            imu.positionX = imu.center.x; imu.lane = 0; imu.cue = [.left]; imu.cueIndex = 0; imu.obstaclePassTimes = [3]; imu.prepareStep()
            let time = ProcessInfo.processInfo.systemUptime+1; imu.imuAcceptAfter = 0; imu.stepStartedUptime = time
            imu.receiveIMU(direction:1,start:time+0.1,end:time+0.5)
            imu.recordSkillsObstacle(avoided:true,move:.left)
        }
        near(imu.skills.references[SkillsRoute(from:0,to:-1)]!,0.4)
        let cursor = GameModel(); cursor.startSkills(input:.cursor,combined:true); assert(!cursor.skillsCombined)
        cursor.phase = .running; cursor.cue = [.left]; cursor.obstaclePassTimes = [2]; cursor.prepareStep()
        cursor.updateDemoCursor(position:CGPoint(x:0.5,y:0.5),insideWindow:true,observedAge:0)
        cursor.updateDemoCursor(position:CGPoint(x:0.4,y:0.5),insideWindow:true,observedAge:0.2)
        cursor.updateDemoCursor(position:CGPoint(x:0.2,y:0.5),insideWindow:true,observedAge:0.4)
        cursor.updateDemoCursor(position:CGPoint(x:0.2,y:0.5),insideWindow:true,observedAge:0.5)
        assert(cursor.skills.movement.duration != nil,"Cursor must measure continuous travel rather than snapped lane changes")
        cursor.cueAge = 0.5; cursor.updateDemoCursor(position:nil,insideWindow:false); cursor.tick(); near(cursor.cueAge,0.5)
        quality.zoneTime = 61
        for _ in 0..<2 {
            for move in [Move.left,.right,.left,.right,.left,.right,.left,.right,.center,.center] {
                var attempt = perfect; attempt = Attempt(move:move,success:true,reaction:0,agility:1,handOutcome:.correct,laneMaintained:true,collision:false)
                quality.appendAttempt(attempt); quality.finishCue()
            }
        }
        assert(quality.phase == .recovery && quality.windows == 2)
        quality.rest = 0; quality.enterBoss(); quality.bossHistory = [perfect,perfect]; quality.bossTime = 30; quality.tick(); assert(quality.won)
        quality.continueRun(); assert(quality.skillsMode && quality.skillsCombined)
        quality.start(demo:true); assert(!quality.skillsMode && !quality.obstacleMode)
        print("PASS: in-game route learning, six fixed medians, warm-up exclusion, waiting exclusion, confirmation/backdating, route-specific movement, collision-independent agility, no-movement exclusion, combined targets, wrist identity, one attempt, lane maintenance, parked hands, interruption, weighted consistency, eligible rolling history, combined spacing, IMU calibration, continuous cursor travel, pause, progression and mode isolation")
    }
}

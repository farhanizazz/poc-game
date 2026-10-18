import SwiftUI
import Combine

enum Move: String, CaseIterable {
    case left = "SHUFFLE LEFT", right = "SHUFFLE RIGHT", center = "CENTER", armTouch = "TOUCH TARGET"
    case sliceUp = "SLICE UP", sliceDown = "SLICE DOWN", punchUp = "PUNCH UP", punchLeft = "PUNCH LEFT", punchRight = "PUNCH RIGHT"
    var icon: String { switch self { case .left: "arrow.left"; case .right: "arrow.right"; case .center: "circle.circle"; case .armTouch: "hand.point.up.left.fill"; case .sliceUp: "arrow.up.right"; case .sliceDown: "arrow.down.right"; case .punchUp: "hand.raised.fingers.spread.fill"; case .punchLeft: "arrow.left.circle.fill"; case .punchRight: "arrow.right.circle.fill" } }
    static let handMoves: [Move] = [.sliceUp,.sliceDown,.punchUp,.punchLeft,.punchRight]
    var handAction: Bool { Self.handMoves.contains(self) }
    var directional: Bool { self == .left || self == .right || self == .center }
}
struct Attempt {
    let move: Move
    let success: Bool
    let reaction: Double
    var agility: Double = 0
    var coordination: Double = 0
    var travelSeconds: Double? = nil
    var timingError: Double? = nil
    var responseSeconds: Double? = nil
    var movementRequired = true
    var agilityEligible = true
    var handOutcome: SkillsHandOutcome = .notRequired
    var laneMaintained: Bool? = nil
    var collision: Bool? = nil
}

enum TouchGrade: String {
    case perfect = "PERFECT", great = "GREAT", good = "GOOD", bad = "BAD"
    var coordination: Double { switch self { case .perfect: 1; case .great: 0.85; case .good: 0.60; case .bad: 0 } }
    static func judge(error: Double, window: Double) -> TouchGrade {
        let delta = abs(error)
        if delta > window+0.000001 { return .bad }
        if delta <= 0.100001 { return .perfect }
        if delta <= 0.200001 { return .great }
        return .good
    }
}

@MainActor final class GameModel: ObservableObject {
    enum Phase { case welcome, calibration, running, recovery, boss, result }
    @Published var phase: Phase = .welcome
    @Published var handMode = false
    @Published var obstacleMode = false
    @Published var skills = SkillsState()
    var obstaclePassTimes: [Double] = []
    var obstacleLaneSample: (age: Double, lane: Int) = (0,0)
    var obstacleResponse: Double?
    var obstacleWaveCount: Int { 3 + Int(5*difficulty) + (phase == .boss ? 2 : 0) }
    var obstacleLookAhead: Double { max(4,secondsPerLane*5) }
    var handNeutralLeft = CGPoint(x:0,y:0.5)
    var handNeutralRight = CGPoint(x:0,y:0.5)
    @Published var handInstruction = "Show both open hands at chest height"
    @Published var imuMode = false
    var imuLeftSign = 0
    var imuAcceptAfter = 0.0
    var stepStartedUptime = 0.0
    @Published var demoPointerOutside = false
    @Published var demoCursor: CGPoint?
    @Published var demoCursorSpeed: Double? // Play-frame lane widths per second.
    var cursorTripOrigin: Double?
    var cursorPrevious: (x: Double, age: Double)?
    var cursorDepartureAge: Double?
    var cursorCalibrationArrival: (x: Double, age: Double)?
    var cursorTripMeasured = false
    var cursorTripInterrupted = false
    @Published var demo = false
    @Published var paused = false
    @Published var tracking = false
    @Published var calibrationStep = 0
    @Published var hold = 0.0
    @Published var elapsed = 0.0
    @Published var zoneTime = 0.0
    @Published var zone = 1
    @Published var score = 0
    @Published var combo = 0
    @Published var lane = 0
    @Published var lastMove: Move?
    var movementTime = 0.0
    @Published var cue: [Move] = []
    @Published var cueIndex = 0
    @Published var remaining = 0.0
    @Published var feedback = "Find your rhythm."
    @Published var windows = 0
    @Published var requireConsecutiveGroups = true
    @Published var bossTime = 0.0
    @Published var won = false
    var history: [Attempt] = []
    var evaluation: [Attempt] = []
    var bossHistory: [Attempt] = []
    var rest = 0.0
    var cueAge = 0.0
    var sequenceAge = 0.0
    var pendingMoves: [Move] = []
    var baselineReaction = 1.5
    var calibrationStarted = Date()
    var center = CGPoint(x: 0.5, y: 0.5)
    var leftX = 0.3
    var rightX = 0.7
    var bodyHeight = 0.5 // Vision uses calibrated shoulder-to-hip height.
    var previousPoseTime = Date.distantPast
    @Published var armTarget: CGPoint?
    @Published var touchGrade: TouchGrade?
    var armTargetRadius = 0.06
    var shoulderMid = CGPoint(x:0.5,y:0.3)
    var shoulderSpan = 0.2
    var torsoScale = 0.3
    var armPrevious: [Int: (point: CGPoint, age: Double)] = [:]
    var armOutside: Set<Int> = []
    var shuffleLeftTarget = false
    var lastTick = Date()
    var calibrationSamples: [Double] = []
    var calibrationClock = 0.0
    var calibrationDeparture: Double?
    var calibrationArrival: Double?
    var calibrationOrigin = 0.5
    var secondsPerLane = 1.0
    @Published var positionX = 0.5
    var demoTargetX = 0.5
    var shuffleDeparture: Double?
    var shuffleOrigin = 0.5
    var stepTravelBaseline = 1.0
    var stepBeat = 1.8
    var stepHalfWindow = 0.45
    var stepDuration = 2.25
    var stepTrackingInterrupted = false
    var currentMove: Move? { cue.indices.contains(cueIndex) ? cue[cueIndex] : nil }
    var usesBeat: Bool { !obstacleMode && (currentMove?.directional == true || currentMove?.handAction == true || currentMove == .armTouch) }
    // Frozen step timing drives both scoring and obstacle presentation.
    var stepWindowOpen: Double { stepBeat - stepHalfWindow }
    var stepWindowClose: Double { stepBeat + stepHalfWindow }
    var agilityFullCreditSeconds: Double { stepHalfWindow + 0.10 }
    var timingOpen: Bool { usesBeat && cueAge >= stepWindowOpen && cueAge <= stepWindowClose }
    var timingLabel: String {
        if obstacleMode { return "DODGE · move to the clear lane anytime" }
        guard usesBeat else { return "Complete the gesture before the timer ends" }
        if currentMove == .armTouch {
            return timingOpen ? "TOUCH NOW · either hand" : cueAge < stepBeat-stepHalfWindow ? String(format:"TOUCH IN %.1fs · either hand",stepBeat-cueAge) : "Timing window closed"
        }
        if currentMove?.directional == true {
            if cueAge < stepWindowOpen { return String(format:"WAIT · MOVE IN %.1fs",stepWindowOpen-cueAge) }
            return timingOpen ? "MOVE NOW · arrive as the obstacle reaches you" : "Movement window closed"
        }
        if cueAge < stepBeat - stepHalfWindow { return String(format: handMode ? "STRIKE IN %.1fs · window ±%.2fs" : "ARRIVE IN %.1fs · window ±%.2fs", stepBeat - cueAge, stepHalfWindow) }
        return timingOpen ? (handMode ? "STRIKE NOW · match the beat" : "ARRIVE NOW · match the beat") : "Timing window closed"
    }
    func targetX(_ move: Move) -> Double { move == .left ? leftX : move == .right ? rightX : center.x }
    var zoneRadius: Double { max(0.025, min(center.x-leftX, rightX-center.x) * 0.25) }
    // One spatial decision drives the avatar, position indicator, and arrival scoring.
    // Side zones extend outward so overshooting a box still counts as arrival.
    func laneAt(_ x: Double) -> Int {
        x <= (leftX + center.x)/2 ? -1 : x >= (rightX + center.x)/2 ? 1 : 0
    }
    func laneFor(_ move: Move) -> Int { move == .left ? -1 : move == .right ? 1 : 0 }
    var positionLabel: String { lane == -1 ? "LEFT" : lane == 1 ? "RIGHT" : "CENTER" }
    func routeUnits(from: Double, to: Double) -> Double {
        let span = max(0.05, (rightX-leftX)/2)
        return max(0.5, abs(to-from)/span)
    }
    var calibrationTitle: String { if handMode { return ["Open hands in guard", "Make two fists in guard", "Open hands — return to guard"][min(2,calibrationStep)] }; return ["Stand in the center", "Shuffle into the LEFT box", "Shuffle into the RIGHT box", "Return to center"][min(3, calibrationStep)] }
    var active: Bool { phase == .running || phase == .boss }
    var reliable: Bool { demo ? !demoPointerOutside : tracking }
    func rates(_ items: [Attempt]) -> (Double, Double, Double) {
        if skillsMode {
            let movements = Array(items.filter { $0.movementRequired && $0.agilityEligible }.suffix(20))
            let agility = movements.isEmpty ? 0 : movements.map(\.agility).reduce(0,+)/Double(movements.count)
            let components = skillsComponents(items)
            let quality = skillsCombined ? 0.5*components.accuracy+0.3*components.control+0.2*(components.consistency ?? 0) : components.accuracy
            return (agility,quality,0)
        }
        let shuffles = items.filter { handMode ? $0.move.handAction : $0.move.directional }
        let a = shuffles.isEmpty ? 0 : shuffles.map(\.agility).reduce(0,+) / Double(shuffles.count)
        let timedActions = items.filter { handMode ? $0.move.handAction : ($0.move.directional || $0.move == .armTouch) }
        let c = timedActions.isEmpty ? 0 : timedActions.map(\.coordination).reduce(0,+) / Double(timedActions.count)
        return (a, c, items.isEmpty ? 0 : items.map(\.reaction).reduce(0,+) / Double(items.count))
    }

    var metrics: (Double, Double, Double) { rates(skillsMode ? history : Array(history.suffix(20))) }
    func performance(_ items: [Attempt]) -> Double {
        let (a,c,r) = rates(items)
        return handMode ? 0.4*a + 0.4*c + 0.2*r : 0.5*a + 0.5*c
    }
    var difficulty: Double {
        let (a,c,_) = metrics
        let cap = min(1, 0.55 + Double(zone - 1) * 0.15)
        let adaptation = history.count >= 10 && (!skillsMode || skills.references.count == 6) && min(a,c) < 0.75 ? 0.75 : 1.0
        return min(cap, max(0, 0.7 * min(1, zoneTime / 180) + 0.3 * performance(skillsMode ? history : Array(history.suffix(20))))) * adaptation
    }
    var responseWindow: Double { max(2.5 - difficulty, baselineReaction * 1.2) }
    func start(demo: Bool) {
        skills = SkillsState()
        imuMode = false; handMode = false; obstacleMode = false
        obstaclePassTimes = []; obstacleResponse = nil; obstacleLaneSample = (0,0)
        handInstruction = "Show both open hands at chest height"
        elapsed = 0; zoneTime = 0; zone = 1; score = 0; combo = 0; lane = 0
        history = []; evaluation = []; bossHistory = []; windows = 0; bossTime = 0
        cue = []; cueIndex = 0; lastMove = nil; won = false; armTarget = nil; touchGrade = nil
        pendingMoves = []; cueAge = 0; sequenceAge = 0; rest = 0; movementTime = 0
        tracking = false; center = CGPoint(x: 0.5, y: 0.5); leftX = 0.3; rightX = 0.7
        lastTick = Date()
        baselineReaction = 1.5; previousPoseTime = .distantPast; feedback = "Find your rhythm."
        self.demo = demo; demoPointerOutside = false; demoCursor = nil; demoCursorSpeed = nil; resetCursorTravel(); phase = .calibration; calibrationStep = 0; hold = 0
        calibrationStarted = Date(); calibrationSamples = []; paused = false
        calibrationClock = 0; calibrationDeparture = nil; calibrationArrival = nil; calibrationOrigin = 0.5
        secondsPerLane = 1; positionX = 0.5; demoTargetX = 0.5; shuffleDeparture = nil
        stepTrackingInterrupted = false
        shoulderMid = CGPoint(x:0.5,y:0.3); shoulderSpan = 0.2; torsoScale = 0.3
        resetArmContact()
    }
    func startObstacles(demo: Bool = false, imu: Bool = false) {
        if imu { startIMU() } else { start(demo:demo) }
        obstacleMode = true
        feedback = "Move into the clear lane before each obstacle reaches you."
    }
    func resetArmContact() { armPrevious = [:]; armOutside = [] }
    func calibrate(position: CGPoint, height: Double, dt: Double) {
        guard phase == .calibration, reliable, !paused else { return }
        calibrationClock += dt
        let target = calibrationStep == 1 ? 0.27 : calibrationStep == 2 ? 0.73 : 0.5
        if calibrationStep > 0, calibrationDeparture == nil, abs(position.x-calibrationOrigin) > 0.04 {
            calibrationDeparture = calibrationClock
        }
        guard abs(position.x - target) < 0.07 else { hold = 0; calibrationArrival = nil; return }
        if calibrationArrival == nil { calibrationArrival = calibrationClock }
        hold += dt
        guard hold >= 0.8 else { return }
        if calibrationStep == 0 { center = position; bodyHeight = max(0.08, height) }
        if calibrationStep == 1 { leftX = position.x }
        if calibrationStep == 2 { rightX = position.x }
        if calibrationStep > 0 {
            if demo, !cursorTripInterrupted, let departure = cursorDepartureAge,
               let arrival = cursorCalibrationArrival, let origin = cursorTripOrigin,
               arrival.age > departure {
                let units = max(0.05,abs(arrival.x-origin)*3)
                calibrationSamples.append((arrival.age-departure)/units)
            } else if !demo, let departure = calibrationDeparture, let arrival = calibrationArrival {
                let units = max(0.5,abs(position.x-calibrationOrigin)/0.23)
                if arrival-departure > 0.1 { calibrationSamples.append((arrival-departure)/units) }
            }
        }
        if demo { resetCursorTravel(age:calibrationClock) }
        calibrationOrigin = position.x; calibrationDeparture = nil; calibrationArrival = nil
        calibrationStarted = Date(); calibrationStep += 1; hold = 0
        if calibrationStep == 4 {
            center = position; bodyHeight = max(0.08, height)
            secondsPerLane = calibrationSamples.isEmpty ? 1 : max(demo ? 0.05 : 0.35, calibrationSamples.reduce(0,+) / Double(calibrationSamples.count))
            baselineReaction = max(1, secondsPerLane)
            positionX = position.x; demoTargetX = position.x
            phase = .running; rest = 1; feedback = "Calibration complete. Let's run!"
            if skillsMode { feedback = "Learning your shuffle speeds as you play." }
        }
    }
    func resetCursorTravel(age: Double = 0) {
        cursorTripOrigin = demoCursor.map { Double($0.x) }
        cursorPrevious = demoCursor.map { (Double($0.x),age) }
        cursorDepartureAge = nil; cursorCalibrationArrival = nil
        cursorTripMeasured = false; cursorTripInterrupted = false
    }
    func sampleCursorTravel(x: Double, age: Double) {
        cursorTripMeasured = true
        guard let origin = cursorTripOrigin else {
            cursorTripOrigin = x; cursorPrevious = (x,age); return
        }
        if cursorDepartureAge == nil, abs(x-origin) > 0.02 {
            // Exclude waiting and tiny pointer jitter. Estimate the first crossing
            // of the departure tolerance between observed cursor samples.
            var departure = age
            if let previous = cursorPrevious, age > previous.age, abs(x-previous.x) > 0.000001 {
                let boundary = origin+(x > origin ? 0.02 : -0.02)
                let fraction = min(1,max(0,(boundary-previous.x)/(x-previous.x)))
                departure = previous.age+fraction*(age-previous.age)
            }
            cursorDepartureAge = departure
            if active { shuffleDeparture = departure }
        }
        cursorPrevious = (x,age)
    }
    func updateDemoCursor(position: CGPoint?, insideWindow: Bool, observedAge: Double? = nil) {
        guard demo else { return }
        demoPointerOutside = !insideWindow
        demoCursor = position
        guard insideWindow, !paused else {
            cursorPrevious = nil; cursorTripInterrupted = true
            resetArmContact(); return
        }
        guard !handMode, let position else { return }
        if phase == .calibration {
            sampleCursorTravel(x:position.x,age:calibrationClock)
            let targetLane = calibrationStep == 1 ? -1 : calibrationStep == 2 ? 1 : 0
            let pointerLane = position.x < 1.0/3 ? -1 : position.x > 2.0/3 ? 1 : 0
            if pointerLane != targetLane { cursorCalibrationArrival = nil }
            else if cursorCalibrationArrival == nil, cursorDepartureAge != nil {
                cursorCalibrationArrival = (position.x,calibrationClock)
            }
            demoTargetX = position.x < 1.0/3 ? 0.27 : position.x > 2.0/3 ? 0.73 : 0.5
        } else if active {
            if currentMove == .armTouch {
                guard (0...1).contains(position.x), (0...1).contains(position.y) else { resetArmContact(); return }
                let age = cueAge+min(0.1,max(0,Date().timeIntervalSince(lastTick)))
                observeArm(wrists:[position,nil],age:age)
            } else {
                let age = observedAge ?? cueAge+min(0.1,max(0,Date().timeIntervalSince(lastTick)))
                if skillsMode { observeShuffle(x:skillsCursorX,observedAge:age); return }
                sampleCursorTravel(x:position.x,age:age)
                setDemoLane(position.x < 1.0/3 ? .left : position.x > 2.0/3 ? .right : .center,age:age)
            }
        }
    }
    // Demo input arrives immediately; camera/IMU movement keeps its measured timing.
    func setDemoLane(_ move: Move, age: Double? = nil) {
        guard demo, !handMode, move.directional, active, reliable, !paused else { return }
        demoTargetX = targetX(move)
        observeShuffle(x:demoTargetX,observedAge:age)
    }
    func input(_ move: Move) {
        guard active, !paused, reliable else { return }
        if move.directional {
            setDemoLane(move)
            return
        }
        if handMode && move.handAction { receiveHand(move, duration: 0.4); return }
        if move == .armTouch { if demo { receiveArmTouch(age:cueAge) }; return }
        lastMove = move; movementTime = 0.6
        guard let expected = currentMove, !expected.directional else { return }
        record(expected, success: expected == move)
        advanceStep(success: expected == move)
    }
    func prepareStep() {
        let reissued = stepTrackingInterrupted
        stepStartedUptime = ProcessInfo.processInfo.systemUptime
        resetCursorTravel()
        cueAge = 0; shuffleDeparture = nil; shuffleOrigin = positionX; stepTrackingInterrupted = false
        let move = currentMove ?? .center
        shuffleLeftTarget = laneAt(positionX) != laneFor(move)
        stepTravelBaseline = (move.handAction || move == .armTouch) ? 0.65 : secondsPerLane * routeUnits(from: positionX, to: targetX(move))
        stepHalfWindow = max(0.3, 0.5 - 0.2*difficulty)
        if move.directional { stepHalfWindow = max(stepHalfWindow, stepTravelBaseline + 0.25) }
        stepBeat = max(1.5, stepTravelBaseline * 1.4 + 0.4)
        stepDuration = usesBeat ? stepBeat + stepHalfWindow : responseWindow
        armTarget = nil; resetArmContact()
        if move == .armTouch {
            armTargetRadius = max(0.04, min(0.075,torsoScale*0.2))
            let candidates: [CGPoint] = [-1.0,1.0].flatMap { side -> [CGPoint] in [-0.2,0.35].map { vertical in
                CGPoint(x:max(0.1,min(0.9,shoulderMid.x+side*shoulderSpan*0.95)),
                        y:max(0.15,min(0.65,shoulderMid.y+vertical*torsoScale)))
            } }
            armTarget = candidates.randomElement()
        }
        remaining = stepDuration
        if obstacleMode {
            let previousPass = cueIndex == 0 ? 0 : obstaclePassTimes[cueIndex-1]
            stepDuration = obstaclePassTimes[cueIndex]-previousPass
            remaining = stepDuration
            obstacleLaneSample = (0,laneAt(positionX))
            obstacleResponse = laneAt(positionX) == laneFor(move) ? 0 : nil
        }
        if skillsMode { prepareSkillsStep(move,reissued:reissued) }
    }
    func observeShuffle(x: Double, observedAge: Double? = nil) {
        guard active, reliable, !paused else { return }
        positionX = x
        lane = laneAt(x)
        // Reissue an interrupted step from the reacquired position; no partial trip is scored.
        if stepTrackingInterrupted { prepareStep(); return }
        guard let move = currentMove, move.directional else { return }
        let age = observedAge ?? cueAge
        if obstacleMode {
            if skillsMode { observeSkillsMovement(age:age) }
            observeObstacleLane(age:age); return
        }
        if lane != laneFor(move) { shuffleLeftTarget = true }
        if shuffleDeparture == nil, abs(x-shuffleOrigin) > zoneRadius { shuffleDeparture = age }
        guard shuffleLeftTarget, let departure = shuffleDeparture, lane == laneFor(move) else { return }
        var travel: Double? = max(0.05,age-departure)
        if demo && cursorTripMeasured {
            travel = nil
            if !cursorTripInterrupted, let started = cursorDepartureAge,
               let origin = cursorTripOrigin, let cursor = demoCursor, age > started {
                travel = age-started
                let distance = abs(cursor.x-origin)*3
                demoCursorSpeed = distance/(age-started)
            } else { demoCursorSpeed = nil }
        }
        completeShuffle(move, arrivalAge:age, travel:travel)
    }
    func observeObstacleLane(age: Double) {
        guard age >= 0, age <= stepDuration, age >= obstacleLaneSample.age else { return }
        obstacleLaneSample = (age,laneAt(positionX))
        if let move = currentMove, laneAt(positionX) == laneFor(move), obstacleResponse == nil {
            obstacleResponse = age
        }
    }
    func resolveObstacle() {
        guard let move = currentMove else { return }
        let nextStart = stepStartedUptime+stepDuration
        let overshoot = max(0,cueAge-stepDuration)
        let previousIndex = cueIndex
        let avoided = obstacleLaneSample.lane == laneFor(move)
        var success = avoided
        if skillsMode {
            recordSkillsObstacle(avoided:avoided,move:move)
            success = (phase == .boss ? bossHistory.last : history.last)?.success ?? false
        } else {
            record(move,success:avoided,coordination:avoided ? 1 : 0,response:obstacleResponse)
            feedback = avoided ? "DODGED · clear lane" : "HIT · obstacle collision"
            if avoided, let response = obstacleResponse { feedback += String(format:" · response %.2fs",response) }
        }
        advanceStep(success:success,keepFeedback:true)
        // Delivery grace must not add a pause between physical obstacles.
        if active, !cue.isEmpty, cueIndex == previousIndex+1 {
            stepStartedUptime = nextStart; cueAge = overshoot; remaining = stepDuration-overshoot
            obstacleLaneSample = (overshoot,laneAt(positionX))
            if skillsMode {
                skills.movement.previous = (positionX,overshoot)
                skills.laneEvents = [(overshoot,laneAt(positionX))]
            }
        }
    }
    func completeShuffle(_ move: Move, arrivalAge: Double, travel: Double?) {
        let error = arrivalAge-stepBeat
        let onTime = arrivalAge >= stepWindowOpen-0.000001 && arrivalAge <= stepWindowClose+0.000001
        let response = arrivalAge-stepWindowOpen
        lastMove = move; movementTime = 0.6
        record(move, success:onTime, travel:travel, error:error, response:response)
        let timing = onTime ? "ON TIME" : arrivalAge < stepWindowOpen ? "EARLY · WAIT FOR MOVE NOW" : "LATE"
        feedback = response < 0
            ? String(format:"%@ · %.2fs before movement window",timing,-response)
            : String(format:"%@ · response %.2fs · %+.2fs from beat",timing,response,error)
        if imuMode { feedback = "IMU estimate · " + feedback }
        advanceStep(success:onTime,keepFeedback:true)
    }
    func interruptShuffle() {
        if usesBeat || (obstacleMode && currentMove != nil) || (!demo && !imuMode && !handMode && currentMove != nil) { stepTrackingInterrupted = true }
        resetArmContact()
    }
    func record(_ move: Move, success: Bool, travel: Double? = nil, error: Double? = nil, coordination: Double? = nil, response: Double? = nil) {
        let speed = travel.map { min(1, stepTravelBaseline / max(0.001, $0)) } ?? 0
        let agility: Double
        if !handMode && move.directional {
            let allowance = obstacleMode ? stepTravelBaseline : agilityFullCreditSeconds
            agility = success ? response.map { min(1,allowance/max(0.001,$0)) } ?? 0 : 0
        } else { agility = speed }
        // Full timing credit within 100ms; linear falloff to zero at the window edge.
        let timing = error.map { max(0, min(1, 1 - max(0, abs($0)-0.1) / max(0.01, stepHalfWindow-0.1))) } ?? 0
        let result = Attempt(move: move, success: success,
            reaction: success ? min(1, baselineReaction / max(0.15, shuffleDeparture ?? cueAge)) : 0,
            agility: agility, coordination: coordination ?? timing, travelSeconds: travel, timingError: error, responseSeconds:response)
        appendAttempt(result)
    }
    func appendAttempt(_ result: Attempt) {
        if phase == .boss { bossHistory.append(result) }
        else {
            history.append(result)
            if skillsMode {
                let eligible = history.indices.filter { history[$0].movementRequired && history[$0].agilityEligible }.suffix(20)
                let keep = Set(eligible).union(history.indices.suffix(20))
                history = history.enumerated().filter { keep.contains($0.offset) }.map(\.element)
            } else if history.count > 20 { history.removeFirst(history.count - 20) }
            evaluation.append(result)
        }
    }
    func advanceStep(success: Bool, keepFeedback: Bool = false) {
        if success { combo += 1; score += 100 + min(combo,20)*10 } else { combo = 0 }
        if !keepFeedback { feedback = success ? "NICE!" : "Missed — reset your rhythm" }
        cueIndex += 1
        if cueIndex >= cue.count { finishCue() } else { prepareStep() }
    }
    func finishCue() {
        cue = []; armTarget = nil; resetArmContact(); cueIndex = 0; rest = max(0.5, (3 - 1.5*difficulty) - sequenceAge)
        if obstacleMode { rest = max(0.35,1.2-0.8*difficulty) }
        guard phase == .running else { return }
        let left = evaluation.filter { $0.move == .left }.count
        let right = evaluation.filter { $0.move == .right }.count
        let centers = evaluation.filter { $0.move == .center }.count
        let balancedHands = Move.handMoves.allSatisfy { move in evaluation.filter { $0.move == move }.count >= 2 }
        if evaluation.count >= 10 && (handMode ? balancedHands : left >= 4 && right >= 4 && centers >= 2) {
            let (a,c,_) = rates(evaluation)
            windows = a >= 0.8 && c >= 0.85 && (!skillsMode || skills.references.count == 6) ? windows + 1 : 0
            evaluation = []
        }
        if zoneTime >= 60 && metrics.0 >= 0.8 && metrics.1 >= 0.85 && (!requireConsecutiveGroups || windows >= 2) && reliable && (!skillsMode || skills.references.count == 6) && (!skillsCombined || skillsComponents(history).consistency != nil) {
            phase = .recovery; rest = 5; feedback = "Mastery gate passed. Breathe before the arena."
        }
    }
    func newCue() {
        if obstacleMode { newObstacleWave(); return }
        if handMode {
            if pendingMoves.isEmpty { pendingMoves = (Move.handMoves + Move.handMoves).shuffled() }
            let count = phase == .boss ? 2 : 1 + Int(2*difficulty)
            cue = []
            for _ in 0..<count {
                if pendingMoves.isEmpty { pendingMoves = (Move.handMoves + Move.handMoves).shuffled() }
                cue.append(pendingMoves.removeFirst())
            }
            cueIndex = 0; sequenceAge = 0; prepareStep(); return
        }
        let pool: [Move] = imuMode ? [.left, .right, .center] : [.left, .right, .center, .armTouch]
        // Shuffle a balanced bag: random order without starving either movement skill.
        if pendingMoves.isEmpty {
            pendingMoves = ([Move.left,.left,.left,.left,.right,.right,.right,.right,.center,.center] + (imuMode ? [] : [.armTouch,.armTouch,.armTouch])).shuffled()
        }
        // Already standing on a target is not a shuffle. Insert a center/side return first.
        let candidate = pendingMoves[0]
        let first: Move
        if candidate.directional && laneAt(positionX) == laneFor(candidate) {
            first = candidate == .center ? (Bool.random() ? .left : .right) : .center
        } else { first = pendingMoves.removeFirst() }
        cue = [first]
        let count = phase == .boss ? max(2, 1 + Int(2*difficulty)) : 1 + Int(2*difficulty)
        while cue.count < count {
            let predictedX = cue.last(where: { $0.directional }).map { targetX($0) } ?? positionX
            cue.append(pool.filter { !$0.directional || abs(targetX($0)-predictedX) > zoneRadius }.randomElement()!)
        }
        cueIndex = 0; sequenceAge = 0; prepareStep()
    }
    func newObstacleWave() {
        cue = []; obstaclePassTimes = []
        var origin = positionX
        var passTime = 0.0
        let density = difficulty
        for index in 0..<obstacleWaveCount {
            if pendingMoves.isEmpty { pendingMoves = [Move.left,.left,.left,.left,.right,.right,.right,.right,.center,.center].shuffled() }
            let candidate = pendingMoves[0]
            let move: Move
            if laneAt(origin) == laneFor(candidate) {
                move = candidate == .center ? (Bool.random() ? .left : .right) : .center
            } else { move = pendingMoves.removeFirst() }
            let route = SkillsRoute(from:laneAt(origin),to:laneFor(move))
            let travel = (skillsMode ? skills.references[route] : nil) ?? secondsPerLane*routeUnits(from:origin,to:targetX(move))
            // Physical spacing allows calibrated travel; no arrival beat or early penalty.
            passTime += max(0.55,travel*(1.5-0.4*density)+0.35) + (index == 0 ? 0.8 : 0) + (skillsCombined ? 1 : 0)
            cue.append(move); obstaclePassTimes.append(passTime)
            origin = targetX(move)
        }
        cueIndex = 0; sequenceAge = 0; prepareStep()
    }
    func tick() {
        let now = Date(); let dt = min(0.1, now.timeIntervalSince(lastTick)); lastTick = now
        // Cursor exits freeze the current cue exactly, independently of manual pause.
        guard !demo || !demoPointerOutside else { resetArmContact(); return }
        guard !paused, reliable else { interruptShuffle(); return }
        movementTime -= dt
        if movementTime <= 0 { lastMove = nil }
        if phase == .recovery { rest = max(0,rest-dt); return }
        guard active else { return }
        elapsed += dt
        if phase == .running { zoneTime += dt } else { bossTime += dt }
        if phase == .boss && bossTime >= 30 {
            // Only completed/timed-out cues count. No pending instruction is scored as a miss.
            let (a,c,_) = rates(bossHistory)
            won = performance(bossHistory) >= 0.85 && a >= 0.8 && c >= 0.8 && (!skillsCombined || skillsComponents(bossHistory).consistency != nil)
            phase = .result; cue = []; return
        }
        if cue.isEmpty { rest -= dt; if rest <= 0 { newCue() }; return }
        if stepTrackingInterrupted {
            if demo || (obstacleMode && imuMode) { prepareStep() } else { return }
        }
        if !demo && !imuMode && !handMode {
            cueAge = max(0, ProcessInfo.processInfo.systemUptime-stepStartedUptime)
            remaining = stepDuration-cueAge
        } else { remaining -= dt; cueAge += dt }
        sequenceAge += dt
        // Allow in-flight Vision work to finish; the scored timing window stays unchanged.
        let deliveryAllowance = imuMode ? 0.65 : (!demo && !handMode ? 0.3 : skillsMode ? 0.1 : 0)
        if remaining <= -deliveryAllowance {
            if obstacleMode { resolveObstacle(); return }
            let armMiss = currentMove == .armTouch
            record(cue[cueIndex], success: false)
            if armMiss { touchGrade = .bad; feedback = "BAD · missed target" }
            advanceStep(success: false, keepFeedback: armMiss)
        }
    }
    func receiveArmTouch(age: Double) {
        guard !handMode, !imuMode, active, reliable, !paused, !stepTrackingInterrupted,
              currentMove == .armTouch, armTarget != nil, age >= 0 else { return }
        let error = age-stepBeat
        let grade = TouchGrade.judge(error:error,window:stepHalfWindow)
        touchGrade = grade; lastMove = .armTouch; movementTime = 0.8
        record(.armTouch, success: grade != .bad, error:error, coordination:grade.coordination)
        feedback = String(format:"%@ · touch %+.0fms from beat",grade.rawValue,error*1000)
        advanceStep(success:grade != .bad,keepFeedback:true)
    }
    func observeArm(wrists: [CGPoint?], age: Double) {
        guard active, reliable, !paused, !handMode, !imuMode, (currentMove == .armTouch || skillsCombined),
              let target = armTarget, !stepTrackingInterrupted else { return }
        var contacts: [(hand: Int, age: Double)] = []
        for (index, maybePoint) in wrists.enumerated() {
            guard let point = maybePoint else { armPrevious[index] = nil; armOutside.remove(index); continue }
            let dx = point.x-target.x, dy = point.y-target.y
            let inside = hypot(dx,dy) <= armTargetRadius
            let previous = armPrevious[index]
            armPrevious[index] = (point,age)
            // Parking a hand on a new cue earns nothing: leave and enter first.
            if !armOutside.contains(index) {
                if !inside { armOutside.insert(index) }
                continue
            }
            var contactAge: Double?
            if let previous, age > previous.age, age-previous.age <= 0.15 {
                // Sweep the wrist segment through the same circle drawn on screen.
                // Interpolate first contact to avoid missing fast swipes between frames.
                let vx = point.x-previous.point.x, vy = point.y-previous.point.y
                let ox = previous.point.x-target.x, oy = previous.point.y-target.y
                let a = vx*vx+vy*vy, b = 2*(ox*vx+oy*vy)
                let c = ox*ox+oy*oy-armTargetRadius*armTargetRadius
                let discriminant = b*b-4*a*c
                if a > 0.000001, c > 0, discriminant >= 0 {
                    let t = (-b-sqrt(discriminant))/(2*a)
                    if t >= 0 && t <= 1 { contactAge = previous.age+t*(age-previous.age) }
                }
            }
            if contactAge == nil && inside { contactAge = age }
            if let contactAge {
                if skillsCombined { contacts.append((index,contactAge)) }
                else { receiveArmTouch(age:contactAge); return }
            }
        }
        if let contact = contacts.sorted(by: { $0.age == $1.age ? $0.hand < $1.hand : $0.age < $1.age }).first {
            receiveSkillsTouch(hand:contact.hand,age:contact.age)
        }
    }
    func startHands(demo: Bool = false) {
        start(demo: demo); handMode = true
    }
    func calibrateHands(guardOK: Bool, left: CGPoint, right: CGPoint, dt: Double) {
        guard handMode, phase == .calibration, reliable, !paused else { return }
        guard guardOK else { hold = 0; return }
        hold += dt
        guard hold >= 0.8 else { return }
        hold = 0; calibrationStep += 1
        if calibrationStep == 3 {
            handNeutralLeft = left; handNeutralRight = right
            phase = .running; rest = 1; feedback = "Hands calibrated · return to guard between strikes"
        }
    }
    func receiveHand(_ move: Move, duration: Double) {
        guard handMode, active, reliable, !paused, let expected = currentMove,
              expected.handAction, duration >= 0.08, duration <= 1.2, cueAge >= duration else { return }
        lastMove = move; movementTime = 0.5
        let error = cueAge-stepBeat
        let correct = move == expected
        let onTime = abs(error) <= stepHalfWindow && correct
        record(expected, success: onTime, travel: correct ? duration : nil, error: correct ? error : nil)
        feedback = correct ? String(format:"%@ · stroke %.2fs · %+.2fs from beat", onTime ? "ON BEAT" : error < 0 ? "EARLY" : "LATE",duration,error) : "Wrong strike · return to guard"
        advanceStep(success:onTime,keepFeedback:true)
    }
    func startIMU() {
        start(demo: false); imuMode = true; imuLeftSign = 0
        imuAcceptAfter = ProcessInfo.processInfo.systemUptime
    }
    func centerIMU() {
        guard imuMode, reliable else { return }
        positionX = center.x; lane = 0; paused = false
        imuAcceptAfter = ProcessInfo.processInfo.systemUptime
        if skillsMode && active && !cue.isEmpty { prepareStep() }
        else if phase == .calibration { calibrationStep = 1; calibrationSamples = []; imuLeftSign = 0 }
        else if active { cue = []; cueIndex = 0; rest = 1; stepTrackingInterrupted = false }
    }
    func receiveIMU(direction: Int, start: Double, end: Double) {
        guard imuMode, reliable, !paused, start >= imuAcceptAfter,
              start.isFinite, end.isFinite, end > start, end-start <= 4, abs(direction) == 1 else { return }
        if phase == .calibration {
            guard calibrationStep > 0 && calibrationStep < 4 else { return }
            if calibrationStep == 1 { imuLeftSign = direction }
            let expected = calibrationStep == 2 ? -imuLeftSign : imuLeftSign
            guard direction == expected else { feedback = "Wrong direction. Follow the calibration instruction."; return }
            calibrationSamples.append((end-start) / (calibrationStep == 2 ? 2 : 1))
            positionX = calibrationStep == 1 ? leftX : calibrationStep == 2 ? rightX : center.x
            lane = calibrationStep == 1 ? -1 : calibrationStep == 2 ? 1 : 0
            calibrationStep += 1; imuAcceptAfter = end
            if calibrationStep == 4 {
                secondsPerLane = max(0.35, calibrationSamples.reduce(0,+)/Double(calibrationSamples.count))
                baselineReaction = max(1, secondsPerLane); phase = .running; rest = 1
                feedback = "IMU calibrated · arrival is estimated from stopping"
                if skillsMode { feedback = "Learning your shuffle speeds as you play." }
            }
            return
        }
        guard active, let move = currentMove, move.directional, start >= stepStartedUptime else { return }
        guard !stepTrackingInterrupted else { prepareStep(); return }
        if obstacleMode {
            let delta = direction == imuLeftSign ? -1 : 1
            let targetLane = laneFor(move)
            let destination = (targetLane-lane)*delta > 0 ? targetLane : max(-1,min(1,lane+delta))
            lane = destination
            positionX = destination == -1 ? leftX : destination == 1 ? rightX : center.x
            imuAcceptAfter = end
            if skillsMode {
                let age = end-stepStartedUptime
                if skills.movement.departure == nil { skills.movement.departure = start-stepStartedUptime }
                if destination == targetLane, age <= stepDuration, skills.movement.duration == nil {
                    skills.movement.arrival = age; skills.movement.confirmedArrival = age
                    skills.movement.duration = age-skills.movement.departure!
                }
            }
            observeObstacleLane(age:end-stepStartedUptime)
            return
        }
        let expected = targetX(move) < positionX ? imuLeftSign : -imuLeftSign
        guard direction == expected else {
            record(move, success: false); advanceStep(success: false)
            paused = true; feedback = "Wrong direction — return to center, then Resume"
            return
        }
        let arrivalAge = end-stepStartedUptime
        cueAge = arrivalAge; shuffleDeparture = start-stepStartedUptime
        positionX = targetX(move); lane = move == .left ? -1 : move == .right ? 1 : 0
        completeShuffle(move,arrivalAge:arrivalAge,travel:end-start)
    }
    func enterBoss() {
        guard phase == .recovery, rest <= 0, reliable, !paused else { return }
        phase = .boss; bossTime = 0; bossHistory = []; pendingMoves = []; cue = []; rest = 1
        feedback = "SENTINEL / 01 — 30 second mastery test"
    }
    func continueRun() {
        guard phase == .result else { return }
        if won { zone += 1 }
        phase = .running; zoneTime = 0; windows = 0; history = []; evaluation = []; cue = []; rest = 3; combo = 0
        pendingMoves = []
        feedback = won ? "New zone unlocked!" : "Recover, practice, and try again."
    }
}

// Movement Skills uses separate configuration and measurements from the legacy modes.
enum SkillsInput: String, CaseIterable { case vision = "Vision", cursor = "Cursor simulation", imu = "iPhone IMU estimate" }
struct SkillsConfiguration {
    let input: SkillsInput
    let combined: Bool
    init(input: SkillsInput, combined: Bool) { self.input = input; self.combined = combined && input == .vision }
}
struct SkillsRoute: Hashable {
    let from: Int
    let to: Int
}
enum SkillsHandOutcome: String {
    case notRequired, pending, correct = "Correct hand", wrongHand = "Wrong hand", outsideLane = "Lane lost", missed = "Missed target"
}
struct SkillsMovement {
    var origin = 0.5
    var departure: Double?
    var arrival: Double?
    var confirmedArrival: Double?
    var duration: Double?
    var previous: (x: Double, age: Double)?
    mutating func observe(x: Double, lane: Int, target: Int, age: Double, tolerance: Double) {
        guard duration == nil, age >= 0, previous == nil || age >= previous!.age else { return }
        if departure == nil, abs(x-origin) > tolerance {
            departure = age
            if let previous, age > previous.age, abs(x-previous.x) > 0.000001 {
                let boundary = origin + (x > origin ? tolerance : -tolerance)
                let fraction = min(1,max(0,(boundary-previous.x)/(x-previous.x)))
                departure = previous.age + fraction*(age-previous.age)
            }
        }
        previous = (x,age)
        if lane != target { arrival = nil; return }
        if arrival == nil { arrival = age }
        if let arrival, age-arrival >= 0.1-0.000001 {
            confirmedArrival = arrival
            if let departure, arrival > departure { duration = arrival-departure }
        }
    }
}
struct SkillsState {
    var configuration: SkillsConfiguration?
    var references: [SkillsRoute: Double] = [:]
    var samples: [SkillsRoute: [Double]] = [:]
    var movement = SkillsMovement()
    var movementRequired = true
    var referenceAtStart: Double?
    var route = SkillsRoute(from:0,to:-1)
    var leftShoulder = CGPoint(x:0.4,y:0.3)
    var rightShoulder = CGPoint(x:0.6,y:0.3)
    var assignedHand = 0
    var handBag: [Int] = []
    var outcome: SkillsHandOutcome = .notRequired
    var targetSpawnAge: Double?
    var contactAge: Double?
    var maintainedLane: Bool?
    var laneEvents: [(age: Double,lane: Int)] = []

}

extension GameModel {
    var skillsMode: Bool { skills.configuration != nil }
    var skillsCombined: Bool { skills.configuration?.combined == true }
    var skillsHandColorName: String { skills.assignedHand == 0 ? "BLUE" : "PINK" }
    func skillsLaneX(_ lane: Int) -> Double { lane == -1 ? leftX : lane == 1 ? rightX : center.x }
    func skillsLaneName(_ lane: Int) -> String { lane == -1 ? "LEFT" : lane == 1 ? "RIGHT" : "CENTER" }
    var skillsCursorX: Double {
        let x = Double(demoCursor?.x ?? 0.5)
        return center.x + (x-0.5)*3*(x < 0.5 ? center.x-leftX : rightX-center.x)
    }
    var imuResumeInstruction: String { "Return to center, then press Resume on Mac" }
    func startSkills(input: SkillsInput, combined: Bool) {
        startObstacles(demo:input == .cursor,imu:input == .imu)
        skills.configuration = SkillsConfiguration(input:input,combined:combined)
        feedback = "Establish your lanes; movement speeds will be learned during play."
    }
    func prepareSkillsStep(_ move: Move, reissued: Bool = false) {
        let source = laneAt(positionX), target = laneFor(move)
        skills.route = SkillsRoute(from:source,to:target)
        skills.movementRequired = source != target
        skills.referenceAtStart = skills.references[skills.route]
        skills.movement = SkillsMovement(origin:positionX,previous:(positionX,0))
        if skills.movementRequired { stepTravelBaseline = skills.references[skills.route] ?? stepTravelBaseline }
        skills.laneEvents = [(0,source)]
        skills.targetSpawnAge = nil; skills.contactAge = nil; skills.maintainedLane = nil
        skills.outcome = skillsCombined ? .pending : .notRequired
        if skillsCombined && !reissued {
            if skills.handBag.isEmpty { skills.handBag = [0,1].shuffled() }
            skills.assignedHand = skills.handBag.removeFirst()
        }
    }
    func observeSkillsMovement(age: Double) {
        guard let move = currentMove, age >= 0 else { return }
        if age <= stepDuration, age >= (skills.laneEvents.last?.age ?? 0) {
            if skills.laneEvents.last?.lane != lane { skills.laneEvents.append((age,lane)) }
        }
        skills.movement.observe(x:positionX,lane:lane,target:laneFor(move),age:age,tolerance:zoneRadius)
        if skillsCombined, armTarget == nil, skills.outcome == .pending,
           skills.movement.confirmedArrival != nil, lane == laneFor(move), age <= stepDuration {
            let shoulder = skills.assignedHand == 0 ? skills.leftShoulder : skills.rightShoulder
            let side = shoulder.x < shoulderMid.x ? -1.0 : 1.0
            armTargetRadius = max(0.04,min(0.075,torsoScale*0.2))
            armTarget = CGPoint(x:max(0.1,min(0.9,shoulder.x+side*shoulderSpan*0.3)),y:max(0.15,min(0.65,shoulderMid.y+torsoScale*0.3)))
            skills.targetSpawnAge = age; resetArmContact()
            feedback = "Match your \(skillsHandColorName) hand marker to the target; keep your lane."
        }
    }
    func receiveSkillsTouch(hand: Int, age: Double) {
        guard skillsCombined, active, reliable, !paused, !stepTrackingInterrupted,
              skills.outcome == .pending, let spawned = skills.targetSpawnAge,
              age >= spawned, age <= stepDuration, let move = currentMove else { return }
        let target = laneFor(move)
        let contactLane = skills.laneEvents.last(where: { $0.age <= age })?.lane
        let held = !skills.laneEvents.contains { $0.age >= spawned && $0.age <= age && $0.lane != target }
        skills.contactAge = age
        skills.outcome = hand != skills.assignedHand ? .wrongHand : contactLane == target ? .correct : .outsideLane
        skills.maintainedLane = skills.outcome == .correct && held
        feedback = skills.outcome.rawValue + (skills.outcome == .correct && !held ? " · Lane lost during reach" : "")
    }
    func recordSkillsObstacle(avoided: Bool, move: Move) {
        let arrived = skills.movement.confirmedArrival.map { $0 <= stepDuration } ?? false
        let travel = arrived ? skills.movement.duration : nil
        let eligible = skills.referenceAtStart != nil
        let agility = skills.movementRequired && eligible ? travel.map { min(1,skills.referenceAtStart!/max(0.001,$0)) } ?? 0 : 0
        if skills.movementRequired, let travel, travel.isFinite, travel > 0, skills.references[skills.route] == nil {
            skills.samples[skills.route,default:[]].append(travel)
            if skills.samples[skills.route]!.count == 3 {
                skills.references[skills.route] = skills.samples[skills.route]!.sorted()[1]
            }
        }
        let outcome: SkillsHandOutcome = skills.outcome == .pending ? .missed : skills.outcome
        let complete = avoided && (!skillsCombined || (outcome == .correct && skills.maintainedLane == true))
        let result = Attempt(move:move,success:complete,reaction:0,agility:agility,coordination:avoided ? 1 : 0,
                             travelSeconds:travel,movementRequired:skills.movementRequired,agilityEligible:eligible,handOutcome:outcome,
                             laneMaintained:skills.maintainedLane,collision:!avoided)
        appendAttempt(result)
        feedback = avoided ? "Dodged" : "Hit"
        if skillsCombined { feedback += " · " + outcome.rawValue; if outcome == .correct && skills.maintainedLane == false { feedback += " · Lane lost" } }
        if let travel { feedback += String(format:" · movement %.2fs",travel) }
    }
    func skillsComponents(_ items: [Attempt]) -> (accuracy: Double, control: Double, consistency: Double?) {
        let recent = Array(items.suffix(20))
        guard !recent.isEmpty else { return (0,0,nil) }
        let accuracy = recent.map { item in
            let dodge = item.collision == false ? 1.0 : 0
            return skillsCombined ? 0.5*dodge + (item.handOutcome == .correct ? 0.5 : 0) : dodge
        }.reduce(0,+)/Double(recent.count)
        let control = recent.filter { $0.handOutcome == .correct && $0.laneMaintained == true }.count
        func correct(_ item: Attempt) -> Bool {
            item.collision == false && (!skillsCombined || (item.handOutcome == .correct && item.laneMaintained == true))
        }
        let pairs = zip(recent,recent.dropFirst()).filter { correct($0.0) && correct($0.1) }.count
        return (accuracy,Double(control)/Double(recent.count),recent.count < 2 ? nil : Double(pairs)/Double(recent.count-1))
    }
}

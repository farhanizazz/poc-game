#if os(macOS)
import SwiftUI
import Combine
import Vision

private let mint = Color(red: 0.72, green: 1.0, blue: 0.40)
private let ink = Color(red: 0.012, green: 0.016, blue: 0.022)
private let mutedText = Color.white.opacity(0.82)
private let panelTint = Color.black.opacity(0.72)
private let panelBorder = Color.white.opacity(0.24)
private func handCueColor(_ hand: Int) -> Color { hand == 0 ? Color(red:0.24,green:0.67,blue:1) : Color(red:1,green:0.34,blue:0.66) }

struct ContentView: View {
    @StateObject private var game = GameModel()
    @StateObject private var tracker = BodyTracker()
    @StateObject private var imu = IMUReceiver()
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var demoPointer = DemoPointer()
    @State private var skillsInput: SkillsInput = .vision
    @State private var skillsCombined = false
    private var visionInstructionsBelow: Bool { !game.demo && !game.imuMode }
    private let timer = Timer.publish(every: 1.0/30, on: .main, in: .common).autoconnect()
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.76).background(.ultraThinMaterial).ignoresSafeArea()
                VStack(spacing: 18) {
                    header
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 14) {
                            stage.frame(maxHeight: .infinity)
                            if visionInstructionsBelow && game.active {
                                VStack(spacing:8) {
                                    cueCard
                                    feedbackBanner
                                }
                            }
                            footer
                        }
                        sidebar.frame(width: geometry.size.width > 950 ? 290 : 230)
                    }
                }.padding(24)
                if game.phase == .welcome { welcome }
            }
            .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            tracker.onPose = { if !game.imuMode { tracker.route($0,to:game) } }
            imu.onShuffle = { direction, start, end in game.receiveIMU(direction: direction, start: start, end: end) }
        }
        .onDisappear { imu.stop(); tracker.capture.stop() }
        .onReceive(timer) { _ in
            if game.demo && game.phase != .welcome {
                let cursor = demoPointer.sample()
                game.updateDemoCursor(position:cursor.position,insideWindow:cursor.insideWindow)
            }
            if game.imuMode {
                if game.tracking && !imu.ready { game.paused = true; game.interruptShuffle() }
                game.tracking = imu.ready
                imu.show(game.paused ? game.imuResumeInstruction : game.phase == .calibration ? game.calibrationTitle : game.currentMove.map { $0.rawValue + " · " + game.timingLabel } ?? game.feedback)
            }
            if !game.imuMode && !game.demo && Date().timeIntervalSince(tracker.lastFrame) > 0.6 { game.tracking = false; game.hold = 0 }
            if game.demo && game.handMode && game.phase == .calibration {
                game.calibrateHands(guardOK:true,left:CGPoint(x:0,y:0.5),right:CGPoint(x:0,y:0.5),dt:1/30)
            }
            if game.demo && !game.handMode && game.phase == .calibration { game.calibrate(position: CGPoint(x: game.demoTargetX,y: 0.5), height: 0.5, dt: 1/30) }
            game.tick()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.paused = true; tracker.capture.stop() }
            else if !game.imuMode && !game.demo && game.phase != .welcome { tracker.start(hands:game.handMode) }
        }
    }
    private var header: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "figure.run").font(.title).foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.skillsMode ? "MOVEMENT / SKILLS" : game.obstacleMode ? "OBSTACLE / DODGE" : "SHUFFLE / RUN").font(.system(.title3, design: .monospaced, weight: .heavy))
                    Text("A BODY-CONTROLLED ENDLESS RUNNER").font(.system(size: 10, design: .monospaced)).foregroundStyle(mutedText)
                }
            }
            Spacer()
            Text(game.handMode ? (game.demo ? "SLICE + PUNCH · DEMO" : "SLICE + PUNCH · VISION") : game.imuMode ? "IPHONE IMU · ESTIMATED ARRIVAL" : game.demo ? "CURSOR DEMO" : "APPLE VISION · ON DEVICE").font(.system(size: 11, design: .monospaced)).foregroundStyle(mint)
            Button(game.paused ? "Resume" : "Pause") { if game.paused && game.imuMode { game.centerIMU() } else { game.paused.toggle() } }.buttonStyle(.bordered)
            Button("Restart") { tracker.capture.stop(); imu.stop(); game.phase = .welcome; game.paused = false }.buttonStyle(.bordered)
        }.padding(12)
            .background(panelTint,in:RoundedRectangle(cornerRadius:16))
            .overlay { RoundedRectangle(cornerRadius:16).stroke(panelBorder,lineWidth:1) }
    }
    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(panelTint)
            if game.phase == .calibration { if game.handMode { handCalibration } else if game.imuMode { imuCalibration } else { calibration } }
            else {
                if game.handMode { handArena } else if game.currentMove == .armTouch { armTargetArena } else { cameraSurface { ZStack { runner; if game.skillsCombined { skillsTargetOverlay } } } }
                if game.demo && !game.handMode && game.currentMove != .armTouch {
                    HStack(spacing:0) {
                        ForEach(["LEFT","CENTER","RIGHT"],id:\.self) { label in
                            VStack { Spacer(); Text(label).font(.system(size:10,weight:.bold,design:.monospaced)).padding(.bottom,10) }
                                .frame(maxWidth:.infinity,maxHeight:.infinity)
                                .border(mint.opacity(0.35),width:1)
                        }
                    }.allowsHitTesting(false)
                }
                VStack {
                    HStack {
                        Label(game.phase == .boss ? "BOSS ARENA" : "ZONE \(String(format: "%02d", game.zone)) · TEST TRACK", systemImage: game.phase == .boss ? "flame" : "location")
                        Spacer()
                        Text(game.phase == .boss ? "\(max(0, 30 - Int(game.bossTime)))s LEFT / \(game.score) PTS" : "\(Int(game.elapsed))s / \(game.score) PTS")
                    }.font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(mint)
                        .padding(10).background(panelTint,in:RoundedRectangle(cornerRadius:10))
                    Spacer()
                    if !visionInstructionsBelow {
                        if game.active { cueCard }
                        Spacer().frame(height: game.currentMove == .armTouch ? 28 : 140)
                        feedbackBanner
                    }
                }.padding(24)
            }
            if game.phase == .recovery || game.phase == .result { arenaOverlay }
            if game.paused || (game.demo && game.demoPointerOutside) || (game.active && !game.reliable) {
                Color.black.opacity(0.88).clipShape(RoundedRectangle(cornerRadius: 24))
                VStack(spacing: 12) {
                    Image(systemName: game.paused ? "pause.circle" : "figure.dashed").font(.largeTitle).foregroundStyle(mint)
                    Text(game.demoPointerOutside && game.demo ? "Cursor outside window" : game.imuMode ? "Return to center" : game.paused ? "Take a breather" : "Step back into view").font(.title2.bold())
                    Text(game.demoPointerOutside && game.demo ? "Move your cursor back into this window to continue. A manual pause still needs Resume." : game.imuMode ? game.imuResumeInstruction + ". " + imu.status : game.paused ? "Resume when you're ready." : game.skillsCombined ? "Keep shoulders, hips, and both wrists visible. Interrupted tasks restart without a miss." : game.handMode ? "Keep shoulders, hips, elbows and both hands visible. Open hands for slices; fists for punches." : "Keep shoulders, hips, and at least one wrist visible for arm targets. Knees and feet can stay out of frame. The clock and scoring are paused.").font(.caption).foregroundStyle(mutedText)
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius:24))
            .overlay { RoundedRectangle(cornerRadius:24).stroke(panelBorder,lineWidth:1) }
            .background(DemoPointerSurface(pointer:demoPointer))
    }
    private var runner: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let horizon = size.height * 0.30
                let cx = size.width/2
                let ground = size.height * 0.91
                let time = game.elapsed
                var floor = Path(); floor.move(to: CGPoint(x: cx-35,y:horizon)); floor.addLine(to: CGPoint(x:cx+35,y:horizon)); floor.addLine(to: CGPoint(x:size.width*0.95,y:size.height)); floor.addLine(to: CGPoint(x:size.width*0.05,y:size.height)); floor.closeSubpath()
                context.fill(floor, with: .color(.white.opacity(0.075)))
                for i in 0...3 {
                    let f = Double(i)/3
                    var line = Path(); line.move(to: CGPoint(x:cx-35+70*f,y:horizon)); line.addLine(to: CGPoint(x:size.width*(0.05+0.9*f),y:size.height))
                    context.stroke(line,with:.color(mint.opacity(0.48)),lineWidth:1)
                }
                for i in 0..<14 {
                    let p = (Double(i)/14 + time * 0.16).truncatingRemainder(dividingBy: 1)
                    let depth = p*p
                    let y = horizon + (size.height-horizon)*depth
                    let width = 35 + (size.width*0.45-35)*depth
                    var line = Path(); line.move(to: CGPoint(x:cx-width,y:y)); line.addLine(to: CGPoint(x:cx+width,y:y))
                    context.stroke(line,with:.color(mint.opacity(0.25 + depth*0.20)),lineWidth:1)
                }
                // Placeholder track pylons, built only from primitives.
                for side in [-1.0,1.0] {
                    for i in 0..<5 {
                        let p = (Double(i)/5 + time*0.07).truncatingRemainder(dividingBy:1)
                        let y = horizon + (size.height-horizon)*p*p
                        let w = 16 + p*50
                        let x = cx + side*(55+p*p*size.width*0.49)
                        context.fill(Path(roundedRect:CGRect(x:x-w/2,y:y-w*1.7,width:w,height:w*1.7),cornerRadius:3),with:.color(Color.white.opacity(0.12)))
                        context.fill(Path(CGRect(x:x-w/2,y:y-w*1.7,width:w,height:5)),with:.color(mint.opacity(0.25)))
                    }
                }
                if game.phase == .boss {
                    let rect = CGRect(x:cx-55,y:horizon-30,width:110,height:90)
                    context.fill(Path(roundedRect:rect,cornerRadius:12),with:.color(.orange.opacity(0.7)))
                    context.draw(Text("BOSS").font(.system(.title3,design:.monospaced,weight:.black)),at:CGPoint(x:cx,y:horizon+15))
                }
                // The obstacle reaches the player at the same ideal arrival used by scoring.
                if game.active, game.obstacleMode, !game.cue.isEmpty {
                    for index in (game.cueIndex..<game.cue.count).reversed() {
                        let untilPass = game.obstaclePassTimes[index]-game.obstaclePassTimes[game.cueIndex]+game.remaining
                        if untilPass <= game.obstacleLookAhead {
                            let progress = min(1.15,max(0,1-untilPass/game.obstacleLookAhead))
                            let depth = 0.15+0.85*progress*progress
                            let y = horizon+(ground-horizon)*depth
                            let width = size.width*0.20*depth
                            let safeLane = game.laneFor(game.cue[index])
                            for lane in -1...1 where lane != safeLane {
                                let x = cx+Double(lane)*size.width*0.25*depth
                                let rect = CGRect(x:x-width/2,y:y-28,width:width,height:28)
                                context.fill(Path(roundedRect:rect,cornerRadius:4),with:.color(.orange.opacity(0.22)))
                                context.stroke(Path(roundedRect:rect,cornerRadius:4),with:.color(.orange),lineWidth:3)
                            }
                            if index == game.cueIndex {
                                let x = cx+Double(safeLane)*size.width*0.25*depth
                                context.draw(Text("CLEAR LANE").font(.system(size:10,weight:.bold,design:.monospaced)).foregroundColor(mint),at:CGPoint(x:x,y:y-40))
                            }
                        }
                    }
                } else if game.active, let move = game.currentMove, move.directional {
                    let progress = min(1.15, max(0, game.cueAge / game.stepBeat))
                    let depth = 0.15 + 0.85 * progress * progress
                    let y = horizon + (ground - horizon) * depth
                    let width = (size.width*0.20) * depth
                    let color: Color = game.timingOpen ? mint : .orange
                    for lane in -1...1 where lane != game.laneFor(move) {
                        let obstacleX = cx + Double(lane)*size.width*0.25*depth
                        let obstacle = CGRect(x:obstacleX-width/2,y:y-26,width:width,height:26)
                        context.stroke(Path(roundedRect:obstacle,cornerRadius:4),with:.color(color.opacity(0.8)),lineWidth:3)
                    }
                    context.draw(Text(game.cueAge < game.stepWindowOpen ? "WAIT" : "MOVE NOW")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(color), at: CGPoint(x: cx, y: y-40))
                }
                let x = cx + Double(game.lane)*size.width*0.25
                let h = 65.0
                context.fill(Path(ellipseIn:CGRect(x:x-30,y:ground+5,width:60,height:10)),with:.color(.black.opacity(0.6)))
                context.fill(Path(roundedRect:CGRect(x:x-20,y:ground-h,width:40,height:h),cornerRadius:10),with:.color(mint))
                context.fill(Path(ellipseIn:CGRect(x:x-12,y:ground-h-26,width:24,height:24)),with:.color(mint))

            }
        }
    }
    private var armTargetArena: some View { cameraSurface { armTargetOverlay } }
    private var armTargetOverlay: some View {
        GeometryReader { geo in
            ZStack {
                if !game.demo { skeleton.opacity(0.45) }
                if let target = game.armTarget {
                    let width = game.armTargetRadius*2*geo.size.width
                    let height = game.armTargetRadius*2*geo.size.height
                    let approach = 1 + max(0,(game.stepBeat-game.cueAge)/game.stepBeat)*2
                    Ellipse().stroke(.white.opacity(0.3),lineWidth:2)
                        .frame(width:width*approach,height:height*approach)
                        .position(x:target.x*geo.size.width,y:target.y*geo.size.height)
                    Button { if game.demo { game.input(.armTouch) } } label: {
                        ZStack {
                            Ellipse().fill(game.timingOpen ? mint.opacity(0.3) : .orange.opacity(0.15))
                            Ellipse().stroke(game.timingOpen ? mint : .orange,lineWidth:4)
                            Image(systemName:"hand.point.up.left.fill").foregroundStyle(.white).font(.title2)
                        }.frame(width:width,height:height)
                    }.buttonStyle(.plain).allowsHitTesting(game.demo)
                        .position(x:target.x*geo.size.width,y:target.y*geo.size.height)
                    Text(game.demo ? "HOVER INTO THE TARGET ON THE BEAT" : "TOUCH WITH EITHER HAND")
                        .font(.system(size:10,weight:.bold,design:.monospaced)).foregroundStyle(mint)
                        .position(x:target.x*geo.size.width,y:(target.y+game.armTargetRadius+0.04)*geo.size.height)
                }
                if game.demo, let cursor = game.demoCursor,
                   (0...1).contains(cursor.x), (0...1).contains(cursor.y) {
                    Circle().fill(.cyan).frame(width:18,height:18)
                        .overlay(Circle().stroke(.white,lineWidth:2)).allowsHitTesting(false)
                        .position(x:cursor.x*geo.size.width,y:cursor.y*geo.size.height)
                }
                if !game.demo {
                    ForEach([VNHumanBodyPoseObservation.JointName.leftWrist,.rightWrist],id:\.rawValue) { joint in
                        if let wrist = tracker.point(joint) {
                            Circle().fill(handCueColor(joint == .leftWrist ? 0 : 1)).frame(width:18,height:18)
                                .overlay(Circle().stroke(.white,lineWidth:2))
                                .position(x:wrist.x*geo.size.width,y:wrist.y*geo.size.height)
                        }
                    }
                }
            }
        }
    }
    private var feedbackBanner: some View {
        Text(game.feedback).font(.system(size:13,weight:.semibold,design:.monospaced)).foregroundStyle(.white)
            .padding(10).frame(maxWidth:.infinity).background(panelTint,in:RoundedRectangle(cornerRadius:12))
    }
    private var cueCard: some View {
        VStack(spacing: 12) {
            if !game.cue.isEmpty {
                if game.currentMove != .armTouch {
                    ScrollView(.horizontal,showsIndicators:false) { HStack(spacing: game.obstacleMode || visionInstructionsBelow ? 8 : 16) {
                        ForEach(Array(game.cue.enumerated()), id: \.offset) { index, move in
                            VStack(spacing: 7) {
                                Image(systemName: move.icon).font(.system(size: game.obstacleMode || visionInstructionsBelow ? 22 : 32, weight: .bold))
                                Text(move.rawValue).font(.system(size: game.obstacleMode || visionInstructionsBelow ? 9 : 12, weight: .heavy, design: .monospaced))
                            }.foregroundStyle(index == game.cueIndex ? ink : .white.opacity(0.9))
                            .padding(game.obstacleMode || visionInstructionsBelow ? 10 : 18).background(index == game.cueIndex ? mint : Color.black.opacity(0.75),in:RoundedRectangle(cornerRadius:16))
                            .overlay { RoundedRectangle(cornerRadius:16).stroke(index == game.cueIndex ? mint : panelBorder,lineWidth:1) }
                        }
                    } }.fixedSize(horizontal:false,vertical:true)
                }
                if game.obstacleMode {
                    Text("OBSTACLE \(game.cueIndex+1) / \(game.cue.count) · EARLY MOVEMENT ALLOWED")
                        .font(.system(size:10,weight:.bold,design:.monospaced)).foregroundStyle(mint)
                } else {
                    ProgressView(value: max(0,game.remaining), total: game.stepDuration).tint(game.timingOpen ? .orange : mint).frame(maxWidth: 280)
                }
                if game.usesBeat {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.3))
                            Capsule().fill(.orange.opacity(0.6))
                                .frame(width: geo.size.width * (2*game.stepHalfWindow/game.stepDuration))
                                .offset(x: geo.size.width * (game.stepWindowOpen/game.stepDuration))
                            Rectangle().fill(mint).frame(width:2)
                                .offset(x:geo.size.width*game.stepBeat/game.stepDuration)
                            Circle().fill(.white).frame(width: 10, height: 10)
                                .offset(x: max(0, min(geo.size.width-10, geo.size.width*game.cueAge/game.stepDuration)))
                        }
                    }.frame(width: 280, height: 10)
                }
                if !game.handMode && game.currentMove != .armTouch {
                    Text(game.imuMode ? "POSITION: \(game.positionLabel) · estimated" : "POSITION: \(game.positionLabel) · cross halfway to change lanes")
                        .font(.system(size:9,design:.monospaced)).foregroundStyle(mint)
                }
                if game.currentMove == .armTouch {
                    Text("PERFECT ≤100ms · GREAT ≤200ms · GOOD in window · BAD outside")
                        .font(.system(size:9,design:.monospaced)).foregroundStyle(mint)
                }
                Text(game.timingLabel)
                    .font(.system(size:game.currentMove?.directional == true ? 14 : 9,weight:.bold,design:.monospaced))
                    .foregroundStyle(game.currentMove?.directional == true && game.timingOpen ? mint : mutedText)
            } else { Text("FIND YOUR RHYTHM").font(.system(.title3,design:.monospaced,weight:.bold)).foregroundStyle(mint) }
        }.padding(14).background(panelTint,in:RoundedRectangle(cornerRadius:18))
    }
    private var handArena: some View { cameraSurface { handArenaOverlay } }
    private var handArenaOverlay: some View {
        GeometryReader { geo in
            ZStack {
                // Five placeholder targets, matching the player's mirrored screen directions.
                ForEach(Array(Move.handMoves.enumerated()),id: \.offset) { index, move in
                    let positions: [CGPoint] = [CGPoint(x:0.36,y:0.23),CGPoint(x:0.36,y:0.75),CGPoint(x:0.63,y:0.23),CGPoint(x:0.16,y:0.5),CGPoint(x:0.85,y:0.5)]
                    let active = game.currentMove == move
                    VStack(spacing:5) {
                        Image(systemName:move.icon).font(.system(size:32,weight:.bold))
                        Text(move.rawValue).font(.system(size:10,weight:.bold,design:.monospaced))
                        Text(index < 2 ? "OPEN HAND" : "FIST").font(.system(size:8,design:.monospaced))
                    }.foregroundStyle(active ? ink : .white.opacity(0.85))
                        .padding(18).background(active ? (index < 2 ? mint : .cyan) : Color.black.opacity(0.72),in:RoundedRectangle(cornerRadius:index < 2 ? 4 : 40))
                        .position(x:geo.size.width*positions[index].x,y:geo.size.height*positions[index].y)
                }
                if !game.demo { skeleton.opacity(0.25).allowsHitTesting(false) }
            }
        }
    }
    private var handCalibration: some View {
        VStack(spacing:18) {
            Text("SLICE + PUNCH / HAND CALIBRATION").font(.system(.caption,design:.monospaced)).foregroundStyle(.cyan)
            Text(game.calibrationTitle).font(.title.bold())
            Text("Keep shoulders, hips, elbows and both hands visible. Hold your hands at chest height, near your shoulders.")
                .font(.callout).foregroundStyle(mutedText).multilineTextAlignment(.center)
            if game.demo {
                Image(systemName:game.calibrationStep == 1 ? "hand.raised.fill" : "hand.raised.fingers.spread.fill").font(.system(size:90)).foregroundStyle(.cyan)
            } else { cameraSurface { skeleton }.frame(maxHeight:.infinity) }
            ProgressView(value:game.hold,total:0.8).tint(.cyan).frame(maxWidth:300)
            Text("STEP \(min(3,game.calibrationStep+1)) OF 3 · Hold for 0.8s").font(.caption)
            if !game.demo { Text(game.handInstruction).font(.system(.caption,design:.monospaced)).foregroundStyle(mutedText) }
            Text(game.demo ? "Simulated calibration. W/S slice; I/J/L punch." : game.tracking ? "Hands found" : "Waiting for both hands and torso").font(.caption).foregroundStyle(.cyan)
            Text("Either hand can strike. Open palm for slices; closed fist with arm extension for punches. Return to guard between actions.")
                .font(.caption).foregroundStyle(mutedText).multilineTextAlignment(.center)
            if let error = tracker.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(26)
    }
    private var imuCalibration: some View {
        VStack(spacing: 20) {
            Text("IPHONE IMU / SHUFFLE CALIBRATION").foregroundStyle(mint)
            Text(imu.address).font(.title2.monospaced()).textSelection(.enabled)
            Text("Pairing code: " + imu.code).font(.title.monospaced())
            Text(imu.status).foregroundStyle(mutedText)
            Text(game.calibrationTitle).font(.title.bold())
            Text("Secure iPhone upright at your waist, screen outward. Face the Mac.\nFollow center → left → right → center, stopping briefly in each position.")
                .multilineTextAlignment(.center)
            if game.calibrationStep == 0 {
                Button("I'm standing in the center") { game.centerIMU() }.disabled(!imu.ready)
                    .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(ink)
            }
            Text("Step \(min(4,game.calibrationStep+1)) of 4 · " + game.feedback).font(.caption)
            Text("Use the same Wi-Fi. Install this project on iPhone to open the companion.\nArrival is inferred from stopping, not measured floor position. IMU mode uses shuffle cues.")
                .font(.caption).foregroundStyle(mutedText).multilineTextAlignment(.center)
        }.padding(28)
    }
    private var calibration: some View {
        VStack(spacing: 16) {
            Text("01 / SET YOUR PLAY SPACE").font(.system(size:11,design:.monospaced)).foregroundStyle(mint)
            Text(game.calibrationTitle).font(.title.bold())
            Text(game.demo ? "Hover in the left, center, or right third • hold for 0.8s" : "Face the camera • show your torso and hips • hold each box for 0.8s").font(.caption).foregroundStyle(mutedText)
            cameraSurface {
                GeometryReader { geo in
                    ZStack {
                        ForEach(0..<3) { index in
                            let target = game.calibrationStep == 1 ? 0 : game.calibrationStep == 2 ? 2 : 1
                            RoundedRectangle(cornerRadius:16).stroke(index == target ? mint : .white.opacity(0.45),style:StrokeStyle(lineWidth:2,dash:[8]))
                                .background(index == target ? mint.opacity(0.06) : .clear,in:RoundedRectangle(cornerRadius:16))
                                .frame(width:geo.size.width*0.21,height:geo.size.height*0.85)
                                .overlay(alignment:.bottom) { Text(["LEFT","CENTER","RIGHT"][index]).font(.system(size:11,design:.monospaced)).padding(12) }
                                .position(x:geo.size.width*[0.27,0.5,0.73][index],y:geo.size.height/2)
                        }
                        if game.demo {
                            Image(systemName:"figure.stand").font(.system(size:85)).foregroundStyle(mint).position(x:geo.size.width*game.demoTargetX,y:geo.size.height*0.5)
                        } else { skeleton }
                    }
                }
            }
            ProgressView(value:game.hold,total:0.8).tint(mint).frame(maxWidth:300)
            Text("STEP \(min(4,game.calibrationStep+1)) OF 4 · \(game.demo ? "SIMULATED BODY" : game.tracking ? "BODY FOUND" : "WAITING FOR SHOULDERS + HIPS")").font(.system(size:10,design:.monospaced)).foregroundStyle(mint)
            if game.demo { Text("Hover LEFT · CENTER · RIGHT to match the highlighted box").font(.caption).foregroundStyle(mint) }
            if let error = tracker.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(24)
    }
    @ViewBuilder private func cameraSurface<Overlay: View>(@ViewBuilder overlay: @escaping () -> Overlay) -> some View {
        if game.demo || game.imuMode {
            overlay()
        } else {
            GeometryReader { geo in
                let aspect = tracker.previewImage.map { Double($0.width)/Double($0.height) } ?? 4.0/3.0
                let width = min(geo.size.width,geo.size.height*aspect)
                let height = width/aspect
                ZStack {
                    if let image = tracker.previewImage {
                        Image(decorative:image,scale:1).resizable()
                            .frame(width:width,height:height).allowsHitTesting(false)
                    } else { Color.black }
                    Color.black.opacity(0.48).allowsHitTesting(false)
                    overlay()
                }.frame(width:width,height:height).clipped()
                    .position(x:geo.size.width/2,y:geo.size.height/2)
            }
        }
    }
    private var skeleton: some View {
        Canvas { context,size in
            let pairs: [(VNHumanBodyPoseObservation.JointName,VNHumanBodyPoseObservation.JointName)] = [(.leftShoulder,.rightShoulder),(.leftShoulder,.leftElbow),(.leftElbow,.leftWrist),(.rightShoulder,.rightElbow),(.rightElbow,.rightWrist),(.leftShoulder,.leftHip),(.rightShoulder,.rightHip),(.leftHip,.rightHip)]
            func convert(_ p:CGPoint) -> CGPoint { CGPoint(x:p.x*size.width,y:p.y*size.height) }
            for (a,b) in pairs { if let start = tracker.point(a),let end = tracker.point(b) { var path = Path(); path.move(to:convert(start)); path.addLine(to:convert(end)); context.stroke(path,with:.color(mint),style:StrokeStyle(lineWidth:3,lineCap:.round)) } }
            for (joint,p) in tracker.points {
                let q = convert(p)
                let left = joint == VNHumanBodyPoseObservation.JointName.leftWrist.rawValue.rawValue
                let right = joint == VNHumanBodyPoseObservation.JointName.rightWrist.rawValue.rawValue
                let radius = left || right ? 9.0 : 4.0
                let dot = Path(ellipseIn:CGRect(x:q.x-radius,y:q.y-radius,width:radius*2,height:radius*2))
                context.fill(dot,with:.color(left ? handCueColor(0) : right ? handCueColor(1) : .white))
                if left || right { context.stroke(dot,with:.color(.white),lineWidth:2) }
            }
        }
    }
    private var sidebar: some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            let values = game.skillsMode && game.phase == .boss ? game.rates(game.bossHistory) : game.metrics
            if !game.demo && !game.imuMode {
                HStack(spacing:12) {
                    Label { Text("BLUE HAND") } icon: { Circle().fill(handCueColor(0)).frame(width:12,height:12) }
                    Label { Text("PINK HAND") } icon: { Circle().fill(handCueColor(1)).frame(width:12,height:12) }
                }.font(.system(size:9,weight:.bold,design:.monospaced))
            }
            Text("RUN TELEMETRY").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(mutedText)
            HStack(alignment:.firstTextBaseline) { Text(String(format:"%02d",game.combo)).font(.system(size: 54, weight: .bold, design: .monospaced)); Text("COMBO").font(.caption).foregroundStyle(mint) }
            Divider()
            metric("DIFFICULTY",value:game.difficulty)
            if game.skillsMode && !(game.phase == .boss ? game.bossHistory : game.history).contains(where: { $0.movementRequired && $0.agilityEligible }) {
                Text("AGILITY · Learning your movement speeds").font(.caption).foregroundStyle(.cyan)
            } else {
                metric(game.skillsMode ? "AGILITY · MOVEMENT" : game.handMode ? "STRIKE SPEED" : "AGILITY · RESPONSE",value:values.0)
            }
            metric(game.skillsCombined ? "COORDINATION" : game.skillsMode ? "DODGE ACCURACY" : game.obstacleMode ? "OBSTACLES AVOIDED" : game.handMode ? "STRIKE TIMING" : "COORDINATION · TIMING",value:values.1)
            if game.skillsMode {
                let attempts = game.phase == .boss ? game.bossHistory : game.history
                let components = game.skillsComponents(attempts)
                Text("Route baselines: \(game.skills.references.count)/6 ready · \(game.skills.samples.values.reduce(0) { $0+$1.count })/18 samples")
                    .font(.caption).foregroundStyle(game.skills.references.count == 6 ? mint : .cyan)
                if game.skillsCombined {
                    metric("TASK ACCURACY · 50%",value:components.accuracy)
                    metric("COMBINED CONTROL · 30%",value:components.control)
                }
                if let consistency = components.consistency { metric(game.skillsCombined ? "CONSISTENCY · 20%" : "CONSISTENCY",value:consistency) }
                else { Text("Consistency: collecting samples").font(.caption).foregroundStyle(mutedText) }
                if let duration = attempts.last(where: { $0.travelSeconds != nil })?.travelSeconds {
                    Text(String(format:"Last movement: %.2fs",duration)).font(.caption.monospaced())
                }
            }
            if game.handMode { metric("REACTION",value:values.2) }
            Divider()
            Text("ROAD TO THE BOSS").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(mint)
            if game.skillsMode { gate("6 route baselines learned",game.skills.references.count == 6) }
            gate("60s active practice",game.zoneTime >= 60)
            gate(game.skillsMode ? "80% movement agility" : game.handMode ? "80% strike speed" : "80% shuffle response",game.metrics.0 >= 0.8)
            gate(game.skillsCombined ? "85% coordination" : game.obstacleMode ? "85% obstacles avoided" : "85% coordination",game.metrics.1 >= 0.85)
            consecutiveGroupsSetting
            if game.requireConsecutiveGroups { gate("Passed groups (\(min(2,game.windows))/2)",game.windows >= 2) }
            gate("Tracking + ready to move",game.reliable && !game.paused)
            Spacer(minLength:0)
            if !game.demo && !game.imuMode { cameraSurface { skeleton }.frame(height:100).background(panelTint,in:RoundedRectangle(cornerRadius:12)) }
            Text(game.imuMode ? "IPHONE IMU\n" + imu.status : game.handMode && game.demo ? "HAND DEMO\nW/S slice · I/J/L punch" : game.demo ? "CURSOR DEMO\nHover left / center / right.\n" + (game.demoCursorSpeed.map { String(format:"Last travel: %.2f lanes/s\n",$0) } ?? "") + "Leave the window to pause." : "VISION INPUT\nNo video is saved or uploaded.").font(.system(size:10,design:.monospaced)).foregroundStyle(mutedText)
            Text("PROTOTYPE / PLACEHOLDER ASSETS").font(.system(size:8,design:.monospaced)).foregroundStyle(mutedText)
        }.padding(20) }.background(panelTint,in:RoundedRectangle(cornerRadius:24))
            .overlay { RoundedRectangle(cornerRadius:24).stroke(panelBorder,lineWidth:1) }
    }
    private func metric(_ label:String,value:Double) -> some View {
        VStack(spacing:7) { HStack { Text(label); Spacer(); Text("\(Int(value*100))%") }.font(.system(size:10,design:.monospaced)); ProgressView(value:value).tint(mint) }
    }
    private func gate(_ title:String,_ passed:Bool) -> some View { Label(title,systemImage:passed ? "checkmark.circle.fill" : "circle").font(.system(size:11)).foregroundStyle(passed ? mint : mutedText) }
    private func shortcut(for move: Move) -> KeyEquivalent {
        switch move {
        case .left: .leftArrow
        case .right: .rightArrow
        case .center: " "
        case .armTouch: "t"
        case .sliceUp: "w"
        case .sliceDown: "s"
        case .punchUp: "i"
        case .punchLeft: "j"
        case .punchRight: "l"
        }
    }
    private var footer: some View {
        HStack {
            if game.demo && !game.handMode {
                Text(game.obstacleMode ? "HOVER: LEFT | CENTER | RIGHT · Stay in the clear lane as each obstacle passes" : "HOVER: LEFT  |  CENTER  |  RIGHT · Hover arm targets on the beat").font(.system(size:10,design:.monospaced)).foregroundStyle(mint)
            } else if game.demo {
                ForEach(Move.handMoves,id:\.rawValue) { move in Button { game.input(move) } label: { Label(move.rawValue,systemImage:move.icon).font(.system(size: 10, weight: .bold, design: .monospaced)).frame(maxWidth:.infinity).padding(.vertical,10) }.buttonStyle(.bordered).tint(mint).keyboardShortcut(shortcut(for: move), modifiers: []).disabled(!game.active || game.paused) }
            } else if game.handMode { Text("OPEN HAND · SLICE ↑ ↓     FIST · PUNCH ↑ ← →     RETURN TO GUARD").font(.system(size:11,design:.monospaced)).foregroundStyle(mint) } else if game.imuMode { Text("← LEFT    CENTER    RIGHT → · Arrival estimated from stopping").font(.caption).foregroundStyle(mint) } else { Text(game.skillsCombined ? "SHUFFLE · HOLD YOUR LANE · MATCH HAND COLOR TO TARGET" : game.obstacleMode ? "← SHUFFLE → · AVOID THE ORANGE BLOCKS · EARLY MOVEMENT ALLOWED" : "← SHUFFLE →     TOUCH ARM TARGETS ON THE BEAT").font(.system(size:11,design:.monospaced)).foregroundStyle(mutedText); Spacer(); Text(game.skillsCombined ? "Shoulders + hips + both wrists" : game.obstacleMode ? "Shoulders + hips in frame" : "Shoulders + hips + hands in frame").font(.caption).foregroundStyle(mint) }
        }
    }
    private var arenaTitle: String {
        if game.phase == .recovery { return "SENTINEL / 01" }
        return game.won ? "ZONE MASTERED" : "KEEP PRACTICING"
    }
    private var arenaMessage: String {
        if game.phase == .recovery { return "A 30-second sequence challenge. Breathe and reset." }
        return game.won ? "The next track is waiting. Higher complexity, same rhythm." : "Return to the run, rebuild consistency, and retry."
    }
    private var arenaOverlay: some View {
        ZStack {
            Color.black.opacity(0.90)
            VStack(spacing:20) {
                Image(systemName: "flame").font(.system(size:60)).foregroundStyle(mint)
                Text(arenaTitle).font(.system(.largeTitle, design:.monospaced, weight:.black))
                Text(arenaMessage).foregroundStyle(mutedText)
                arenaActions
            }.padding(30)
        }.clipShape(RoundedRectangle(cornerRadius:24))
    }
    @ViewBuilder private var arenaActions: some View {
        if game.phase == .recovery {
            Text("Recovery: \(Int(ceil(game.rest)))s").font(.caption)
            Button("I'm ready — enter arena") { game.enterBoss() }
                .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(ink)
                .disabled(game.rest > 0 || !game.reliable)
        } else {
            Text(bossSummary).font(.system(.caption,design:.monospaced)).foregroundStyle(mint)
            Button(game.won ? "Run the next zone" : "Back to practice") { game.continueRun() }
                .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(ink)
        }
    }
    private var bossSummary: String {
        let (a,c,_) = game.rates(game.bossHistory)
        let score = Int(game.performance(game.bossHistory)*100)
        return game.skillsMode ? "BOSS SCORE \(score)% · MOVEMENT \(Int(a*100))% · \(game.skillsCombined ? "COORDINATION" : "DODGE") \(Int(c*100))%" : game.obstacleMode ? "BOSS SCORE \(score)% · RESPONSE \(Int(a*100))% · AVOIDED \(Int(c*100))%" : "BOSS SCORE \(score)% · A \(Int(a*100))% · C \(Int(c*100))%"
    }
    private var consecutiveGroupsSetting: some View {
        VStack(alignment:.leading,spacing:6) {
            Toggle("Require 2 consecutive groups",isOn:$game.requireConsecutiveGroups)
                .toggleStyle(.switch).tint(mint).font(.caption)
            Text(game.requireConsecutiveGroups ? "Boss entry needs two evaluation groups passed in a row." : "Groups are optional. Practice time, skill scores, and tracking still apply.")
                .font(.system(size:10,design:.monospaced)).foregroundStyle(mutedText)
        }
    }
    private var skillsSetup: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("MOVEMENT SKILLS").font(.headline).foregroundStyle(.cyan)
            Picker("Input",selection:$skillsInput) {
                ForEach(SkillsInput.allCases,id:\.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth:600)
            Picker("Tasks",selection:$skillsCombined) {
                Text("Shuffle only").tag(false)
                Text("Shuffle + hand targets").tag(true).disabled(skillsInput != .vision)
            }.pickerStyle(.radioGroup)
            .onChange(of:skillsInput) { _, input in if input != .vision { skillsCombined = false } }
            Text(skillsInput == .vision ? "Dodge obstacles immediately after lane setup; movement speeds are learned during play. Combined tasks need both wrists visible." : "Combined tasks require Vision. This input measures simulated or estimated shuffle movement only.")
                .font(.caption).foregroundStyle(mutedText)
            Button("Start Movement Skills") {
                imu.stop(); tracker.capture.stop()
                game.startSkills(input:skillsInput,combined:skillsCombined)
                if skillsInput == .vision { tracker.start() }
                else if skillsInput == .imu { imu.start() }
            }.buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(ink)
        }.padding(16).background(panelTint,in:RoundedRectangle(cornerRadius:14))
            .overlay { RoundedRectangle(cornerRadius:14).stroke(panelBorder,lineWidth:1) }
    }
    private var skillsTargetOverlay: some View {
        GeometryReader { geo in
            ZStack {
                skeleton.opacity(0.45)
                if let target = game.armTarget {
                    Ellipse().fill(handCueColor(game.skills.assignedHand).opacity(0.35))
                        .overlay { Ellipse().stroke(handCueColor(game.skills.assignedHand),lineWidth:4) }
                        .frame(width:game.armTargetRadius*2*geo.size.width,height:game.armTargetRadius*2*geo.size.height)
                        .overlay { VStack(spacing:3) {
                            Image(systemName:game.skills.outcome == .pending ? "hand.raised.fill" : game.skills.outcome == .correct ? "checkmark" : "xmark")
                            Text(game.skillsHandColorName).font(.system(size:9,weight:.bold))
                        }.foregroundStyle(.white) }
                        .position(x:target.x*geo.size.width,y:target.y*geo.size.height)
                }
                ForEach([VNHumanBodyPoseObservation.JointName.leftWrist,.rightWrist],id:\.rawValue) { joint in
                    if let point = tracker.point(joint) {
                        Circle().fill(handCueColor(joint == .leftWrist ? 0 : 1)).frame(width:18,height:18)
                            .overlay(Circle().stroke(.white,lineWidth:2))
                            .accessibilityLabel(joint == .leftWrist ? "Blue hand" : "Pink hand")
                            .position(x:point.x*geo.size.width,y:point.y*geo.size.height)
                    }
                }
            }.allowsHitTesting(false)
        }
    }
    private var welcome: some View {
        ZStack {
            Color.black.opacity(0.68).background(.ultraThinMaterial).ignoresSafeArea()
            ScrollView { VStack(alignment:.leading,spacing:18) {
                Text("MOVEMENT LAB / CONCEPT 001").font(.system(.caption,design:.monospaced)).foregroundStyle(mint)
                Text("Your body.\nThe controller.").font(.system(size:58,weight:.black,design:.rounded)).tracking(-3)
                Text("Shuffle through an endless test track. Shuffle and touch arm targets.\nBuild your rhythm. Earn your way into the boss arena.").font(.title3).foregroundStyle(mutedText)
                HStack(spacing:24) { Label("4-step calibration",systemImage:"viewfinder"); Label("Adaptive difficulty",systemImage:"waveform.path"); Label("Mastery bosses",systemImage:"flame") }.font(.caption).foregroundStyle(mint)
                consecutiveGroupsSetting
                Text("Place your Mac facing you, with the camera framing your head, torso, and hips. Knees and feet can stay out of frame.\nWait for MOVE NOW, then arrive in the requested lane as the obstacle reaches you. Touch arm targets on the beat. Keep your hands in view.").font(.callout).foregroundStyle(mutedText)
                HStack(spacing:16) {
                    Button("Vision camera") { imu.stop(); game.start(demo:false); tracker.start() }
                    Button("iPhone IMU sensors") { tracker.capture.stop(); game.startIMU(); imu.start() }
                    Button("Try cursor demo") { imu.stop(); tracker.capture.stop(); game.start(demo:true) }
                }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(ink).controlSize(.large)
                skillsSetup
                HStack(spacing:16) {
                    Button("Obstacle Dodge · Vision") { imu.stop(); game.startObstacles(); tracker.start() }
                    Button("Obstacle Dodge · iPhone IMU") { tracker.capture.stop(); game.startObstacles(imu:true); imu.start() }
                    Button("Obstacle Dodge · cursor") { imu.stop(); tracker.capture.stop(); game.startObstacles(demo:true) }
                }.buttonStyle(.borderedProminent).tint(.orange).foregroundStyle(ink).controlSize(.large)
                Text("Obstacle Dodge: consecutive obstacles, clear lanes, no beat window. Move early and stay clear as they pass.").font(.caption).foregroundStyle(.orange)
                HStack(spacing:16) {
                    Button("Slice & Punch · Vision") { imu.stop(); game.startHands(); tracker.start(hands:true) }
                    Button("Slice & Punch · demo") { imu.stop(); tracker.capture.stop(); game.startHands(demo:true) }
                }.buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(ink).controlSize(.large)
                Text("Hand mode: open-hand slices ↑ ↓; closed-fist punches ↑ ← →. Return to chest-height guard.").font(.caption).foregroundStyle(.cyan)
                Text("iPhone IMU: use the companion on the same Wi-Fi; secure the phone at your waist.").font(.caption).foregroundStyle(mint)
                Text("Cursor demo: hover in the left, center, or right third to move. Hover arm targets on the beat. Leaving the window pauses play.").font(.caption).foregroundStyle(mint)
                Text("ALL SHAPES ARE PLACEHOLDERS · CAMERA PROCESSING STAYS ON DEVICE").font(.system(size:10,design:.monospaced)).foregroundStyle(mutedText)
            }.padding(40) }
        }
    }
}

#endif

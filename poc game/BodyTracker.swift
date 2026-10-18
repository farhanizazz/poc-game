import SwiftUI
import AVFoundation
import Vision
import Combine
import CoreImage

nonisolated struct BodyFrame: Sendable {
    var points: [String: CGPoint]
    var valid: Bool
    var timestamp: Date
    var capturedUptime: Double? = nil
    var handShapes: [String: HandShape] = [:]
    var previewImage: CGImage? = nil

    // A torso must be observed; lower-leg predictions cannot make tracking valid.
    var torso: (root: CGPoint, shoulderY: Double, height: Double)? {
        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            points[joint.rawValue.rawValue]
        }
        guard let root = point(.root), let leftShoulder = point(.leftShoulder),
              let rightShoulder = point(.rightShoulder), point(.leftHip) != nil,
              point(.rightHip) != nil else { return nil }
        let shoulderY = (leftShoulder.y + rightShoulder.y)/2
        let height = root.y-shoulderY
        guard height >= 0.08 else { return nil }
        return (root, shoulderY, height)
    }
}

// Capture and Vision run on one serial queue; only immutable joint snapshots cross to UI.
nonisolated final class PoseCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "shuffle.pose.capture")
    var onFrame: (@Sendable (BodyFrame) -> Void)?
    var onError: (@Sendable (String) -> Void)?
    private let previewContext = CIContext(options: [.cacheIntermediates: false])
    private var configured = false
    private var frameCount = 0
    private var handsEnabled = false
    func setHandsEnabled(_ enabled: Bool) { queue.async { self.handsEnabled = enabled } }
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            guard let self else { return }
            guard allowed else { self.onError?("Camera permission denied. Enable Camera in System Settings → Privacy & Security → Camera, or use Keyboard Demo."); return }
            self.queue.async { self.configure() }
        }
    }
    private func configure() {
        if configured { if !session.isRunning { session.startRunning() }; return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { onError?("No camera available. Connect a webcam or try Keyboard Demo."); return }
        session.beginConfiguration(); session.sessionPreset = .medium
        guard session.canAddInput(input) else { session.commitConfiguration(); onError?("Camera input unavailable."); return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { session.commitConfiguration(); onError?("Camera output unavailable."); return }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
        }
        session.commitConfiguration(); configured = true; session.startRunning()
    }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        guard (!handsEnabled || frameCount % 2 == 0), let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let observedAt = Date()
        let observedUptime = ProcessInfo.processInfo.systemUptime
        // Mirror the exact buffer analyzed by Vision. Image and landmarks travel
        // together, so the visible hand stays aligned with its contact marker.
        let mirrored = CIImage(cvPixelBuffer: buffer).oriented(.upMirrored)
        let preview = previewContext.createCGImage(mirrored, from: mirrored.extent)
        let request = VNDetectHumanBodyPoseRequest()
        do {
            // Native sensor orientation, then mirror x for a front-facing movement display.
            let handRequest = VNDetectHumanHandPoseRequest()
            handRequest.maximumHandCount = 2
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform(handsEnabled ? [request,handRequest] : [request])
            guard let body = request.results?.first else { onFrame?(BodyFrame(points: [:], valid: false, timestamp: observedAt, capturedUptime: observedUptime, previewImage: preview)); return }
            let joints = try body.recognizedPoints(.all)
            var points: [String: CGPoint] = [:]
            let excluded: Set<VNHumanBodyPoseObservation.JointName> = [.leftKnee,.rightKnee,.leftAnkle,.rightAnkle]
            for (key, point) in joints where point.confidence > 0.45 && !excluded.contains(key) {
                points[key.rawValue.rawValue] = CGPoint(x: 1-point.x, y: 1-point.y)
            }
            var frame = BodyFrame(points: points, valid: false, timestamp: observedAt, capturedUptime: observedUptime, previewImage: preview)
            if handsEnabled {
                var assigned: Set<String> = []
                for hand in handRequest.results ?? [] {
                    guard let hp = try? hand.recognizedPoints(.all), let wrist = hp[.wrist], wrist.confidence > 0.35 else { continue }
                    let location = CGPoint(x:1-wrist.x,y:1-wrist.y)
                    let candidates: [VNHumanBodyPoseObservation.JointName] = [.leftWrist,.rightWrist]
                    let nearest = candidates.compactMap { joint -> (String,Double)? in
                        let name = joint.rawValue.rawValue
                        guard !assigned.contains(name), let bodyWrist = points[name] else { return nil }
                        return (name,hypot(bodyWrist.x-location.x,bodyWrist.y-location.y))
                    }.min { $0.1 < $1.1 }
                    guard let nearest, nearest.1 < 0.12 else { continue }
                    let fingers: [(VNHumanHandPoseObservation.JointName,VNHumanHandPoseObservation.JointName)] = [(.indexTip,.indexPIP),(.middleTip,.middlePIP),(.ringTip,.ringPIP),(.littleTip,.littlePIP)]
                    var tips: [CGPoint] = [], pips: [CGPoint] = []
                    for (tip,pip) in fingers {
                        if let t = hp[tip], let p = hp[pip], t.confidence > 0.35, p.confidence > 0.35 {
                            tips.append(CGPoint(x:1-t.x,y:1-t.y)); pips.append(CGPoint(x:1-p.x,y:1-p.y))
                        }
                    }
                    frame.handShapes[nearest.0] = HandShapeClassifier.classify(wrist:location,tips:tips,knuckles:pips)
                    assigned.insert(nearest.0)
                }
            }
            frame.valid = frame.torso != nil
            onFrame?(frame)
        } catch { onFrame?(BodyFrame(points: [:], valid: false, timestamp: observedAt, capturedUptime: observedUptime, previewImage: preview)) }
    }
}

@MainActor final class BodyTracker: ObservableObject {
    let capture = PoseCapture()
    @Published var previewImage: CGImage?
    @Published var points: [String: CGPoint] = [:]
    @Published var error: String?
    @Published var lastFrame = Date.distantPast
    var onPose: ((BodyFrame) -> Void)?
    private var leftGesture = HandGestureDetector()
    private var rightGesture = HandGestureDetector()
    private var handStepStamp = 0.0
    init() {
        capture.onFrame = { [weak self] frame in Task { @MainActor [weak self] in
            self?.previewImage = frame.previewImage; self?.points = frame.points; self?.lastFrame = frame.timestamp; self?.onPose?(frame)
        } }
        capture.onError = { [weak self] message in Task { @MainActor [weak self] in self?.error = message } }
    }
    func start(hands: Bool = false) { error = nil; capture.setHandsEnabled(hands); capture.start() }
    func route(_ frame: BodyFrame, to game: GameModel) {
        guard game.handMode else { leftGesture.reset(); rightGesture.reset(); game.consume(frame); return }
        guard !game.demo, !game.imuMode else { return }
        func p(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? { frame.points[joint.rawValue.rawValue] }
        let required: [VNHumanBodyPoseObservation.JointName] = [.leftShoulder,.rightShoulder,.leftElbow,.rightElbow,.leftWrist,.rightWrist]
        let leftShapeText = frame.handShapes[VNHumanBodyPoseObservation.JointName.leftWrist.rawValue.rawValue]?.rawValue ?? "not visible"
        let rightShapeText = frame.handShapes[VNHumanBodyPoseObservation.JointName.rightWrist.rawValue.rawValue]?.rawValue ?? "not visible"
        game.handInstruction = "LEFT: \(leftShapeText.uppercased()) · RIGHT: \(rightShapeText.uppercased())"
        let visible = required.allSatisfy { p($0) != nil }
            && frame.handShapes[VNHumanBodyPoseObservation.JointName.leftWrist.rawValue.rawValue] != nil
            && frame.handShapes[VNHumanBodyPoseObservation.JointName.rightWrist.rawValue.rawValue] != nil
            && frame.handShapes.values.filter { $0 != .unknown }.count >= 2
        game.tracking = frame.valid && frame.torso != nil && visible
        guard game.tracking, !game.paused else {
            game.hold = 0; game.interruptShuffle(); leftGesture.reset(); rightGesture.reset(); return
        }
        guard let ls = p(.leftShoulder), let rs = p(.rightShoulder),
              let lw = p(.leftWrist), let rw = p(.rightWrist), let le = p(.leftElbow), let re = p(.rightElbow) else { return }
        let span = abs(ls.x-rs.x)
        guard span >= 0.05 else { game.tracking = false; game.interruptShuffle(); return }
        let ln = CGPoint(x:(lw.x-ls.x)/span,y:(lw.y-ls.y)/span)
        let rn = CGPoint(x:(rw.x-rs.x)/span,y:(rw.y-rs.y)/span)
        let lShape = frame.handShapes[VNHumanBodyPoseObservation.JointName.leftWrist.rawValue.rawValue] ?? .unknown
        let rShape = frame.handShapes[VNHumanBodyPoseObservation.JointName.rightWrist.rawValue.rawValue] ?? .unknown
        if game.phase == .calibration {
            let dt = min(0.1,max(0,frame.timestamp.timeIntervalSince(game.previousPoseTime)))
            game.previousPoseTime = frame.timestamp
            let expected: HandShape = game.calibrationStep == 1 ? .fist : .open
            let guardOK = [ln,rn].allSatisfy { abs($0.x) < 1 && $0.y > -0.1 && $0.y < 1.5 }
            game.calibrateHands(guardOK:guardOK && lShape == expected && rShape == expected,left:ln,right:rn,dt:dt)
            leftGesture.reset(); rightGesture.reset(); return
        }
        guard game.active else { leftGesture.reset(); rightGesture.reset(); return }
        if game.stepTrackingInterrupted { game.prepareStep() }
        if handStepStamp != game.stepStartedUptime {
            leftGesture.reset(); rightGesture.reset(); handStepStamp = game.stepStartedUptime
        }
        let time = frame.timestamp.timeIntervalSinceReferenceDate
        if let event = leftGesture.sample(time:time,wrist:lw,elbow:le,shoulder:ls,shoulderSpan:span,shape:lShape,neutral:game.handNeutralLeft) {
            game.receiveHand(event.move,duration:event.duration)
        }
        if let event = rightGesture.sample(time:time,wrist:rw,elbow:re,shoulder:rs,shoulderSpan:span,shape:rShape,neutral:game.handNeutralRight) {
            game.receiveHand(event.move,duration:event.duration)
        }
    }
    func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? { points[joint.rawValue.rawValue] }
}

extension GameModel {
    func consume(_ frame: BodyFrame) {
        guard !demo, !imuMode, !handMode else { return }
        if let captured = frame.capturedUptime {
            let latency = ProcessInfo.processInfo.systemUptime-captured
            guard latency >= 0, latency <= 0.3 else {
                tracking = false; hold = 0; resetArmContact(); interruptShuffle(); return
            }
            // Never apply a queued observation to a cue that appeared after that frame.
            if active && !stepTrackingInterrupted && captured < stepStartedUptime { return }
        }
        func p(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? { frame.points[name.rawValue.rawValue] }
        let wrists = [p(.leftWrist),p(.rightWrist)]
        tracking = frame.valid && frame.torso != nil && (currentMove != .armTouch || wrists.contains { $0 != nil }) && (!skillsCombined || !active || wrists.allSatisfy { $0 != nil })
        guard tracking, !paused else { hold = 0; resetArmContact(); interruptShuffle(); return }
        guard let torso = frame.torso, let ls = p(.leftShoulder), let rs = p(.rightShoulder) else { return }
        if skillsMode { skills.leftShoulder = ls; skills.rightShoulder = rs }
        shoulderMid = CGPoint(x:(ls.x+rs.x)/2,y:(ls.y+rs.y)/2)
        shoulderSpan = max(0.1,abs(ls.x-rs.x)); torsoScale = torso.height
        let gap = frame.timestamp.timeIntervalSince(previousPoseTime)
        if gap > 0.3 { resetArmContact(); if skillsMode { interruptShuffle() } }
        let dt = min(0.1, max(0, gap)); previousPoseTime = frame.timestamp
        if phase == .calibration { calibrate(position: torso.root, height: torso.height, dt: dt); return }
        guard active else { return }
        let step = stepStartedUptime
        let age = frame.capturedUptime.map { max(0,$0-stepStartedUptime) } ?? cueAge
        observeShuffle(x: torso.root.x, observedAge:age)
        guard step == stepStartedUptime else { return }
        observeArm(wrists:wrists,age:age)
    }
}

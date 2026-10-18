#if os(iOS)
import SwiftUI
import CoreMotion
import Network
import Combine

@MainActor final class PhoneMotion: ObservableObject {
    @Published var status = "Connect to the Mac on the same Wi-Fi"
    @Published var instruction = "Secure the phone upright at your waist, screen facing outward."
    @Published var connected = false
    private let motion = CMMotionManager()
    private var wire: MotionWire?
    private var detector = ShuffleDetector()
    private var heartbeat = 0.0
    func connect(address: String, code: String) {
        stop()
        let parts = address.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count == 2, let portValue = UInt16(parts[1]), let port = NWEndpoint.Port(rawValue: portValue) else {
            status = "Enter the Mac address including :port"; return
        }
        guard motion.isDeviceMotionAvailable else { status = "Motion sensors require a physical iPhone."; return }
        let candidate = MotionWire(NWConnection(host: NWEndpoint.Host(String(parts[0])), port: port, using: .tcp))
        wire = candidate; status = "Connecting…"
        candidate.onReady = { [weak candidate] in candidate?.send(MotionMessage(type: "hello", code: code)) }
        candidate.onMessage = { [weak self] message in
            guard let self else { return }
            switch message.type {
            case "accepted": self.connected = true; self.status = "Connected. Keep this app open."; self.startMotion()
            case "ping": self.wire?.send(MotionMessage(type: "pong", time: ProcessInfo.processInfo.systemUptime, echo: message.time))
            case "instruction": self.instruction = message.text ?? ""
            default: break
            }
        }
        candidate.onClose = { [weak self] in
            self?.motion.stopDeviceMotionUpdates(); self?.connected = false
            self?.status = "Disconnected. Check the address, code, Wi-Fi and Local Network permission."
            UIApplication.shared.isIdleTimerDisabled = false
        }
        candidate.start()
    }
    private func startMotion() {
        detector.reset(); heartbeat = 0; UIApplication.shared.isIdleTimerDisabled = true
        motion.deviceMotionUpdateInterval = 1.0/50
        motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let sample, error == nil else { self.status = "Motion unavailable. Check Motion & Fitness permission."; self.stop(); return }
                let upright = sample.gravity.y < -0.7 && abs(sample.rotationRate.z) < 1.5
                if let event = self.detector.sample(time: sample.timestamp, lateral: sample.userAcceleration.x, upright: upright) {
                    self.wire?.send(MotionMessage(type: "shuffle", time: event.end, start: event.start, direction: event.direction))
                }
                if sample.timestamp-self.heartbeat >= 0.2 {
                    self.heartbeat = sample.timestamp
                    self.wire?.send(MotionMessage(type: "heartbeat", ready: upright))
                }
            }
        }
    }
    func stop() {
        motion.stopDeviceMotionUpdates(); wire?.close(); wire = nil; connected = false; detector.reset()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
struct IPhoneCompanionView: View {
    @StateObject private var phone = PhoneMotion()
    @State private var address = ""
    @State private var code = ""
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack {
            Form {
                Section("iPhone IMU controller") {
                    Text("Open Shuffle Run on your Mac and choose iPhone IMU. Enter the address and pairing code shown there.")
                    TextField("Mac address:port", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("6-digit pairing code", text: $code).keyboardType(.numberPad)
                    Button(phone.connected ? "Disconnect" : "Connect") {
                        if phone.connected { phone.stop() } else { phone.connect(address: address, code: code) }
                    }
                    Text(phone.status)
                }
                Section("Movement instructions") {
                    Text(phone.instruction).font(.title2.bold())
                    Text("Keep the phone firmly secured at your waist, upright with the screen facing outward. Face the Mac throughout calibration and play. Keep this app in the foreground.")
                    Text("Shuffle-only mode. Arrival is estimated from movement stopping; the phone cannot verify floor-box position. No camera is used.")
                }
            }.navigationTitle("Shuffle Run · IMU")
        }.onChange(of: phase) { _, value in if value != .active { phone.stop() } }
    }
}
#endif

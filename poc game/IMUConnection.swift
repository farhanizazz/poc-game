import Foundation
import Network
import Combine

struct MotionMessage: Codable {
    var type: String
    var code: String? = nil
    var time: Double? = nil
    var echo: Double? = nil
    var start: Double? = nil
    var direction: Int? = nil
    var ready: Bool? = nil
    var text: String? = nil
}

// Length-bounded newline framing; one authenticated phone per game session.
@MainActor final class MotionWire {
    let connection: NWConnection
    var onMessage: ((MotionMessage) -> Void)?
    var onClose: (() -> Void)?
    var onReady: (() -> Void)?
    private var buffer = Data()
    private var closed = false
    init(_ connection: NWConnection) { self.connection = connection }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready: self?.onReady?()
                case .failed, .cancelled: self?.close()
                default: break
                }
            }
        }
        connection.start(queue: .main); receive()
    }
    func send(_ message: MotionMessage) {
        guard !closed, var data = try? JSONEncoder().encode(message) else { return }
        data.append(10)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { Task { @MainActor [weak self] in self?.close() } }
        })
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            Task { @MainActor [weak self] in
                guard let self, !self.closed else { return }
                if let data { self.buffer.append(data) }
                guard self.buffer.count <= 16384 else { self.close(); return }
                while let end = self.buffer.firstIndex(of: 10) {
                    let line = self.buffer.prefix(upTo: end)
                    self.buffer.removeSubrange(...end)
                    guard let message = try? JSONDecoder().decode(MotionMessage.self, from: line) else { self.close(); return }
                    self.onMessage?(message)
                }
                if done || error != nil { self.close() } else { self.receive() }
            }
        }
    }
    func close() {
        guard !closed else { return }; closed = true
        connection.cancel(); onClose?()
    }
}

#if os(macOS)
@MainActor final class IMUReceiver: ObservableObject {
    @Published var status = "Choose iPhone IMU to start pairing"
    @Published var address = ""
    @Published var code = ""
    @Published var ready = false
    var onShuffle: ((Int, Double, Double) -> Void)?
    private var listener: NWListener?
    private var wire: MotionWire?
    private var authenticated = false
    private var lastHeartbeat = 0.0
    private var offset = 0.0
    private var bestRTT = Double.infinity
    private var lastEnd = 0.0
    private var pendingPings: Set<Double> = []
    private var timer: Timer?
    private var instruction = ""
    func start() {
        stop(); code = String(Int.random(in: 100000...999999))
        do {
            let listener = try NWListener(using: .tcp, on: .any); self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor [weak self, weak listener] in
                    guard let self else { return }
                    if case .ready = state, let port = listener?.port {
                        self.address = "\(Host.current().localizedName?.replacingOccurrences(of: " ", with: "-") ?? "Mac").local:\(port.rawValue)"
                        // The OS host name is the authoritative mDNS name when available.
                        if let host = Host.current().name { self.address = "\(host):\(port.rawValue)" }
                        self.status = "Enter this Mac address and pairing code on iPhone"
                    }
                    if case .failed(let error) = state { self.status = error.localizedDescription }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in self?.accept(connection) }
            }
            listener.start(queue: .main)
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.poll() }
            }
        } catch { status = error.localizedDescription }
    }
    private func accept(_ connection: NWConnection) {
        guard wire == nil else { connection.cancel(); return }
        let candidate = MotionWire(connection); wire = candidate
        authenticated = false; bestRTT = .infinity; lastEnd = 0; pendingPings = []
        lastHeartbeat = ProcessInfo.processInfo.systemUptime
        candidate.onMessage = { [weak self] in self?.receive($0) }
        candidate.onClose = { [weak self, weak candidate] in
            guard let self, self.wire === candidate else { return }
            self.wire = nil; self.ready = false; self.authenticated = false
            self.status = "Phone disconnected. Reconnect, then restart calibration."
        }
        candidate.start()
    }
    private func receive(_ message: MotionMessage) {
        let now = ProcessInfo.processInfo.systemUptime
        if !authenticated {
            guard message.type == "hello", message.code == code else { wire?.close(); return }
            authenticated = true; wire?.send(MotionMessage(type: "accepted")); ping(); return
        }
        switch message.type {
        case "pong":
            guard let echo = message.echo, let remote = message.time, remote.isFinite,
                  pendingPings.remove(echo) != nil else { return }
            let rtt = now-echo
            if rtt < bestRTT { bestRTT = rtt; offset = (echo+now)/2-remote }
        case "heartbeat":
            lastHeartbeat = now
            ready = message.ready == true && bestRTT < 0.2
            status = ready ? "iPhone motion connected · estimated arrival" : "Keep iPhone upright and still; checking motion and connection"
        case "shuffle":
            guard ready, now-lastHeartbeat < 1, let start = message.start, let end = message.time,
                  let direction = message.direction, abs(direction) == 1,
                  start.isFinite, end.isFinite, end > start, end-start <= 4,
                  end > lastEnd, abs(now-(end+offset)) < 0.8 else { return }
            lastEnd = end
            onShuffle?(direction, start+offset, end+offset)
        default: break
        }
    }
    private func ping() {
        let now = ProcessInfo.processInfo.systemUptime
        pendingPings = pendingPings.filter { now-$0 < 3 }; pendingPings.insert(now)
        wire?.send(MotionMessage(type: "ping", time: now))
    }
    private func poll() {
        let age = ProcessInfo.processInfo.systemUptime-lastHeartbeat
        if wire != nil && age > 1 { ready = false; status = "Motion stream paused. Keep the iPhone app open." }
        if wire != nil && age > 5 { wire?.close() }
        if authenticated { ping() }
    }
    func show(_ text: String) {
        guard text != instruction else { return }; instruction = text
        wire?.send(MotionMessage(type: "instruction", text: text))
    }
    func stop() {
        timer?.invalidate(); timer = nil; wire?.close(); wire = nil
        listener?.cancel(); listener = nil; ready = false; authenticated = false; instruction = ""
    }
}
#endif

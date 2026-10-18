import Foundation
import Network

@main struct IMUConnectionChecks {
    @MainActor static func main() async throws {
        let receiver = IMUReceiver(); receiver.start()
        for _ in 0..<100 {
            if !receiver.address.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let portString = receiver.address.split(separator: ":").last, let portNumber = UInt16(portString),
              let port = NWEndpoint.Port(rawValue: portNumber) else { fatalError("Listener did not start: \(receiver.status)") }
        let wrong = MotionWire(NWConnection(host:"127.0.0.1",port:port,using:.tcp))
        var rejected = false
        wrong.onReady = { wrong.send(MotionMessage(type:"hello",code:"invalid")) }
        wrong.onClose = { rejected = true }; wrong.start()
        for _ in 0..<100 { if rejected { break }; try await Task.sleep(for:.milliseconds(20)) }
        assert(rejected && !receiver.ready)
        let phone = MotionWire(NWConnection(host:"127.0.0.1",port:port,using:.tcp))
        var delivered = 0
        receiver.onShuffle = { direction, start, end in
            assert(direction == 1 && abs(end-start-0.5) < 0.01); delivered += 1
        }
        phone.onReady = { phone.send(MotionMessage(type:"hello",code:receiver.code)) }
        phone.onMessage = { message in
            if message.type == "ping" {
                // Simulate a phone clock that differs by 100 seconds.
                phone.send(MotionMessage(type:"pong",time:ProcessInfo.processInfo.systemUptime-100,echo:message.time))
                phone.send(MotionMessage(type:"heartbeat",ready:true))
            }
        }
        phone.start()
        for _ in 0..<100 { if receiver.ready { break }; try await Task.sleep(for:.milliseconds(20)) }
        assert(receiver.ready, receiver.status)
        let end = ProcessInfo.processInfo.systemUptime-100
        let event = MotionMessage(type:"shuffle",time:end,start:end-0.5,direction:1)
        phone.send(event); phone.send(event)
        try await Task.sleep(for:.milliseconds(150))
        assert(delivered == 1, "Clock-mapped events arrive once; duplicates are rejected")
        phone.close()
        for _ in 0..<100 { if !receiver.ready { break }; try await Task.sleep(for:.milliseconds(20)) }
        assert(!receiver.ready)
        receiver.stop()
        print("PASS: pairing rejection, local connection, clock offset, heartbeat readiness, event delivery, duplicate rejection, disconnect")
    }
}

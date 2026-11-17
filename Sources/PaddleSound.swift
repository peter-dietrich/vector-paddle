import Foundation
import AVFoundation

@MainActor
final class PaddleSound {
    private var player: AVAudioPlayer?
    private var lastPlayed = Date.distantPast

    func play(_ event: PaddleEvent, enabled: Bool) {
        guard enabled, Date().timeIntervalSince(lastPlayed) > 0.045 else { return }
        lastPlayed = Date()
        let frequency: Double
        let duration: Double
        switch event {
        case .paddle: frequency = 660; duration = 0.055
        case .wall: frequency = 430; duration = 0.04
        case .score: frequency = 240; duration = 0.17
        case .pickup: frequency = 920; duration = 0.15
        case .win: frequency = 840; duration = 0.25
        }
        let sampleRate = 22_050
        let samples = Int(Double(sampleRate) * duration)
        var payload = Data()
        let length = UInt32(samples * 2)
        func write16(_ value: UInt16) {
            payload.append(UInt8(truncatingIfNeeded: value))
            payload.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func write32(_ value: UInt32) {
            payload.append(UInt8(truncatingIfNeeded: value))
            payload.append(UInt8(truncatingIfNeeded: value >> 8))
            payload.append(UInt8(truncatingIfNeeded: value >> 16))
            payload.append(UInt8(truncatingIfNeeded: value >> 24))
        }
        payload.append(contentsOf: Array("RIFF".utf8)); write32(length + 36)
        payload.append(contentsOf: Array("WAVEfmt ".utf8)); write32(16)
        write16(1); write16(1); write32(UInt32(sampleRate))
        write32(UInt32(sampleRate * 2)); write16(2); write16(16)
        payload.append(contentsOf: Array("data".utf8)); write32(length)
        for n in 0..<samples {
            let t = Double(n) / Double(sampleRate)
            let fade = pow(max(0, 1 - Double(n) / Double(samples)), 1.4)
            let oscillation = sin(2 * Double.pi * frequency * t)
            let sample = Int16(clamping: Int(oscillation * fade * 14_000))
            write16(UInt16(bitPattern: sample))
        }
        if let next = try? AVAudioPlayer(data: payload) {
            player = next
            next.prepareToPlay()
            next.play()
        }
    }
}

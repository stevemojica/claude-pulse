import Foundation
import SwiftUI
import AVFoundation
import ClaudePulseCore

/// Programmatically generates and plays subtle notification sounds.
/// No shipped audio files — sounds are synthesized using AVAudioEngine.
@MainActor
final class SoundManager {
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var eventObserver: Any?

    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("soundVolume") private var soundVolume: Double = 0.5

    init(sessionManager: SessionManager) {
        setupEngine()

        // Listen for session events
        eventObserver = NotificationCenter.default.addObserver(
            forName: SessionManager.sessionEventNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?["event"] as? String else { return }
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }
    }

    private func setupEngine() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        guard let engine, let playerNode else { return }
        engine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    private func handleEvent(_ event: String) {
        guard soundEnabled else { return }

        switch event {
        case SessionManager.SessionEvent.sessionAdded.rawValue:
            playTone(frequency: 880, duration: 0.08, volume: 0.3)
        case SessionManager.SessionEvent.permissionRequested.rawValue:
            playTone(frequency: 660, duration: 0.15, volume: 0.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.playTone(frequency: 880, duration: 0.12, volume: 0.4)
            }
        case SessionManager.SessionEvent.questionAsked.rawValue:
            playTone(frequency: 550, duration: 0.12, volume: 0.4)
        case SessionManager.SessionEvent.sessionUpdated.rawValue:
            // Check if it's a completion
            break // Only play for attention-worthy events
        default:
            break
        }
    }

    /// Generate and play a sine wave tone.
    private func playTone(frequency: Double, duration: Double, volume: Float) {
        guard let engine, let playerNode, engine.isRunning else { return }

        let sampleRate = 44100.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let adjustedVolume = volume * Float(soundVolume)

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            // Sine wave with exponential decay envelope
            let envelope = Float(exp(-t * 8.0 / duration))
            channelData[i] = sin(Float(2.0 * .pi * frequency * t)) * adjustedVolume * envelope
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !playerNode.isPlaying { playerNode.play() }
    }

    deinit {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        engine?.stop()
    }
}


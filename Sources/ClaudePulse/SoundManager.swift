import Foundation
import SwiftUI
import AVFoundation
import ClaudePulseCore

/// Programmatically generates and plays subtle notification sounds.
/// Uses NSSound for system sounds with AVAudioEngine tone synthesis as primary.
@MainActor
final class SoundManager {
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var eventObserver: Any?
    private var engineReady = false

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
        let audioEngine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        audioEngine.attach(player)

        // Use the output node's format to avoid sample rate mismatches
        let outputFormat = audioEngine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44100.0

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            print("[ClaudePulse] Sound: Could not create audio format")
            return
        }

        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)

        do {
            try audioEngine.start()
            engine = audioEngine
            playerNode = player
            engineReady = true
        } catch {
            print("[ClaudePulse] Sound: AVAudioEngine failed to start: \(error). Falling back to system sounds.")
        }
    }

    private func handleEvent(_ event: String) {
        guard soundEnabled else { return }

        switch event {
        case SessionManager.SessionEvent.sessionAdded.rawValue:
            // New session connected — quiet pop
            playTone(frequency: 880, duration: 0.08, volume: 0.3)

        case SessionManager.SessionEvent.permissionRequested.rawValue:
            // Permission needed — two-tone ascending chime
            playTone(frequency: 660, duration: 0.15, volume: 0.5)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                self?.playTone(frequency: 880, duration: 0.12, volume: 0.4)
            }

        case SessionManager.SessionEvent.questionAsked.rawValue:
            // Agent has a question — gentle tone
            playTone(frequency: 550, duration: 0.15, volume: 0.4)

        case SessionManager.SessionEvent.sessionRemoved.rawValue:
            // Session ended — low soft tone
            playTone(frequency: 440, duration: 0.1, volume: 0.2)

        default:
            break
        }
    }

    /// Generate and play a sine wave tone, or fall back to system sound.
    private func playTone(frequency: Double, duration: Double, volume: Float) {
        if engineReady {
            playEngineTone(frequency: frequency, duration: duration, volume: volume)
        } else {
            playSystemSound()
        }
    }

    private func playEngineTone(frequency: Double, duration: Double, volume: Float) {
        guard let engine, let playerNode, engine.isRunning else {
            // Engine died — try to restart
            engineReady = false
            setupEngine()
            if !engineReady { playSystemSound(); return }
            guard let engine = self.engine, let playerNode = self.playerNode, engine.isRunning else {
                playSystemSound(); return
            }
            let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
            playEngineToneInternal(playerNode: playerNode, frequency: frequency, duration: duration, volume: volume, sampleRate: sr > 0 ? sr : 44100)
            return
        }

        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        playEngineToneInternal(playerNode: playerNode, frequency: frequency, duration: duration, volume: volume, sampleRate: sr > 0 ? sr : 44100)
    }

    private func playEngineToneInternal(playerNode: AVAudioPlayerNode, frequency: Double, duration: Double, volume: Float, sampleRate: Double) {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let adjustedVolume = volume * Float(soundVolume)

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = Float(exp(-t * 8.0 / duration))
            channelData[i] = sin(Float(2.0 * .pi * frequency * t)) * adjustedVolume * envelope
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !playerNode.isPlaying { playerNode.play() }
    }

    /// Fallback: use macOS system sound
    private func playSystemSound() {
        NSSound.beep()
    }

    func tearDown() {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
            eventObserver = nil
        }
        playerNode?.stop()
        engine?.stop()
        engine = nil
        playerNode = nil
        engineReady = false
    }

    deinit {
        // tearDown() should have been called already; this is a safety net
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
            eventObserver = nil
        }
        engine?.stop()
    }
}

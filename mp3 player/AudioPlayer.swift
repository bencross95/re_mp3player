import AVFoundation
import Accelerate
import SwiftUI

class AudioPlayer: ObservableObject {
    @Published var waveformPoints: [CGFloat] = Array(repeating: 0, count: 60)
    @Published var isPlaying: Bool = false
    @Published var volume: Float = 0.7

    private var engine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private let bufferSize = 1024
    private var _duration: TimeInterval = 1
    private var audioFile: AVAudioFile?
    private var seekOffset: TimeInterval = 0

    var currentTime: TimeInterval {
        guard let node = playerNode,
              let lastRenderTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: lastRenderTime) else { return seekOffset }
        return seekOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    var duration: TimeInterval { _duration }

    func play(url: URL) {
        stop()
        seekOffset = 0

        do {
            let file = try AVAudioFile(forReading: url)
            self.audioFile = file
            let format = file.processingFormat

            engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            playerNode = node
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)

            node.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: format) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }

            try engine.start()
            _duration = file.duration

            node.scheduleFile(file, at: nil)
            node.volume = volume
            node.play()
            isPlaying = true
        } catch {
            print("Playback error: \(error)")
        }
    }

    func stop() {
        playerNode?.stop()
        engine.stop()
        waveformPoints = Array(repeating: 0, count: waveformPoints.count)
        isPlaying = false
        seekOffset = 0
        audioFile = nil
    }

    func togglePlayback() {
        guard let node = playerNode else { return }
        if node.isPlaying {
            node.pause()
            isPlaying = false
        } else {
            node.play()
            isPlaying = true
        }
    }

    func seek(to time: TimeInterval) {
        guard let file = audioFile, let node = playerNode else { return }

        let sampleRate = file.processingFormat.sampleRate
        let totalFrames = AVAudioFramePosition(file.length)
        let clampedTime = max(0, min(time, _duration))
        let startFrame = AVAudioFramePosition(clampedTime * sampleRate)
        let remainingFrames = AVAudioFrameCount(totalFrames - startFrame)

        guard remainingFrames > 0 else { return }

        seekOffset = clampedTime
        let wasPlaying = node.isPlaying

        node.stop()
        node.scheduleSegment(file, startingFrame: startFrame, frameCount: remainingFrames, at: nil)

        if wasPlaying {
            node.play()
        }
    }

    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        playerNode?.volume = volume
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var points: [CGFloat] = []
        let step = max(frameLength / waveformPoints.count, 1)

        for i in stride(from: 0, to: frameLength, by: step) {
            let chunk = UnsafeBufferPointer(start: channelData + i, count: min(step, frameLength - i))
            var rms: Float = 0
            vDSP_rmsqv(chunk.baseAddress!, 1, &rms, vDSP_Length(chunk.count))
            points.append(CGFloat(rms))
        }

        DispatchQueue.main.async { [weak self] in
            self?.waveformPoints = points
        }
    }
}

extension AVAudioFile {
    var duration: TimeInterval {
        Double(length) / processingFormat.sampleRate
    }
}

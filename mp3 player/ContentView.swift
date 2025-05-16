import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Audio Visualizer Logic

class AudioVisualizerModel: ObservableObject {
    @Published var waveformPoints: [CGFloat] = Array(repeating: 0, count: 100)

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let bufferSize = 1024

    func play(url: URL) {
        stop()

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            print("Could not open file: \(error)")
            return
        }

        let format = file.processingFormat

        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        player.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try engine.start()
            player.scheduleFile(file, at: nil, completionHandler: nil)
            player.play()
        } catch {
            print("Engine failed to start: \(error)")
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        waveformPoints = Array(repeating: 0, count: waveformPoints.count)
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

        DispatchQueue.main.async {
            self.waveformPoints = points
        }
    }
}

// MARK: - Waveform Line View

struct WaveformLineView: View {
    var samples: [CGFloat]

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let width = geometry.size.width
            let step = width / CGFloat(samples.count - 1)

            Path { path in
                path.move(to: CGPoint(x: 0, y: height / 2))

                for index in samples.indices {
                    let x = CGFloat(index) * step
                    let normalized = min(samples[index], 1.0) // normalize if needed
                    let y = height / 2 - (normalized * height / 2)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.accentColor, lineWidth: 2)
        }
    }
}

// MARK: - Main App View

struct ContentView: View {
    @State private var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music")
    @State private var directoryContents: [URL] = []
    @State private var selectedFile: URL?
    @ObservedObject private var visualizer = AudioVisualizerModel()

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    Button("Go Up") {
                        goUpDirectory()
                    }
                    .disabled(currentDirectory.pathComponents.count <= FileManager.default.homeDirectoryForCurrentUser.pathComponents.count + 1)

                    Text(currentDirectory.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal)

                List(directoryContents, id: \.self) { file in
                    HStack {
                        Image(systemName: isDirectory(file) ? "folder" : "music.note")
                        Text(file.lastPathComponent)
                    }
                    .onTapGesture {
                        if isDirectory(file) {
                            currentDirectory = file
                            loadContents()
                        } else if file.pathExtension.lowercased() == "mp3" {
                            selectedFile = file
                            visualizer.play(url: file)
                        }
                    }
                }
                .frame(minWidth: 250)
            }

            Divider()

            VStack {
                if let file = selectedFile {
                    Text("Now Playing: \(file.lastPathComponent)")
                        .font(.headline)
                        .padding(.top)
                } else {
                    Text("Select an MP3")
                        .foregroundColor(.gray)
                        .padding(.top)
                }

                WaveformLineView(samples: visualizer.waveformPoints)
                    .frame(height: 100)
                    .padding(.horizontal)

<<<<<<< HEAD
                Button("Stop") {
                    visualizer.stop()
=======
                    Button("pls Stop") {
                        stopPlayback()
                    }
                    .disabled(audioPlayer == nil)
>>>>>>> a5d3e02e84ae7ba7835b1adbd83bc0298ad57d19
                }
                .padding()

                Spacer()
            }
            .frame(minWidth: 300)
        }
        .frame(width: 750, height: 450)
        .onAppear {
            loadContents()
        }
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    func loadContents() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            self.directoryContents = contents.sorted { a, b in
                let aIsDir = isDirectory(a)
                let bIsDir = isDirectory(b)
                if aIsDir == bIsDir {
                    return a.lastPathComponent.lowercased() < b.lastPathComponent.lowercased()
                }
                return aIsDir && !bIsDir
            }
        } catch {
            print("Error reading directory: \(error)")
            directoryContents = []
        }
    }

    func goUpDirectory() {
        currentDirectory.deleteLastPathComponent()
        loadContents()
    }
}

#Preview {
    ContentView()
}

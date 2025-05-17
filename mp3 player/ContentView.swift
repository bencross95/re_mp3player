import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Audio Visualizer

class AudioVisualizerModel: ObservableObject {
    @Published var waveformPoints: [CGFloat] = Array(repeating: 0, count: 100)

    private var engine = AVAudioEngine()
    private var _player: AVAudioPlayerNode?
    private let bufferSize = 1024
    private var _duration: TimeInterval = 1
    private var currentURL: URL?
    private var currentVolume: Float = 1.0

    var activePlayer: AVAudioPlayerNode? {
        _player
    }

    var currentTime: TimeInterval {
        guard let node = _player,
              let lastRenderTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: lastRenderTime) else { return 0 }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    var duration: TimeInterval {
        _duration
    }

    func play(url: URL, startAt time: TimeInterval = 0) {
        stop()
        currentURL = url

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat

            engine = AVAudioEngine()
            _player = AVAudioPlayerNode()
            engine.attach(_player!)
            engine.connect(_player!, to: engine.mainMixerNode, format: format)

            _player!.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: format) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }

            try engine.start()

            let sampleRate = format.sampleRate
            let startSampleTime = AVAudioFramePosition(time * sampleRate)
            _duration = file.duration

            _player!.scheduleSegment(file, startingFrame: startSampleTime,
                                     frameCount: AVAudioFrameCount(file.length) - AVAudioFrameCount(startSampleTime), at: nil)
            _player!.volume = currentVolume
            _player!.play()
        } catch {
            print("Playback error: \(error)")
        }
    }

    func stop() {
        _player?.stop()
        engine.stop()
        waveformPoints = Array(repeating: 0, count: waveformPoints.count)
    }

    func togglePlayback() {
        guard let player = _player else { return }
        player.isPlaying ? player.pause() : player.play()
    }

    func setVolume(_ volume: Float) {
        currentVolume = volume
        _player?.volume = volume
    }

    func seek(to time: TimeInterval) {
        guard let url = currentURL else { return }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat

            engine.stop()
            _player?.stop()
            engine.detach(_player!)

            _player = AVAudioPlayerNode()
            engine.attach(_player!)
            engine.connect(_player!, to: engine.mainMixerNode, format: format)

            _player!.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: format) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }

            try engine.start()

            let sampleRate = format.sampleRate
            let startSampleTime = AVAudioFramePosition(time * sampleRate)
            _duration = file.duration

            _player!.scheduleSegment(file, startingFrame: startSampleTime,
                                     frameCount: AVAudioFrameCount(file.length) - AVAudioFrameCount(startSampleTime), at: nil)
            _player!.volume = currentVolume
            _player!.play()
        } catch {
            print("Seek failed: \(error)")
        }
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

extension AVAudioFile {
    var duration: TimeInterval {
        Double(length) / processingFormat.sampleRate
    }
}

// MARK: - Waveform View

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
                    let y = height / 2 - (min(samples[index], 1.0) * height / 2)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.accentColor, lineWidth: 2)
        }
    }
}

// MARK: - FileNode Model

struct FileNode: Identifiable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
}

// MARK: - Main View

struct ContentView: View {
    @ObservedObject private var visualizer = AudioVisualizerModel()
    @State private var columnStack: [[FileNode]] = []
    @State private var selectedFile: URL?
    @State private var lastColumnCount: Int = 0
    @State private var rootDirectory: URL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var isSeeking: Bool = false
    @State private var isPlaying: Bool = false
    @State private var currentVolume: Float = 1.0

    func openFolderPicker() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Select Root Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            folderBrowserView
            Divider()
            playerControlsView
        }
        .frame(height: 360)
        .onAppear {
            loadDirectoryContents(at: rootDirectory, replacingFromLevel: 0)

            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                guard !isSeeking else { return }
                currentTime = visualizer.currentTime
                duration = visualizer.duration
            }
        }
    }

    private var folderBrowserView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button("Choose Root Folder…") {
                    if let selected = openFolderPicker() {
                        rootDirectory = selected
                        loadDirectoryContents(at: selected, replacingFromLevel: 0)
                    }
                }
                .padding(.horizontal)

                Text("Current: \(rootDirectory.lastPathComponent)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 1) {
                        ForEach(Array(columnStack.enumerated()), id: \.offset) { (level, nodes) in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(nodes) { node in
                                        HStack {
                                            Image(systemName: node.isDirectory ? "folder" : "music.note")
                                            Text(node.url.lastPathComponent)
                                                .lineLimit(1)
                                        }
                                        .padding(6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            handleSelection(node, at: level)
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                            .frame(width: 200)
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(4)
                            .shadow(radius: 1)
                            .id(level)
                        }
                    }
                    .padding(.vertical)
                }
                .background(
                    GeometryReader { _ in
                        Color.clear
                            .onChange(of: columnStack.count) { _ in
                                let newCount = columnStack.count
                                if newCount > lastColumnCount {
                                    withAnimation {
                                        scrollProxy.scrollTo(newCount - 1, anchor: .trailing)
                                    }
                                }
                                lastColumnCount = newCount
                            }
                    }
                )
            }
        }
    }

    private var playerControlsView: some View {
        VStack(spacing: 8) {
            if let file = selectedFile {
                Text("Now Playing: \(file.lastPathComponent)")
                    .font(.subheadline)
                    .padding(.top, 4)

                WaveformLineView(samples: visualizer.waveformPoints)
                    .frame(height: 60)
                    .padding(.horizontal)

                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { newValue in
                            currentTime = newValue
                        }
                    ),
                    in: 0...duration,
                    onEditingChanged: { editing in
                        if editing {
                            isSeeking = true
                        } else {
                            visualizer.seek(to: currentTime)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isSeeking = false
                            }
                        }
                    }
                )

                .padding(.horizontal)

                HStack(spacing: 16) {
                    Button(action: {
                        visualizer.togglePlayback()
                        isPlaying.toggle()
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                    }

                    Button(action: {
                        visualizer.stop()
                        selectedFile = nil
                        isPlaying = false
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                    }
                }
                .padding(.bottom, 4)

                Slider(value: Binding(
                    get: { Double(currentVolume) },
                    set: {
                        currentVolume = Float($0)
                        visualizer.setVolume(currentVolume)
                    }
                ), in: 0...1)
                .padding([.horizontal, .bottom])
            } else {
                Text("Select an MP3 file")
                    .foregroundColor(.gray)
                    .padding(.top, 6)
            }

            Spacer()
        }
        .frame(minWidth: 300)
    }

    func handleSelection(_ node: FileNode, at level: Int) {
        if node.isDirectory {
            loadDirectoryContents(at: node.url, replacingFromLevel: level + 1)
        } else if node.url.pathExtension.lowercased() == "mp3" {
            selectedFile = node.url
            visualizer.play(url: node.url)
            isPlaying = true
        }
    }

    func loadDirectoryContents(at url: URL, replacingFromLevel level: Int) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let nodes: [FileNode] = contents.compactMap { url in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    return FileNode(url: url, isDirectory: isDir.boolValue)
                }
                return nil
            }
            .sorted {
                if $0.isDirectory == $1.isDirectory {
                    return $0.url.lastPathComponent.lowercased() < $1.url.lastPathComponent.lowercased()
                }
                return $0.isDirectory && !$1.isDirectory
            }

            columnStack = Array(columnStack.prefix(level)) + [nodes]
        } catch {
            print("Failed to read directory: \(error)")
        }
    }
}

#Preview {
    ContentView()
}

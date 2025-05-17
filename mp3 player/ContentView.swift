import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Audio Visualizer

class AudioVisualizerModel: ObservableObject {
    @Published var waveformPoints: [CGFloat] = Array(repeating: 0, count: 100)

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let bufferSize = 1024

    func play(url: URL) {
        stop()

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat

            engine = AVAudioEngine()
            player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)

            player.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: format) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }

            try engine.start()
            player.scheduleFile(file, at: nil)
            player.play()
        } catch {
            print("Playback error: \(error)")
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
                                .onChange(of: columnStack.map(\.count)) { _ in
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

            Divider()

            VStack(spacing: 8) {
                if let file = selectedFile {
                    Text("Now Playing: \(file.lastPathComponent)")
                        .font(.subheadline)
                        .padding(.top, 4)

                    WaveformLineView(samples: visualizer.waveformPoints)
                        .frame(height: 60)
                        .padding(.horizontal)

                    Button("Stop") {
                        visualizer.stop()
                        selectedFile = nil
                    }
                    .padding(.bottom, 8)
                } else {
                    Text("Select an MP3 file")
                        .foregroundColor(.gray)
                        .padding(.top, 6)
                }

                Spacer()
            }
            .frame(minWidth: 300)
        }
        .frame(height: 300)
        .onAppear {
            loadDirectoryContents(at: rootDirectory, replacingFromLevel: 0)
        }
    }

    func handleSelection(_ node: FileNode, at level: Int) {
        if node.isDirectory {
            loadDirectoryContents(at: node.url, replacingFromLevel: level + 1)
        } else if node.url.pathExtension.lowercased() == "mp3" {
            selectedFile = node.url
            visualizer.play(url: node.url)
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

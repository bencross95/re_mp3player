import SwiftUI
import AVFoundation
import Accelerate

// MARK: - Audio Player

class AudioPlayer: ObservableObject {
    @Published var waveformPoints: [CGFloat] = Array(repeating: 0, count: 60)
    @Published var isPlaying: Bool = false
    
    private var engine = AVAudioEngine()
    private var player: AVAudioPlayerNode?
    private let bufferSize = 1024
    private var _duration: TimeInterval = 1
    private var currentURL: URL?
    private var currentVolume: Float = 0.7

    var currentTime: TimeInterval {
        guard let node = player, node.isPlaying,
              let lastRenderTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: lastRenderTime) else { return 0 }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
    
    var duration: TimeInterval { _duration }

    func play(url: URL) {
        stop()
        currentURL = url

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat

            engine = AVAudioEngine()
            player = AVAudioPlayerNode()
            engine.attach(player!)
            engine.connect(player!, to: engine.mainMixerNode, format: format)

            player!.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: format) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }

            try engine.start()
            _duration = file.duration

            player!.scheduleFile(file, at: nil)
            player!.volume = currentVolume
            player!.play()
            isPlaying = true
        } catch {
            print("Playback error: \(error)")
        }
    }

    func stop() {
        player?.stop()
        engine.stop()
        waveformPoints = Array(repeating: 0, count: waveformPoints.count)
        isPlaying = false
    }

    func togglePlayback() {
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
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

// MARK: - File Browser

struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }
}

class FileBrowser: ObservableObject {
    @Published var currentPath: URL
    @Published var items: [FileItem] = []
    @Published var selectedIndex: Int = 0
    
    init() {
        if let savedPath = UserDefaults.standard.string(forKey: "rootDirectory"),
           let url = URL(string: savedPath),
           FileManager.default.fileExists(atPath: url.path) {
            currentPath = url
        } else {
            currentPath = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!
        }
        loadCurrentDirectory()
    }
    
    func loadCurrentDirectory() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: currentPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            items = contents.compactMap { url in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
                return FileItem(url: url, name: url.lastPathComponent, isDirectory: isDir.boolValue)
            }
            .sorted {
                if $0.isDirectory == $1.isDirectory {
                    return $0.name.lowercased() < $1.name.lowercased()
                }
                return $0.isDirectory && !$1.isDirectory
            }
            
            selectedIndex = 0
        } catch {
            print("Failed to read directory: \(error)")
        }
    }
    
    func moveUp() {
        selectedIndex = max(0, selectedIndex - 1)
    }
    
    func moveDown() {
        selectedIndex = min(items.count - 1, selectedIndex + 1)
    }
    
    func goIntoSelected() -> FileItem? {
        guard selectedIndex < items.count else { return nil }
        let item = items[selectedIndex]
        
        if item.isDirectory {
            currentPath = item.url
            UserDefaults.standard.set(currentPath.absoluteString, forKey: "rootDirectory")
            loadCurrentDirectory()
            return nil
        }
        
        // Return any audio file, not just mp3
        let audioExtensions = ["mp3", "m4a", "wav", "aiff", "flac"]
        if audioExtensions.contains(item.url.pathExtension.lowercased()) {
            return item
        }
        
        return nil
    }
    
    func goUp() {
        let parent = currentPath.deletingLastPathComponent()
        guard parent.path != currentPath.path else { return }
        currentPath = parent
        UserDefaults.standard.set(currentPath.absoluteString, forKey: "rootDirectory")
        loadCurrentDirectory()
    }
}

// MARK: - Custom Font Extension

extension View {
    func terminalFont(_ size: CGFloat) -> some View {
        self.font(.custom("NBArchitektStd-Bold", size: size))
            .textCase(.uppercase)
    }
}

// MARK: - Terminal Waveform

struct TerminalWaveform: View {
    let samples: [CGFloat]
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let barWidth = width / CGFloat(samples.count)
            
            HStack(spacing: 0) {
                ForEach(samples.indices, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: barWidth, height: max(2, samples[i] * height * 2))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var browser = FileBrowser()
    @StateObject private var player = AudioPlayer()
    @State private var nowPlaying: String = ""
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("♫")
                        .terminalFont(14)
                        .foregroundColor(.white)
                    Spacer()
                    Text(browser.currentPath.lastPathComponent)
                        .terminalFont(14)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(8)
                .background(Color.white.opacity(0.1))
                .background(WindowDragGesture())
                
                Divider().background(Color.white)
                
                // File list
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(browser.items.enumerated()), id: \.element.id) { index, item in
                                let audioExtensions = ["mp3", "m4a", "wav", "aiff", "flac"]
                                let isAudio = audioExtensions.contains(item.url.pathExtension.lowercased())
                                
                                HStack(spacing: 4) {
                                    Text(index == browser.selectedIndex ? ">" : " ")
                                        .terminalFont(14)
                                        .foregroundColor(.white)
                                    Text(item.isDirectory ? "[D]" : (isAudio ? "[♫]" : "[F]"))
                                        .terminalFont(14)
                                        .foregroundColor(item.isDirectory ? .white.opacity(0.6) : (isAudio ? .white : .white.opacity(0.3)))
                                    Text(item.name)
                                        .terminalFont(14)
                                        .foregroundColor(index == browser.selectedIndex ? .white : .white.opacity(0.8))
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == browser.selectedIndex ? Color.white.opacity(0.15) : Color.clear)
                                .id(index)
                            }
                        }
                    }
                    .onChange(of: browser.selectedIndex) { newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                
                Divider().background(Color.white)
                
                // Player controls
                VStack(spacing: 3) {
                    if !nowPlaying.isEmpty {
                        Text(nowPlaying)
                            .terminalFont(13)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                        
                        TerminalWaveform(samples: player.waveformPoints)
                            .frame(height: 25)
                            .padding(.horizontal, 8)
                        
                        HStack(spacing: 4) {
                            Text(timeString(currentTime))
                                .terminalFont(11)
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 2)
                                .overlay(
                                    GeometryReader { geo in
                                        Rectangle()
                                            .fill(Color.white)
                                            .frame(width: geo.size.width * CGFloat(currentTime / max(duration, 0.1)))
                                    }
                                )
                            Text(timeString(duration))
                                .terminalFont(11)
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                    } else {
                        Text("NO TRACK")
                            .terminalFont(13)
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.vertical, 6)
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.05))
                
                Divider().background(Color.white)
                
                // Help
                HStack(spacing: 8) {
                    Text("↑↓")
                    Text("→")
                    Text("←")
                    Text("SPC")
                    Text("ESC")
                }
                .terminalFont(10)
                .foregroundColor(.white.opacity(0.4))
                .padding(4)
            }
        }
        .focusable()
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                currentTime = player.currentTime
                duration = player.duration
            }
        }
        .onKeyPress(.upArrow) {
            browser.moveUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            browser.moveDown()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if let item = browser.goIntoSelected() {
                player.play(url: item.url)
                nowPlaying = item.name
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            browser.goUp()
            return .handled
        }
        .onKeyPress(.space) {
            player.togglePlayback()
            return .handled
        }
        .onKeyPress(.escape) {
            player.stop()
            nowPlaying = ""
            return .handled
        }
        .frame(width: 400, height: 300)
        .windowStyle()
    }
    
    func timeString(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Window Styling

struct WindowDragGesture: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = true
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func windowStyle() -> some View {
        self.onAppear {
            if let window = NSApplication.shared.windows.first {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
            }
        }
    }
}

#Preview {
    ContentView()
}

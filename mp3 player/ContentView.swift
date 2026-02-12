import SwiftUI
import AppKit

// MARK: - Custom Font Extension

extension View {
    func terminalFont(_ size: CGFloat) -> some View {
        self.font(.custom("NBArchitektStd-Bold", size: size))
            .textCase(.uppercase)
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var browser = FileBrowser()
    @StateObject private var player = AudioPlayer()
    @State private var nowPlaying: String = ""
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var hoveredIndex: Int? = nil
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: TimeInterval = 0
    @State private var displayVolume: Float = 0.7
    @State private var updateTimer: Timer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // File list
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(browser.items.enumerated()), id: \.element.id) { index, item in
                                HStack(spacing: 4) {
                                    Text(index == browser.selectedIndex ? ">" : " ")
                                        .terminalFont(14)
                                        .foregroundColor(.white)
                                    Text(item.isDirectory ? "[FOLDER]" : (item.isAudio ? "[AUDIO]" : "[F]"))
                                        .terminalFont(14)
                                        .foregroundColor(item.isDirectory ? .white.opacity(0.6) : (item.isAudio ? .white : .white.opacity(0.3)))
                                    Text(item.displayName)
                                        .terminalFont(14)
                                        .foregroundColor(index == browser.selectedIndex ? .white : .white.opacity(0.8))
                                        .lineLimit(1)
                                    Spacer()
                                    if item.isAudio, let dur = item.duration {
                                        Text(durationString(dur))
                                            .terminalFont(14)
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    index == browser.selectedIndex
                                        ? Color.white.opacity(0.15)
                                        : (hoveredIndex == index ? Color.white.opacity(0.08) : Color.clear)
                                )
                                .contentShape(Rectangle())
                                .onHover { isHovered in
                                    hoveredIndex = isHovered ? index : nil
                                }
                                .onTapGesture {
                                    if index == browser.selectedIndex {
                                        if let item = browser.goIntoSelected() {
                                            player.play(url: item.url)
                                            nowPlaying = item.displayName
                                        }
                                    } else {
                                        browser.selectByMouse(index)
                                    }
                                }
                                .contextMenu {
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                    }
                                    if item.isAudio {
                                        Button("Play") {
                                            browser.selectByMouse(index)
                                            player.play(url: item.url)
                                            nowPlaying = item.displayName
                                        }
                                    }
                                    Button("Copy Path") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(item.url.path, forType: .string)
                                    }
                                }
                                .id(index)
                            }
                        }
                    }
                    .onChange(of: browser.selectedIndex) { newIndex in
                        if browser.selectedViaKeyboard {
                            withAnimation {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }

                Divider().background(Color.white)

                // Player controls
                VStack(spacing: 3) {
                    if !nowPlaying.isEmpty {
                        Text(nowPlaying)
                            .terminalFont(14)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)

                        DotDensityMeter(samples: player.waveformPoints)
                            .frame(height: 10)
                            .padding(.horizontal, 8)

                        HStack(spacing: 4) {
                            Text(timeString(isScrubbing ? scrubTime : currentTime))
                                .terminalFont(14)

                            GeometryReader { geo in
                                let progress = (isScrubbing ? scrubTime : currentTime) / max(duration, 0.1)

                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 2)
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: geo.size.width * CGFloat(min(1, max(0, progress))), height: 2)
                                }
                                .frame(maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .highPriorityGesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            isScrubbing = true
                                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                                            scrubTime = Double(fraction) * duration
                                            currentTime = scrubTime
                                        }
                                        .onEnded { value in
                                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                                            let targetTime = Double(fraction) * duration
                                            player.seek(to: targetTime)
                                            isScrubbing = false
                                        }
                                )
                            }
                            .frame(height: 14)
                            .background(WindowDragBlocker())

                            Text(timeString(duration))
                                .terminalFont(14)
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                    } else {
                        Text("NO TRACK")
                            .terminalFont(14)
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.vertical, 6)
                    }

                    // Volume control
                    HStack(spacing: 4) {
                        Text("VOL")
                            .terminalFont(14)

                        GeometryReader { geo in
                            let volumeFraction = CGFloat(displayVolume)

                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 4)
                                Rectangle()
                                    .fill(Color.white.opacity(0.7))
                                    .frame(width: geo.size.width * volumeFraction, height: 4)
                            }
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let fraction = Float(max(0, min(1, value.location.x / geo.size.width)))
                                        displayVolume = fraction
                                        player.setVolume(fraction)
                                    }
                            )
                        }
                        .frame(height: 12)
                        .background(WindowDragBlocker())

                        Text("\(Int(displayVolume * 100))%")
                            .terminalFont(14)
                            .frame(width: 45, alignment: .trailing)
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                }
                .padding(6)
                .background(Color.white.opacity(0.05))

                Divider().background(Color.white)

                // Help
                HStack(spacing: 8) {
                    Text("↑")
                    Text("↓")
                    Text("→")
                    Text("←")
                    Text("SPC")
                    Text("ESC")
                    Text("+/-")
                }
                .terminalFont(14)
                .foregroundColor(.white.opacity(0.4))
                .padding(4)
            }
        }
        .background(WindowDragGesture())
        .focusable()
        .onAppear {
            displayVolume = player.volume
            updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                if !isScrubbing {
                    currentTime = player.currentTime
                }
                duration = player.duration
            }
        }
        .onDisappear {
            updateTimer?.invalidate()
            updateTimer = nil
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
                nowPlaying = item.displayName
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
        .onKeyPress(characters: CharacterSet(charactersIn: "=+")) { _ in
            let newVol = min(1.0, player.volume + 0.05)
            player.setVolume(newVol)
            displayVolume = newVol
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "-_")) { _ in
            let newVol = max(0.0, player.volume - 0.05)
            player.setVolume(newVol)
            displayVolume = newVol
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

    func durationString(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}

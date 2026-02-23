import SwiftUI
import AppKit

// MARK: - Custom Font Extension

extension View {
    func terminalFont(_ size: CGFloat) -> some View {
        self.font(.custom("NBArchitektStd-Bold", size: size))
            .textCase(.uppercase)
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let item: FileItem
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> FileItem?
    var onPlay: ((FileItem) -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(isSelected ? ">" : " ")
                .terminalFont(14)
                .foregroundColor(.white)
            Text(item.isDirectory ? "[FOLDER]" : (item.isAudio ? "[AUDIO]" : "[F]"))
                .terminalFont(14)
                .foregroundColor(item.isDirectory ? .white.opacity(0.5) : (item.isAudio ? .white : .white.opacity(0.2)))
            Text(item.displayName)
                .terminalFont(14)
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                .lineLimit(1)
            Spacer()
            if item.isAudio, let dur = item.duration {
                Text(FileRowView.durationString(dur))
                    .terminalFont(14)
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? Color.white.opacity(0.2)
                : (isHovered ? Color.white.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if isSelected {
                if let playItem = onDoubleTap() {
                    onPlay?(playItem)
                }
            } else {
                onTap()
            }
        }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            if item.isAudio {
                Button("Play") {
                    onTap()
                    if let playItem = onDoubleTap() {
                        onPlay?(playItem)
                    }
                }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
    }

    static func durationString(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Footer Player Bar

struct FooterPlayerBar: View {
    @ObservedObject var player: AudioPlayer
    let nowPlaying: String
    var onPrevious: () -> Void
    var onNext: () -> Void

    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: TimeInterval = 0
    @State private var updateTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Scrubber bar across full width
            GeometryReader { geo in
                let progress = (isScrubbing ? scrubTime : currentTime) / max(duration, 0.1)

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 2)
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
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
            .frame(height: 10)
            .background(WindowDragBlocker())

            // Controls row
            HStack(spacing: 0) {
                // Transport controls
                HStack(spacing: 12) {
                    Button(action: onPrevious) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)

                    Button(action: { player.togglePlayback() }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)

                    Button(action: onNext) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }

                Spacer().frame(width: 12)

                // Track name
                if !nowPlaying.isEmpty {
                    Text(nowPlaying)
                        .terminalFont(12)
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)

                    Spacer()

                    // Time
                    Text(timeString(isScrubbing ? scrubTime : currentTime))
                        .terminalFont(12)
                        .foregroundColor(.white.opacity(0.3))
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
        }
        .background(Color.white.opacity(0.05))
        .background(WindowDragBlocker())
        .onAppear {
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
    }

    private func timeString(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var browser = FileBrowser()
    @StateObject private var player = AudioPlayer()
    @State private var nowPlaying: String = ""
    @State private var alwaysOnTop: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.001).ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation header
                HStack(spacing: 2) {
                    Button(action: { browser.goBack() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(browser.canGoBack ? .white.opacity(0.7) : .white.opacity(0.15))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(!browser.canGoBack)

                    Button(action: { browser.goForward() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(browser.canGoForward ? .white.opacity(0.7) : .white.opacity(0.15))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(!browser.canGoForward)

                    Text(browser.currentPath.lastPathComponent)
                        .terminalFont(14)
                        .foregroundColor(.white.opacity(0.3))
                        .lineLimit(1)
                        .padding(.leading, 4)

                    Spacer()

                    // Always-on-top toggle
                    Button(action: { alwaysOnTop.toggle() }) {
                        Image(systemName: alwaysOnTop ? "lock.fill" : "lock.open")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(alwaysOnTop ? .white.opacity(0.9) : .white.opacity(0.3))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(alwaysOnTop ? "Unpin window" : "Pin window on top")

                    // Window controls
                    Button(action: { NSApplication.shared.keyWindow?.miniaturize(nil) }) {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Minimize")

                    Button(action: { NSApplication.shared.keyWindow?.close() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Close")
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .background(WindowDragBlocker())

                // File list (full width)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(browser.items.enumerated()), id: \.element.id) { index, item in
                                FileRowView(
                                    item: item,
                                    index: index,
                                    isSelected: index == browser.selectedIndex,
                                    onTap: { browser.selectByMouse(index) },
                                    onDoubleTap: { browser.goIntoSelected() },
                                    onPlay: { playItem in
                                        player.play(url: playItem.url)
                                        nowPlaying = playItem.displayName
                                    }
                                )
                                .id(item.id)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: browser.selectedIndex) { newIndex in
                        if browser.selectedViaKeyboard, newIndex < browser.items.count {
                            withAnimation {
                                proxy.scrollTo(browser.items[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }

                // Footer player bar
                FooterPlayerBar(
                    player: player,
                    nowPlaying: nowPlaying,
                    onPrevious: {
                        if let item = browser.previousAudioItem() {
                            player.play(url: item.url)
                            nowPlaying = item.displayName
                        }
                    },
                    onNext: {
                        if let item = browser.nextAudioItem() {
                            player.play(url: item.url)
                            nowPlaying = item.displayName
                        }
                    }
                )
            }
        }
        .background(WindowDragGesture())
        .background(AlwaysOnTopHelper(isOnTop: alwaysOnTop))
        .focusable()
        .onAppear {
            player.setupRemoteCommands()
            player.onNextTrack = {
                if let item = browser.nextAudioItem() {
                    player.play(url: item.url)
                    nowPlaying = item.displayName
                }
            }
            player.onPreviousTrack = {
                if let item = browser.previousAudioItem() {
                    player.play(url: item.url)
                    nowPlaying = item.displayName
                }
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
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "-_")) { _ in
            let newVol = max(0.0, player.volume - 0.05)
            player.setVolume(newVol)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "[")) { _ in
            browser.goBack()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "]")) { _ in
            browser.goForward()
            return .handled
        }
        .frame(minWidth: 380, minHeight: 150)
        .windowStyle()
    }
}

#Preview {
    ContentView()
}

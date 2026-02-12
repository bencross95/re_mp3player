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

// MARK: - Main View

struct ContentView: View {
    @StateObject private var browser = FileBrowser()
    @StateObject private var player = AudioPlayer()
    @State private var nowPlaying: String = ""
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 1
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: TimeInterval = 0
    @State private var displayVolume: Float = 0.7
    @State private var updateTimer: Timer?
    @State private var dragStartVolume: Float = 0.7

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
                    .disabled(!browser.canGoBack)

                    Button(action: { browser.goForward() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(browser.canGoForward ? .white.opacity(0.7) : .white.opacity(0.15))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!browser.canGoForward)

                    Text(browser.currentPath.lastPathComponent)
                        .terminalFont(10)
                        .foregroundColor(.white.opacity(0.3))
                        .lineLimit(1)
                        .padding(.leading, 4)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .background(WindowDragBlocker())

                // File list
                ScrollViewReader { proxy in
                    List(Array(browser.items.enumerated()), id: \.element.id) { index, item in
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
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .id(index)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: browser.selectedIndex) { newIndex in
                        if browser.selectedViaKeyboard {
                            withAnimation {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }

                Divider().background(Color.white.opacity(0.2))

                // Player controls
                VStack(spacing: 3) {
                    if !nowPlaying.isEmpty {
                        HStack(spacing: 4) {
                            Text(timeString(isScrubbing ? scrubTime : currentTime))
                                .terminalFont(14)

                            GeometryReader { geo in
                                let progress = (isScrubbing ? scrubTime : currentTime) / max(duration, 0.1)

                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.2))
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

                            // Volume dial
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                Circle()
                                    .trim(from: 0, to: CGFloat(displayVolume))
                                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 14, height: 14)
                            .contentShape(Circle())
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if abs(value.translation.height) < 1 && abs(value.translation.width) < 1 {
                                            dragStartVolume = displayVolume
                                        }
                                        let delta = Float(-value.translation.height / 100)
                                        let newVol = max(0, min(1, dragStartVolume + delta))
                                        displayVolume = newVol
                                        player.setVolume(newVol)
                                    }
                            )
                            .background(WindowDragBlocker())
                        }
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 8)
                    } else {
                        Text("NO TRACK")
                            .terminalFont(14)
                            .foregroundColor(.white.opacity(0.2))
                            .padding(.vertical, 6)
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.1))
            }
        }
        .background(WindowDragGesture())
        .focusable()
        .onAppear {
            displayVolume = player.volume
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
        .onKeyPress(characters: CharacterSet(charactersIn: "[")) { _ in
            browser.goBack()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "]")) { _ in
            browser.goForward()
            return .handled
        }
        .frame(minWidth: 220, minHeight: 150)
        .windowStyle()
    }

    func timeString(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

}

#Preview {
    ContentView()
}

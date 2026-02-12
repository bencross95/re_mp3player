import Foundation
import AVFoundation

let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aiff", "flac"]

struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var duration: TimeInterval?
    var artist: String?
    var title: String?

    var isAudio: Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    var displayName: String {
        if let title = title {
            return artist.map { "\($0) - \(title)" } ?? title
        }
        return name
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }
}

class FileBrowser: ObservableObject {
    @Published var currentPath: URL
    @Published var items: [FileItem] = []
    @Published var selectedIndex: Int = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    var selectedViaKeyboard: Bool = true
    private var metadataCache: [URL: (duration: TimeInterval?, artist: String?, title: String?)] = [:]
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

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
            loadMetadataForItems()
        } catch {
            print("Failed to read directory: \(error)")
        }
    }

    private func loadMetadataForItems() {
        let audioItems = items.enumerated().filter { $0.element.isAudio }

        for (index, item) in audioItems {
            if let cached = metadataCache[item.url] {
                items[index].duration = cached.duration
                items[index].artist = cached.artist
                items[index].title = cached.title
                continue
            }

            let url = item.url
            let itemIndex = index

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var fileDuration: TimeInterval?
                if let audioFile = try? AVAudioFile(forReading: url) {
                    fileDuration = audioFile.duration
                }

                var artist: String?
                var title: String?
                let asset = AVAsset(url: url)
                let semaphore = DispatchSemaphore(value: 0)

                asset.loadValuesAsynchronously(forKeys: ["commonMetadata"]) {
                    let metadata = asset.commonMetadata
                    title = AVMetadataItem.metadataItems(
                        from: metadata,
                        filteredByIdentifier: .commonIdentifierTitle
                    ).first?.stringValue
                    artist = AVMetadataItem.metadataItems(
                        from: metadata,
                        filteredByIdentifier: .commonIdentifierArtist
                    ).first?.stringValue
                    semaphore.signal()
                }
                semaphore.wait()

                DispatchQueue.main.async { [weak self] in
                    guard let self = self, itemIndex < self.items.count,
                          self.items[itemIndex].url == url else { return }
                    self.items[itemIndex].duration = fileDuration
                    self.items[itemIndex].artist = artist
                    self.items[itemIndex].title = title
                    self.metadataCache[url] = (fileDuration, artist, title)
                }
            }
        }
    }

    func moveUp() {
        selectedViaKeyboard = true
        selectedIndex = max(0, selectedIndex - 1)
    }

    func moveDown() {
        selectedViaKeyboard = true
        selectedIndex = min(items.count - 1, selectedIndex + 1)
    }

    func selectByMouse(_ index: Int) {
        selectedViaKeyboard = false
        selectedIndex = index
    }

    func nextAudioItem() -> FileItem? {
        for i in (selectedIndex + 1)..<items.count {
            if items[i].isAudio {
                selectedViaKeyboard = true
                selectedIndex = i
                return items[i]
            }
        }
        return nil
    }

    func previousAudioItem() -> FileItem? {
        for i in stride(from: selectedIndex - 1, through: 0, by: -1) {
            if items[i].isAudio {
                selectedViaKeyboard = true
                selectedIndex = i
                return items[i]
            }
        }
        return nil
    }

    func goIntoSelected() -> FileItem? {
        guard selectedIndex < items.count else { return nil }
        let item = items[selectedIndex]

        if item.isDirectory {
            navigateTo(item.url)
            return nil
        }

        if item.isAudio {
            return item
        }

        return nil
    }

    func goUp() {
        let parent = currentPath.deletingLastPathComponent()
        guard parent.path != currentPath.path else { return }
        navigateTo(parent)
    }

    private func navigateTo(_ url: URL) {
        backStack.append(currentPath)
        forwardStack.removeAll()
        currentPath = url
        UserDefaults.standard.set(currentPath.absoluteString, forKey: "rootDirectory")
        loadCurrentDirectory()
        updateNavigationState()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentPath)
        currentPath = previous
        UserDefaults.standard.set(currentPath.absoluteString, forKey: "rootDirectory")
        loadCurrentDirectory()
        updateNavigationState()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentPath)
        currentPath = next
        UserDefaults.standard.set(currentPath.absoluteString, forKey: "rootDirectory")
        loadCurrentDirectory()
        updateNavigationState()
    }

    private func updateNavigationState() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }
}

import Foundation

let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aiff", "flac"]

struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool

    var isAudio: Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url
    }
}

class FileBrowser: ObservableObject {
    @Published var currentPath: URL
    @Published var items: [FileItem] = []
    @Published var selectedIndex: Int = 0
    var selectedViaKeyboard: Bool = true

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

    func goIntoSelected() -> FileItem? {
        guard selectedIndex < items.count else { return nil }
        let item = items[selectedIndex]

        if item.isDirectory {
            currentPath = item.url
            UserDefaults.standard.set(currentPath.absoluteString, forKey: "rootDirectory")
            loadCurrentDirectory()
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
        currentPath = parent
        UserDefaults.standard.set(currentPath.absoluteString, forKey: "rootDirectory")
        loadCurrentDirectory()
    }
}

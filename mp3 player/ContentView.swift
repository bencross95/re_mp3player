import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var mp3Files: [URL] = []
    @State private var selectedFile: URL?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        
        
        HStack {
            VStack {
                Text("Loaded from ~/Music")
                    .font(.caption)
                    .padding()

                List(mp3Files, id: \.self, selection: $selectedFile) { file in
                    Text(file.lastPathComponent)
                        .onTapGesture {
                            loadMP3(url: file)
                        }
                }
                .frame(minWidth: 200)
            }

            Divider()

            VStack {
                if let file = selectedFile {
                    Text(file.lastPathComponent)
                        .font(.headline)
                        .padding()
                } else {
                    Text("Select an MP3")
                        .foregroundColor(.gray)
                        .padding()
                }

                HStack {
                    Button(isPlaying ? "Pause" : "Play") {
                        togglePlayback()
                    }
                    .disabled(audioPlayer == nil)

                    Button("pls Stop") {
                        stopPlayback()
                    }
                    .disabled(audioPlayer == nil)
                }
                .padding()

                Spacer()
            }
            .frame(minWidth: 300)
        }
        .frame(width: 600, height: 400)
        .onAppear {
            loadMP3sFromDefaultFolder()
        }
    }

    func loadMP3sFromDefaultFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultFolder = home.appendingPathComponent("Music")

        do {
            let files = try FileManager.default.contentsOfDirectory(at: defaultFolder, includingPropertiesForKeys: nil)
            self.mp3Files = files.filter { $0.pathExtension.lowercased() == "mp3" }
        } catch {
            print("Failed to load MP3s: \(error)")
        }
    }

    func loadMP3(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("Failed to play audio: \(error)")
            isPlaying = false
        }
    }

    func togglePlayback() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }
}




#Preview {
    ContentView()
}

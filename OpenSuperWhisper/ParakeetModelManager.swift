import Foundation

@MainActor
class ParakeetModelManager {
    static let shared = ParakeetModelManager()

    private let bundleID = "ru.starmel.OpenSuperWhisper"
    private let modelsDirectoryName = "parakeet-models"

    var modelsDirectory: URL {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not find Application Support directory")
        }

        let modelsURL = appSupportURL
            .appendingPathComponent(bundleID)
            .appendingPathComponent(modelsDirectoryName)

        // Create directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create models directory: \(error)")
        }

        return modelsURL
    }

    func availableModels() -> [String] {
        let fileManager = FileManager.default
        var models: [String] = []

        do {
            let repositoryURL = modelsDirectory.appendingPathComponent("mlx-community")
            let modelURLs = try fileManager.contentsOfDirectory(at: repositoryURL,
                                                               includingPropertiesForKeys: [.isDirectoryKey],
                                                               options: [.skipsHiddenFiles])

            for url in modelURLs {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    // Check if required files exist
                    let requiredFiles = ["config.json", "model.safetensors", "tokenizer.model", "tokenizer.vocab", "vocab.txt"]
                    let hasAllFiles = requiredFiles.allSatisfy { fileName in
                        fileManager.fileExists(atPath: url.appendingPathComponent(fileName).path)
                    }

                    if hasAllFiles {
                        models.append(url.lastPathComponent)
                    }
                }
            }
        } catch {
            print("❌ Failed to enumerate models: \(error)")
        }

        return models.sorted()
    }

    func modelDirectory(for repositoryID: String) -> URL {
        return modelsDirectory
            .appendingPathComponent("mlx-community")
            .appendingPathComponent(repositoryID)
    }

    func isModelDownloaded(identifier: String) -> Bool {
        let directory = modelDirectory(for: identifier)
        let requiredFiles = ["config.json", "model.safetensors", "tokenizer.model", "tokenizer.vocab", "vocab.txt"]

        return requiredFiles.allSatisfy { fileName in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
        }
    }

    func downloadModel(repositoryID: String, progressHandler: @escaping (Double) -> Void) async throws {
        // This is a placeholder implementation
        // In a real implementation, you would download the model files from HuggingFace
        // For now, we'll just simulate the download

        print("⬇️ Starting download for model: \(repositoryID)")

        let directory = modelDirectory(for: repositoryID)
        let fileManager = FileManager.default

        // Create directory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Simulate download progress
        for i in 0...10 {
            let progress = Double(i) / 10.0
            progressHandler(progress)
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }

        print("✅ Download completed for model: \(repositoryID)")
        throw NSError(domain: "ParakeetModelManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download not implemented yet"])
    }

    private init() {}
}
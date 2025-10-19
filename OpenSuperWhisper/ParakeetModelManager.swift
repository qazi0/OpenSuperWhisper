import Foundation

final class ParakeetDownloadDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    private let progressCallback: @Sendable (Double) -> Void
    private var expectedContentLength: Int64 = 0
    var completionHandler: (@Sendable (URL?, Error?) -> Void)?
    
    init(progressCallback: @escaping @Sendable (Double) -> Void) {
        self.progressCallback = progressCallback
        super.init()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        completionHandler?(location, nil)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if expectedContentLength == 0 {
            expectedContentLength = totalBytesExpectedToWrite
        }
        let progress = Double(totalBytesWritten) / Double(expectedContentLength)
        progressCallback(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler?(nil, error)
        }
    }
}

extension ParakeetDownloadDelegate: @unchecked Sendable {}

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
            print("Failed to create models directory: \(error)")
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
            print("Failed to enumerate models: \(error)")
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

    func downloadModel(repositoryID: String, progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        print("Starting download for model: \(repositoryID)")

        let directory = modelDirectory(for: repositoryID)
        let fileManager = FileManager.default

        // Check if model already exists
        if isModelDownloaded(identifier: repositoryID) {
            print("Model already exists at: \(directory.path)")
            progressHandler(1.0)
            return
        }

        // Create directory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // List of required files to download from HuggingFace
        let requiredFiles = [
            "config.json",
            "model.safetensors",
            "tokenizer.model",
            "tokenizer.vocab",
            "vocab.txt"
        ]
        
        let totalFiles = Double(requiredFiles.count)
        var completedFiles = 0.0
        
        // Download each file
        for fileName in requiredFiles {
            let fileURL = directory.appendingPathComponent(fileName)
            
            // Skip if file already exists
            if fileManager.fileExists(atPath: fileURL.path) {
                completedFiles += 1.0
                let overallProgress = completedFiles / totalFiles
                progressHandler(overallProgress)
                print("File already exists: \(fileName)")
                continue
            }
            
            // Construct HuggingFace download URL
            let downloadURLString = "https://huggingface.co/\(repositoryID)/resolve/main/\(fileName)"
            guard let downloadURL = URL(string: downloadURLString) else {
                throw NSError(domain: "ParakeetModelManager", code: -1, 
                            userInfo: [NSLocalizedDescriptionKey: "Invalid download URL for \(fileName)"])
            }
            
            print("Downloading \(fileName) from \(downloadURLString)")
            
            // Download the file
            let currentCompletedFiles = completedFiles
            try await downloadFile(from: downloadURL, to: fileURL) { fileProgress in
                // Calculate overall progress: completed files + current file progress
                let overallProgress = (currentCompletedFiles + fileProgress) / totalFiles
                progressHandler(overallProgress)
            }
            
            completedFiles += 1.0
            print("Downloaded: \(fileName)")
        }
        
        print("Download completed for model: \(repositoryID)")
        progressHandler(1.0)
    }
    
    private func downloadFile(from url: URL, to destination: URL, progressCallback: @escaping @Sendable (Double) -> Void) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = ParakeetDownloadDelegate(progressCallback: progressCallback)
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForResource = 1800 // 30 minutes for large model files
            
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
            
            let downloadTask = session.downloadTask(with: url)
            
            delegate.completionHandler = { location, error in
                if let error = error {
                    print("Download failed with error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let location = location else {
                    let error = NSError(domain: "ParakeetModelManager", code: -2, 
                                      userInfo: [NSLocalizedDescriptionKey: "No download location received"])
                    continuation.resume(throwing: error)
                    return
                }
                
                do {
                    // Move downloaded file to destination
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: location, to: destination)
                    continuation.resume(returning: ())
                } catch {
                    print("Failed to move downloaded file: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            
            downloadTask.resume()
        }
    }

    private init() {}
}
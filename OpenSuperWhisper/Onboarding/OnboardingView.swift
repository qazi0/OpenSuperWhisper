//
//  OnboardingView.swift
//  OpenSuperWhisper
//
//  Created by user on 08.02.2025.
//

import Foundation
import SwiftUI

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var selectedLanguage: String {
        didSet {
            AppPreferences.shared.whisperLanguage = selectedLanguage
        }
    }

    @Published var selectedModel: DownloadableModel?
    @Published var models: [DownloadableModel]
    @Published var isDownloadingAny: Bool = false

    private let whisperModelManager = WhisperModelManager.shared
    private let parakeetModelManager = ParakeetModelManager.shared

    init(applySystemLanguage: Bool = true) {
        self.models = []
        let preferences = AppPreferences.shared

        if applySystemLanguage {
            let systemLanguage = LanguageUtil.getSystemLanguage()
            preferences.whisperLanguage = systemLanguage
            self.selectedLanguage = systemLanguage
        } else {
            self.selectedLanguage = preferences.whisperLanguage
        }

        loadModels()
        selectModelFromPreferences()

        if selectedModel == nil, let defaultModel = models.first(where: { $0.name == "Turbo V3 large" }) {
            self.selectedModel = defaultModel
        }
    }

    func setLanguage(_ newLanguage: String) {
        selectedLanguage = newLanguage
    }

    func loadModels() {
        models = availableModels.map { model in
            var updatedModel = model
            switch model.vendor {
            case .whisper:
                if let filename = model.url?.lastPathComponent {
                    updatedModel.isDownloaded = whisperModelManager.isModelDownloaded(name: filename)
                }
            case .parakeet:
                if let repoID = model.repositoryID {
                    updatedModel.isDownloaded = parakeetModelManager.isModelDownloaded(identifier: repoID)
                }
            }
            return updatedModel
        }
    }

    func selectModelFromPreferences() {
        let preferences = AppPreferences.shared
        guard let savedPath = preferences.selectedModelPath else { return }

        if let existing = models.first(where: { model in
            guard model.vendor == preferences.selectedModelVendor else { return false }
            switch model.vendor {
            case .whisper:
                guard let filename = model.url?.lastPathComponent else { return false }
                let localPath = WhisperModelManager.shared.modelsDirectory
                    .appendingPathComponent(filename)
                    .path
                return localPath == savedPath
            case .parakeet:
                guard let repoID = model.repositoryID else { return false }
                return ParakeetModelManager.shared.modelDirectory(for: repoID).path == savedPath
            }
        }) {
            self.selectedModel = existing
        }
    }

    func applySelectedModelPreferences() {
        guard let selectedModel = selectedModel, selectedModel.isDownloaded else { return }

        switch selectedModel.vendor {
        case .whisper:
            guard let filename = selectedModel.url?.lastPathComponent else { return }
            let modelPath = whisperModelManager.modelsDirectory
                .appendingPathComponent(filename)
                .path
            AppPreferences.shared.selectedModelPath = modelPath
            AppPreferences.shared.selectedModelVendor = .whisper
        case .parakeet:
            guard let repoID = selectedModel.repositoryID else { return }
            let directory = parakeetModelManager.modelDirectory(for: repoID)
            AppPreferences.shared.selectedModelPath = directory.path
            AppPreferences.shared.selectedModelVendor = .parakeet
        }
    }

    @MainActor
    func downloadSelectedModel() async throws {
        guard let model = selectedModel, !model.isDownloaded else { return }

        guard !isDownloadingAny else { return }
        isDownloadingAny = true

        do {
            // Find the index of the model we're downloading
            guard let modelIndex = models.firstIndex(where: { $0.name == model.name }) else {
                isDownloadingAny = false
                return
            }

            switch model.vendor {
            case .whisper:
                guard let downloadURL = model.url else {
                    throw NSError(domain: "Onboarding", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL"])
                }
                
                let filename = downloadURL.lastPathComponent
                
                try await whisperModelManager.downloadModel(url: downloadURL, name: filename) { [weak self] progress in
                    DispatchQueue.main.async {
                        self?.models[modelIndex].downloadProgress = progress
                        if progress >= 1.0 {
                            self?.models[modelIndex].isDownloaded = true
                            self?.isDownloadingAny = false
                            // Update the model path after successful download
                            if let modelPath = self?.whisperModelManager.modelsDirectory.appendingPathComponent(filename).path {
                                AppPreferences.shared.selectedModelPath = modelPath
                                AppPreferences.shared.selectedModelVendor = .whisper
                                print("Model path after download: \(modelPath)")
                            }
                        }
                    }
                }
            case .parakeet:
                guard let repoID = model.repositoryID else {
                    throw NSError(domain: "Onboarding", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing repository identifier"])
                }

                // Reference the shared manager directly to avoid crossing actor boundaries
                let manager = ParakeetModelManager.shared
                try await manager.downloadModel(repositoryID: repoID) { [weak self] progress in
                    DispatchQueue.main.async {
                        self?.models[modelIndex].downloadProgress = progress

                        if progress >= 1.0 {
                            self?.models[modelIndex].isDownloaded = true
                            self?.isDownloadingAny = false

                            let directory = ParakeetModelManager.shared.modelDirectory(for: repoID)
                            AppPreferences.shared.selectedModelPath = directory.path
                            AppPreferences.shared.selectedModelVendor = .parakeet
                            print("Parakeet model downloaded to: \(directory.path)")
                        }
                    }
                }
            }
        } catch {
            print("Failed to download model: \(error)")
            if let modelIndex = models.firstIndex(where: { $0.name == model.name }) {
                models[modelIndex].downloadProgress = 0
            }
            isDownloadingAny = false
            throw error
        }
    }
}

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @EnvironmentObject private var appState: AppState
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            VStack(alignment: .leading) {
                Text("Welcome to OpenSuperWhisper!")
                    .font(.title)
                    .padding()

                // Language selection
                VStack(alignment: .leading) {
                    Text("Choose speech language")
                        .font(.headline)
                    Picker("", selection: $viewModel.selectedLanguage) {
                        ForEach(LanguageUtil.availableLanguages, id: \.self) { code in
                            Text(LanguageUtil.languageNames[code] ?? code)
                                .tag(code)
                        }
                    }
                    .frame(width: 200)
                }
                .padding()

                VStack(alignment: .leading) {
                    Text("Choose Model")
                        .font(.headline)

                    Text("The model is designed to transcribe audio into text. It is a powerful tool that can be used to transcribe audio into text.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                .padding()

                ModelListView(viewModel: viewModel)

                HStack {
                    Spacer()
                    Button(action: {
                        handleNextButtonTap()
                    }) {
                        Text("Next")
                    }
                    .padding()
                    .disabled(viewModel.selectedModel == nil || viewModel.isDownloadingAny)
                }
            }
            .padding()
            .frame(width: 450, height: 650)
            .alert("Download Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func handleNextButtonTap() {
        guard let selectedModel = viewModel.selectedModel else { return }

        if selectedModel.isDownloaded {
            viewModel.applySelectedModelPreferences()
            // If model is already downloaded, proceed immediately
            appState.hasCompletedOnboarding = true
        } else {
            // If model needs to be downloaded, start download
            Task {
                do {
                    try await viewModel.downloadSelectedModel()
                    // After successful download, proceed to the main app
                    await MainActor.run {
                        appState.hasCompletedOnboarding = true
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
}

struct DownloadableModel: Identifiable, Equatable {
    let id = UUID() // Add an ID for Identifiable conformance
    let name: String
    var isDownloaded: Bool
    let url: URL?
    let repositoryID: String?
    let vendor: SpeechModelVendor
    let size: Int
    var speedRate: Int
    var accuracyRate: Int
    var downloadProgress: Double = 0.0 // 0 to 1

    var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB] // More appropriate units
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true // Let the formatter decide
        return formatter.string(fromByteCount: Int64(size) * 1000000) // Convert to MB as your size is in MB
    }

    init(
        name: String,
        isDownloaded: Bool,
        url: URL? = nil,
        repositoryID: String? = nil,
        vendor: SpeechModelVendor,
        size: Int,
        speedRate: Int,
        accuracyRate: Int
    ) {
        self.name = name
        self.isDownloaded = isDownloaded
        self.url = url
        self.repositoryID = repositoryID
        self.vendor = vendor
        self.size = size
        self.speedRate = speedRate
        self.accuracyRate = accuracyRate
    }
    static func == (lhs: DownloadableModel, rhs: DownloadableModel) -> Bool {
        lhs.id == rhs.id
    }
    
    @MainActor
    func isDifferentFromPreference() -> Bool {
        let prefs = AppPreferences.shared
        guard let savedPath = prefs.selectedModelPath else { return true }
        guard prefs.selectedModelVendor == vendor else { return true }
        
        switch vendor {
        case .whisper:
            guard let filename = url?.lastPathComponent else { return true }
            let localPath = WhisperModelManager.shared.modelsDirectory
                .appendingPathComponent(filename)
                .path
            return localPath != savedPath
        case .parakeet:
            guard let repoID = repositoryID else { return true }
            let localPath = ParakeetModelManager.shared.modelDirectory(for: repoID).path
            return localPath != savedPath
        }
    }
}

let availableModels = [

    DownloadableModel(
        name: "Turbo V3 large",
        isDownloaded: false,
        url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!,
        repositoryID: nil,
        vendor: .whisper,
        size: 1624,
        speedRate: 60,
        accuracyRate: 100
    ),
    DownloadableModel(
        name: "Turbo V3 medium",
        isDownloaded: false,
        url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true")!,
        repositoryID: nil,
        vendor: .whisper,
        size: 874,
        speedRate: 70,
        accuracyRate: 70
    ),
    DownloadableModel(
        name: "Turbo V3 small",
        isDownloaded: false,
        url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true")!,
        repositoryID: nil,
        vendor: .whisper,
        size: 574,
        speedRate: 100,
        accuracyRate: 60
    ),
    DownloadableModel(
        name: "Parakeet-TDT-0.6B-v2 (EN)",
        isDownloaded: false,
        url: nil,
        repositoryID: "mlx-community/parakeet-tdt-0.6b-v2",
        vendor: .parakeet,
        size: 2510,
        speedRate: 90,
        accuracyRate: 80
    ),
    DownloadableModel(
        name: "Parakeet-TDT-0.6B-v3",
        isDownloaded: false,
        url: nil,
        repositoryID: "mlx-community/parakeet-tdt-0.6b-v3",
        vendor: .parakeet,
        size: 2510,
        speedRate:90,
        accuracyRate: 95
    )
]

// UI for the model
struct DownloadableItemView: View {
    @Binding var model: DownloadableModel
    @EnvironmentObject var viewModel: OnboardingViewModel
    var onDoubleClick: ((DownloadableModel) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 12) {
                        Text(model.name)
                            .font(.headline)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("\(model.vendor.displayName) model")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        VStack {
                            Text("Accuracy")
                            ProgressView(value: Double(model.accuracyRate), total: 100)
                                .progressViewStyle(LinearProgressViewStyle())
                                .frame(width: 64, height: 4)
                        }

                        VStack {
                            Text("Speed")
                            ProgressView(value: Double(model.speedRate), total: 100)
                                .progressViewStyle(LinearProgressViewStyle())
                                .frame(width: 64, height: 4)
                        }
                    }

                    Text(model.sizeString)
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    if model.name == "Turbo V3 large" {
                        Text("Recommended!")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                // Download status indicator
                if model.isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if model.downloadProgress > 0 && model.downloadProgress < 1 {
                    VStack(spacing: 4) {
                        ProgressView(value: model.downloadProgress)
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(width: 30, height: 30)
                    }
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.gray)
                        .imageScale(.large)
                }
            }
            .padding(16)
        }
        .frame(width: 400)
        .padding(.vertical, 8)
        .background(model.name == viewModel.selectedModel?.name ? Color.gray.opacity(0.3) : Color.clear)
        .cornerRadius(16)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double-click to activate model
            if model.isDownloaded {
                viewModel.selectedModel = model
                onDoubleClick?(model)
            }
        }
        .onTapGesture {
            // Single-click to select model
            viewModel.selectedModel = model
        }
    }
}

struct ModelListView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var onDoubleClick: ((DownloadableModel) -> Void)?

    var body: some View {
        ScrollView {
            VStack {
                ForEach($viewModel.models) { $model in
                    DownloadableItemView(model: $model, onDoubleClick: onDoubleClick)
                        .environmentObject(viewModel)
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
}

#Preview {
    ModelListView(viewModel: OnboardingViewModel())
}

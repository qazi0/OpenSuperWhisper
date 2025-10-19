import AppKit
import Carbon
import Combine
import Foundation
import KeyboardShortcuts
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var selectedModel: LocalSpeechModel? {
        didSet {
            guard let model = selectedModel else { return }
            AppPreferences.shared.selectedModelPath = model.path.path
            AppPreferences.shared.selectedModelVendor = model.vendor
        }
    }

    @Published var availableModels: [LocalSpeechModel] = []
    @Published var downloadableModels: [DownloadableModel] = []
    @Published var isDownloadingAny: Bool = false
    @Published var selectedLanguage: String {
        didSet {
            AppPreferences.shared.whisperLanguage = selectedLanguage
        }
    }

    @Published var translateToEnglish: Bool {
        didSet {
            AppPreferences.shared.translateToEnglish = translateToEnglish
        }
    }

    @Published var suppressBlankAudio: Bool {
        didSet {
            AppPreferences.shared.suppressBlankAudio = suppressBlankAudio
        }
    }

    @Published var showTimestamps: Bool {
        didSet {
            AppPreferences.shared.showTimestamps = showTimestamps
        }
    }
    
    @Published var temperature: Double {
        didSet {
            AppPreferences.shared.temperature = temperature
        }
    }

    @Published var noSpeechThreshold: Double {
        didSet {
            AppPreferences.shared.noSpeechThreshold = noSpeechThreshold
        }
    }

    @Published var initialPrompt: String {
        didSet {
            AppPreferences.shared.initialPrompt = initialPrompt
        }
    }

    @Published var useBeamSearch: Bool {
        didSet {
            AppPreferences.shared.useBeamSearch = useBeamSearch
        }
    }

    @Published var beamSize: Int {
        didSet {
            AppPreferences.shared.beamSize = beamSize
        }
    }

    @Published var debugMode: Bool {
        didSet {
            AppPreferences.shared.debugMode = debugMode
        }
    }
    
    @Published var playSoundOnRecordStart: Bool {
        didSet {
            AppPreferences.shared.playSoundOnRecordStart = playSoundOnRecordStart
        }
    }
    
    @Published var useAsianAutocorrect: Bool {
        didSet {
            AppPreferences.shared.useAsianAutocorrect = useAsianAutocorrect
        }
    }
    
    init() {
        let prefs = AppPreferences.shared
        self.selectedLanguage = prefs.whisperLanguage
        self.translateToEnglish = prefs.translateToEnglish
        self.suppressBlankAudio = prefs.suppressBlankAudio
        self.showTimestamps = prefs.showTimestamps
        self.temperature = prefs.temperature
        self.noSpeechThreshold = prefs.noSpeechThreshold
        self.initialPrompt = prefs.initialPrompt
        self.useBeamSearch = prefs.useBeamSearch
        self.beamSize = prefs.beamSize
        self.debugMode = prefs.debugMode
        self.playSoundOnRecordStart = prefs.playSoundOnRecordStart
        self.useAsianAutocorrect = prefs.useAsianAutocorrect
        
        loadAvailableModels()
        initializeDownloadableModels()
    }
    
    func loadAvailableModels() {
        let whisperModels = WhisperModelManager.shared
            .getAvailableModels()
            .map { url in
                LocalSpeechModel(
                    name: url.lastPathComponent,
                    vendor: .whisper,
                    path: url,
                    repositoryID: nil
                )
            }
        
        let parakeetModels: [LocalSpeechModel] = ParakeetModelManager.shared.availableModels()
            .map { modelName -> LocalSpeechModel in
                let directory = ParakeetModelManager.shared.modelDirectory(for: modelName)
                return LocalSpeechModel(
                    name: modelName,
                    vendor: .parakeet,
                    path: directory,
                    repositoryID: modelName
                )
            }

        let combined = (whisperModels + parakeetModels).sorted { $0.name < $1.name }
        availableModels = combined
        
        let prefs = AppPreferences.shared
        if let savedPath = prefs.selectedModelPath,
           let existing = combined.first(where: { $0.path.path == savedPath })
        {
            if selectedModel?.path != existing.path {
                selectedModel = existing
            }
        } else if selectedModel == nil {
            selectedModel = combined.first
        }
    }

    private func initializeDownloadableModels() {
        let onboardingViewModel = OnboardingViewModel(applySystemLanguage: false)
        onboardingViewModel.loadModels()
        onboardingViewModel.selectModelFromPreferences()
        downloadableModels = onboardingViewModel.models
        synchronizeDownloadState()
    }

    func refreshDownloadableModels() {
        initializeDownloadableModels()
    }

    private func synchronizeDownloadState() {
        let prefs = AppPreferences.shared
        guard let savedPath = prefs.selectedModelPath else { return }

        for index in downloadableModels.indices {
            let model = downloadableModels[index]

            switch model.vendor {
            case .whisper:
                if let filename = model.url?.lastPathComponent {
                    let path = WhisperModelManager.shared.modelsDirectory
                        .appendingPathComponent(filename)
                        .path
                    if path == savedPath {
                        downloadableModels[index].isDownloaded = true
                    }
                }
            case .parakeet:
                if let repoID = model.repositoryID {
                    let path = ParakeetModelManager.shared.modelDirectory(for: repoID).path
                    if path == savedPath {
                        downloadableModels[index].isDownloaded = true
                    }
                }
            }
        }
    }

    func handleDownloadCompletion(for model: DownloadableModel) {
        switch model.vendor {
        case .whisper:
            guard let filename = model.url?.lastPathComponent else { return }
            let path = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(filename)
            let localModel = LocalSpeechModel(name: filename, vendor: .whisper, path: path, repositoryID: nil)
            selectedModel = localModel
        case .parakeet:
            guard let repoID = model.repositoryID else { return }
            let directory = ParakeetModelManager.shared.modelDirectory(for: repoID)
            let localModel = LocalSpeechModel(name: repoID, vendor: .parakeet, path: directory, repositoryID: repoID)
            selectedModel = localModel
        }

        loadAvailableModels()
        initializeDownloadableModels()
    }
}

struct Settings {
    var selectedLanguage: String
    var translateToEnglish: Bool
    var suppressBlankAudio: Bool
    var showTimestamps: Bool
    var temperature: Double
    var noSpeechThreshold: Double
    var initialPrompt: String
    var useBeamSearch: Bool
    var beamSize: Int
    var useAsianAutocorrect: Bool

    @MainActor
    init() {
        let prefs = AppPreferences.shared
        self.selectedLanguage = prefs.whisperLanguage
        self.translateToEnglish = prefs.translateToEnglish
        self.suppressBlankAudio = prefs.suppressBlankAudio
        self.showTimestamps = prefs.showTimestamps
        self.temperature = prefs.temperature
        self.noSpeechThreshold = prefs.noSpeechThreshold
        self.initialPrompt = prefs.initialPrompt
        self.useBeamSearch = prefs.useBeamSearch
        self.beamSize = prefs.beamSize
        self.useAsianAutocorrect = prefs.useAsianAutocorrect
    }
}

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var modelSelectionViewModel = OnboardingViewModel(applySystemLanguage: false)
    @Environment(\.dismiss) var dismiss
    @State private var isRecordingNewShortcut = false
    @State private var selectedTab = 0
    @State private var previousModel: LocalSpeechModel?
    @State private var showModelDownloadError = false
    @State private var modelDownloadErrorMessage = ""
    
    var body: some View {
        TabView(selection: $selectedTab) {

             // Shortcut Settings
            shortcutSettings
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag(0)
            // Model Settings
            modelSettings
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }
                .tag(1)
            
            // Transcription Settings
            transcriptionSettings
                .tabItem {
                    Label("Transcription", systemImage: "text.bubble")
                }
                .tag(2)
            
            // Advanced Settings
            advancedSettings
                .tabItem {
                    Label("Advanced", systemImage: "gear")
                }
                .tag(3)
            }
        .padding()
        .frame(width: 550)
        .background(Color(.windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Done") {
                    finalizeSelectionAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .onAppear {
            previousModel = viewModel.selectedModel
            modelSelectionViewModel.loadModels()
            modelSelectionViewModel.selectModelFromPreferences()
        }
        .alert("Download Error", isPresented: $showModelDownloadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(modelDownloadErrorMessage)
        }
    }
    
    private var canSetActiveModel: Bool {
        guard let selected = modelSelectionViewModel.selectedModel else { return false }
        guard selected.isDownloaded else { return false }

        return selected.isDifferentFromPreference()
    }

    private func updatePreferenceSelection(using model: DownloadableModel) {
        if model.isDownloaded {
            modelSelectionViewModel.applySelectedModelPreferences()
            viewModel.loadAvailableModels()
            reloadTranscriptionModelIfNeeded(with: model)
        }
    }

    private func onSetActiveModel() {
        guard let model = modelSelectionViewModel.selectedModel, model.isDownloaded else { return }

        updatePreferenceSelection(using: model)
        modelSelectionViewModel.loadModels()
        modelSelectionViewModel.selectModelFromPreferences()
    }

    private func finalizeSelectionAndDismiss() {
        if let model = modelSelectionViewModel.selectedModel, model.isDownloaded {
            reloadTranscriptionModelIfNeeded(with: model)
        }
        dismiss()
    }

    private func reloadTranscriptionModelIfNeeded(with model: DownloadableModel) {
        switch model.vendor {
        case .whisper:
            guard let filename = model.url?.lastPathComponent else { return }
            let path = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(filename)
            TranscriptionService.shared.reloadModel(with: path.path)
        case .parakeet:
            guard let repoID = model.repositoryID else { return }
            let directory = ParakeetModelManager.shared.modelDirectory(for: repoID)
            TranscriptionService.shared.reloadModel(with: directory.path)
        }
    }

    private var modelSettings: some View {
        Form {
            Section {
                modelSettingsContent
            }
        }
        .padding()
    }

    private var modelSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Whisper Model")
                .font(.headline)
                .foregroundColor(.primary)

            modelPickerView

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Manage Models")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ModelListView(viewModel: modelSelectionViewModel) { model in
                    // Handle double-click activation
                    if model.isDownloaded {
                        updatePreferenceSelection(using: model)
                        modelSelectionViewModel.loadModels()
                        modelSelectionViewModel.selectModelFromPreferences()
                    }
                }
                .frame(height: 300)

                HStack(spacing: 12) {
                    Button("Download Selected") {
                        Task {
                            do {
                                try await modelSelectionViewModel.downloadSelectedModel()
                                modelSelectionViewModel.applySelectedModelPreferences()
                                viewModel.loadAvailableModels()
                                modelSelectionViewModel.loadModels()
                                modelSelectionViewModel.selectModelFromPreferences()
                            } catch {
                                await MainActor.run {
                                    modelDownloadErrorMessage = error.localizedDescription
                                    showModelDownloadError = true
                                }
                            }
                        }
                    }
                    .disabled(modelSelectionViewModel.selectedModel == nil || modelSelectionViewModel.selectedModel?.isDownloaded == true || modelSelectionViewModel.isDownloadingAny)

                    Button("Set Active Model") {
                        onSetActiveModel()
                    }
                    .disabled(!canSetActiveModel)

                    if modelSelectionViewModel.isDownloadingAny {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            directoriesView

            downloadLinksView
        }
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelPickerView: some View {
        Picker("Model", selection: $viewModel.selectedModel) {
            ForEach(viewModel.availableModels) { model in
                Text("\(model.name) (\(model.vendor.displayName))")
                    .tag(model as LocalSpeechModel?)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var directoriesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            whisperDirectoryView
            parakeetDirectoryView
        }
        .padding(.top, 8)
    }

    private var whisperDirectoryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Models Directory:")
                    .font(.subheadline)
                Spacer()
                Button(action: {
                    NSWorkspace.shared.open(WhisperModelManager.shared.modelsDirectory)
                }) {
                    Label("Open Folder", systemImage: "folder")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .help("Open models directory")
            }
            Text(WhisperModelManager.shared.modelsDirectory.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(6)
        }
    }

    private var parakeetDirectoryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Parakeet Directory:")
                    .font(.subheadline)
                Spacer()
                Button(action: {
                    NSWorkspace.shared.open(ParakeetModelManager.shared.modelsDirectory)
                }) {
                    Label("Open Folder", systemImage: "folder")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .help("Open Parakeet models directory")
            }

            Text(ParakeetModelManager.shared.modelsDirectory.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(6)
        }
    }

    private var downloadLinksView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To display other models in the list, you need to download a ggml bin file and place it in the models folder. Then restart the application.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link("Download models here", destination: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/tree/main")!)
                .font(.caption)

            Link("Download Parakeet models", destination: URL(string: "https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3")!)
                .font(.caption)
        }
        .padding(.top, 8)
    }
    
    private var transcriptionSettings: some View {
        Form {
            VStack(spacing: 20) {
                // Language Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Language Settings")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcription Language")
                            .font(.subheadline)
                        
                        Picker("Language", selection: $viewModel.selectedLanguage) {
                            ForEach(LanguageUtil.availableLanguages, id: \.self) { code in
                                Text(LanguageUtil.languageNames[code] ?? code)
                                    .tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Toggle(isOn: $viewModel.translateToEnglish) {
                            Text("Translate to English")
                                .font(.subheadline)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                        .padding(.top, 4)
                        
                        if ["zh", "ja", "ko"].contains(viewModel.selectedLanguage) {
                            Toggle(isOn: $viewModel.useAsianAutocorrect) {
                                Text("Use Asian Autocorrect")
                                    .font(.subheadline)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                            .padding(.top, 4)
                        }
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Output Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Output Options")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $viewModel.showTimestamps) {
                            Text("Show Timestamps")
                                .font(.subheadline)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                        
                        Toggle(isOn: $viewModel.suppressBlankAudio) {
                            Text("Suppress Blank Audio")
                                .font(.subheadline)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Initial Prompt
                VStack(alignment: .leading, spacing: 16) {
                    Text("Initial Prompt")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $viewModel.initialPrompt)
                            .frame(height: 60)
                            .padding(6)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        
                        Text("Optional text to guide the model's transcription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Transcriptions Directory
                VStack(alignment: .leading, spacing: 16) {
                    Text("Transcriptions Directory")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Directory:")
                                .font(.subheadline)
                            Spacer()
                            Button(action: {
                                NSWorkspace.shared.open(Recording.recordingsDirectory)
                            }) {
                                Label("Open Folder", systemImage: "folder")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .help("Open transcriptions directory")
                        }
                        
                        Text(Recording.recordingsDirectory.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(.textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }
    
    private var advancedSettings: some View {
        Form {
            VStack(spacing: 20) {
                // Decoding Strategy
                VStack(alignment: .leading, spacing: 16) {
                    Text("Decoding Strategy")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $viewModel.useBeamSearch) {
                            Text("Use Beam Search")
                                .font(.subheadline)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                        .help("Beam search can provide better results but is slower")
                        
                        if viewModel.useBeamSearch {
                            HStack {
                                Text("Beam Size:")
                                    .font(.subheadline)
                                Spacer()
                                Stepper("\(viewModel.beamSize)", value: $viewModel.beamSize, in: 1...10)
                                    .help("Number of beams to use in beam search")
                                    .frame(width: 120)
                            }
                            .padding(.leading, 24)
                        }
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Model Parameters
                VStack(alignment: .leading, spacing: 16) {
                    Text("Model Parameters")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Temperature:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.temperature))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $viewModel.temperature, in: 0.0...1.0, step: 0.1)
                                .help("Higher values make the output more random")
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("No Speech Threshold:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.noSpeechThreshold))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $viewModel.noSpeechThreshold, in: 0.0...1.0, step: 0.1)
                                .help("Threshold for detecting speech vs. silence")
                        }
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Debug Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Debug Options")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Toggle(isOn: $viewModel.debugMode) {
                        Text("Debug Mode")
                            .font(.subheadline)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                    .help("Enable additional logging and debugging information")
                }
                .padding()
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }
    
    private var shortcutSettings: some View {
        Form {
            VStack(spacing: 20) {
                // Recording Shortcut
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Shortcut")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Toggle record:")
                                .font(.subheadline)
                            Spacer()
                            KeyboardShortcuts.Recorder("", name: .toggleRecord)
                                .frame(width: 120)
                        }
                        
                        if isRecordingNewShortcut {
                            Text("Press your new shortcut combination...")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                                .padding(.vertical, 4)
                        }
                        
                        Toggle(isOn: $viewModel.playSoundOnRecordStart) {
                            Text("Play sound when recording starts")
                                .font(.subheadline)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                        .help("Play a notification sound when recording begins")
                        .padding(.top, 4)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Instructions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Instructions")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("Press any key combination to set as the recording shortcut")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "2.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("The shortcut will work even when the app is in the background")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "3.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("Recommended to use Command (⌘) or Option (⌥) key combinations")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }
}

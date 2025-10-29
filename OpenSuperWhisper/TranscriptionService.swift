@preconcurrency import AVFoundation
@preconcurrency import Foundation
import ParakeetMLX
import MLX

@preconcurrency import ObjectiveC

@MainActor
@preconcurrency
class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()
    
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var currentSegment = ""
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Float = 0.0
    
    private var context: MyWhisperContext?
    private var parakeetModel: ParakeetTDT?
    private var loadedModelVendor: SpeechModelVendor?
    private var totalDuration: Float = 0.0
    private var transcriptionTask: Task<String, Error>? = nil
    private var isCancelled = false
    private var abortFlag: UnsafeMutablePointer<Bool>? = nil
    
    init() {
        loadModel()
    }
    
    func cancelTranscription() {
        isCancelled = true
        
        // Set the abort flag to true to signal the whisper processing to stop
        if let abortFlag = abortFlag {
            abortFlag.pointee = true
        }
        
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        // Reset state
        isTranscribing = false
        currentSegment = ""
        progress = 0.0
        isCancelled = false
    }
    
    private func loadModel() {
        print("Loading model")
        guard let modelPath = AppPreferences.shared.selectedModelPath else {
            print("No model path set in preferences")
            return
        }
        let vendor = AppPreferences.shared.selectedModelVendor
        print("Model path: \(modelPath)")
        print("Model vendor: \(vendor.displayName)")
        isLoading = true

        // Capture cache directory on main actor to avoid cross-actor access later
        let cacheDirectory = ParakeetModelManager.shared.modelsDirectory

        Task(priority: .userInitiated) {
            switch vendor {
            case .whisper:
                let params = WhisperContextParams()
                let newContext = MyWhisperContext.initFromFile(path: modelPath, params: params)

                await MainActor.run {
                    let service = TranscriptionService.shared
                    service.context = newContext
                    service.parakeetModel = nil
                    service.loadedModelVendor = .whisper
                    service.isLoading = false
                    print("Whisper model loaded successfully")
                }
            case .parakeet:
                print("Loading Parakeet model from: \(modelPath)")
                do {
                    let model = try await loadParakeetModel(
                        from: modelPath,
                        dtype: .float16,
                        cacheDirectory: cacheDirectory
                    )

                    // Ensure the model runs in evaluation mode for stable BatchNorm behavior
                    // and to avoid any training-mode randomness.
                    model.train(false)

                    await MainActor.run {
                        let service = TranscriptionService.shared
                        service.parakeetModel = model
                        service.context = nil
                        service.loadedModelVendor = .parakeet
                        service.isLoading = false
                        service.progress = 0.0
                        print("Parakeet model loaded successfully")
                        print("Model config: sample_rate=\(model.preprocessConfig.sampleRate), features=\(model.preprocessConfig.features), normalize=\(model.preprocessConfig.normalize)")
                        print("Model vocabulary size: \(model.vocabulary.count)")
                        print("Model durations: \(model.durations.count) values")
                    }
                } catch {
                    await MainActor.run {
                        let service = TranscriptionService.shared
                        service.parakeetModel = nil
                        service.loadedModelVendor = nil
                        service.isLoading = false
                        print("Failed to load Parakeet model: \(error)")
                        print("Error details: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func reloadModel(with path: String) {
        print("Reloading model")
        print("New model path: \(path)")
        isLoading = true

        // Capture main-actor values before detaching
        let cacheDirectory = ParakeetModelManager.shared.modelsDirectory
        let vendor = AppPreferences.shared.selectedModelVendor
        print("Model vendor: \(vendor.displayName)")

        Task(priority: .userInitiated) {
            switch vendor {
            case .whisper:
                let params = WhisperContextParams()
                let newContext = MyWhisperContext.initFromFile(path: path, params: params)

                await MainActor.run {
                    let service = TranscriptionService.shared
                    service.context = newContext
                    service.parakeetModel = nil
                    service.loadedModelVendor = .whisper
                    service.isLoading = false
                    print("Whisper model reloaded successfully")
                }
            case .parakeet:
                print("Reloading Parakeet model from: \(path)")
                do {
                    let model = try await loadParakeetModel(
                        from: path,
                        dtype: .float16,
                        cacheDirectory: cacheDirectory
                    )

                    // Switch to eval mode to use running stats in BatchNorm, etc.
                    model.train(false)

                    await MainActor.run {
                        let service = TranscriptionService.shared
                        service.parakeetModel = model
                        service.context = nil
                        service.loadedModelVendor = .parakeet
                        service.isLoading = false
                        service.progress = 0.0
                        print("Parakeet model reloaded successfully")
                    }
                } catch {
                    await MainActor.run {
                        let service = TranscriptionService.shared
                        service.parakeetModel = nil
                        service.loadedModelVendor = nil
                        service.isLoading = false
                        print("Failed to reload Parakeet model: \(error)")
                        print("Error details: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func transcribeAudio(url: URL, settings: Settings) async throws -> String {
        let vendor = AppPreferences.shared.selectedModelVendor
        
        await MainActor.run {
            self.progress = 0.0
            self.isTranscribing = true
            self.transcribedText = ""
            self.currentSegment = ""
            self.isCancelled = false
            
            if vendor == .whisper {
                if self.abortFlag != nil {
                    self.abortFlag?.deallocate()
                }
                self.abortFlag = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
                self.abortFlag?.initialize(to: false)
            } else {
                if self.abortFlag != nil {
                    self.abortFlag?.deallocate()
                    self.abortFlag = nil
                }
            }
        }
        
        defer {
            Task { @MainActor in
                self.isTranscribing = false
                self.currentSegment = ""
                if !self.isCancelled {
                    self.progress = 1.0
                }
                self.transcriptionTask = nil
            }
        }
        
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationInSeconds = Float(CMTimeGetSeconds(duration))
        
        await MainActor.run {
            self.totalDuration = durationInSeconds
        }
        
        let task: Task<String, Error>

        switch vendor {
        case .whisper:
            let contextForTask = context
            let abortFlagForTask = abortFlag

            // Capture service reference before entering detached task
            let serviceRef = TranscriptionService.shared

            // Extract the context data we need before entering detached task
            let contextPtr = contextForTask
            let abortPtr = abortFlagForTask

            task = Task(priority: .userInitiated) {
                try Task.checkCancellation()

                guard let context = contextPtr else {
                    throw TranscriptionError.contextInitializationFailed
                }

                guard let samples = try await TranscriptionService.convertAudioToPCM(fileURL: url) else {
                    throw TranscriptionError.audioConversionFailed
                }
                
                try Task.checkCancellation()
                
                let nThreads = 4
                
                guard context.pcmToMel(samples: samples, nSamples: samples.count, nThreads: nThreads) else {
                    throw TranscriptionError.processingFailed
                }
                
                try Task.checkCancellation()
                
                guard context.encode(offset: 0, nThreads: nThreads) else {
                    throw TranscriptionError.processingFailed
                }
                
                try Task.checkCancellation()
                
                var params = WhisperFullParams()
                
                params.strategy = settings.useBeamSearch ? .beamSearch : .greedy
                params.nThreads = Int32(nThreads)
                params.noTimestamps = !settings.showTimestamps
                params.suppressBlank = settings.suppressBlankAudio
                params.translate = settings.translateToEnglish
                params.language = settings.selectedLanguage != "auto" ? settings.selectedLanguage : nil
                params.detectLanguage = false
                
                params.temperature = Float(settings.temperature)
                params.noSpeechThold = Float(settings.noSpeechThreshold)
                params.initialPrompt = settings.initialPrompt.isEmpty ? nil : settings.initialPrompt
                
                typealias GGMLAbortCallback = @convention(c) (UnsafeMutableRawPointer?) -> Bool
                
                let abortCallback: GGMLAbortCallback = { userData in
                    guard let userData = userData else { return false }
                    let flag = userData.assumingMemoryBound(to: Bool.self)
                    return flag.pointee
                }
                
                if settings.useBeamSearch {
                    params.beamSearchBeamSize = Int32(settings.beamSize)
                }
                
                params.printRealtime = true
                params.print_realtime = true
                
                let segmentCallback: @convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void = { ctx, state, n_new, user_data in
                    guard let ctx = ctx,
                          let userData = user_data,
                          let service = Unmanaged<TranscriptionService>.fromOpaque(userData).takeUnretainedValue() as TranscriptionService?
                    else { return }
                    
                    let segmentInfo = service.processNewSegment(context: ctx, state: state, nNew: Int(n_new))
                    
                    Task { @MainActor in
                        if service.isCancelled { return }
                        
                        if !segmentInfo.text.isEmpty {
                            service.currentSegment = segmentInfo.text
                            service.transcribedText += segmentInfo.text + "\n"
                        }
                        
                        if service.totalDuration > 0 && segmentInfo.timestamp > 0 {
                            let newProgress = min(segmentInfo.timestamp / service.totalDuration, 1.0)
                            service.progress = newProgress
                        }
                    }
                }
                
                params.newSegmentCallback = segmentCallback
                params.newSegmentCallbackUserData = Unmanaged.passUnretained(serviceRef).toOpaque()
                
                var cParams = params.toC()
                cParams.abort_callback = abortCallback
                
                if let abortFlag = abortPtr {
                    cParams.abort_callback_user_data = UnsafeMutableRawPointer(abortFlag)
                }
                
                try Task.checkCancellation()
                
                guard context.full(samples: samples, params: &cParams) else {
                    throw TranscriptionError.processingFailed
                }
                
                try Task.checkCancellation()
                
                var text = ""
                let nSegments = context.fullNSegments
                
                for i in 0..<nSegments {
                    if i % 5 == 0 {
                        try Task.checkCancellation()
                    }
                    
                    guard let segmentText = context.fullGetSegmentText(iSegment: i) else { continue }
                    
                    if settings.showTimestamps {
                        let t0 = context.fullGetSegmentT0(iSegment: i)
                        let t1 = context.fullGetSegmentT1(iSegment: i)
                        text += String(format: "[%.1f->%.1f] ", Float(t0) / 100.0, Float(t1) / 100.0)
                    }
                    text += segmentText + "\n"
                }
                
                let cleanedText = text
                    .replacingOccurrences(of: "[MUSIC]", with: "")
                    .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                var processedText = cleanedText
                if ["zh", "ja", "ko"].contains(settings.selectedLanguage),
                   settings.useAsianAutocorrect,
                   !cleanedText.isEmpty
                {
                    processedText = AutocorrectWrapper.format(cleanedText)
                }
                
                let finalText = processedText.isEmpty ? "No speech detected in the audio" : processedText
                
                await MainActor.run {
                    if !serviceRef.isCancelled {
                        serviceRef.transcribedText = finalText
                        serviceRef.progress = 1.0
                    }
                }
                
                return finalText
            }
        case .parakeet:
            let modelForTask = parakeetModel
            print("Starting Parakeet transcription")

            // Capture service reference before entering detached task
            let serviceRef = TranscriptionService.shared

            task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()

                guard let model = modelForTask else {
                    print("Parakeet model is nil - model not loaded!")
                    throw TranscriptionError.contextInitializationFailed
                }
                print("Parakeet model available for transcription")

                print("Converting audio to PCM format...")
                guard let samples = try await TranscriptionService.convertAudioToPCM(fileURL: url) else {
                    print("Audio conversion failed")
                    throw TranscriptionError.audioConversionFailed
                }
                print("Audio converted: \(samples.count) samples")

                try Task.checkCancellation()

                let audioArray = MLXArray(samples)

                let shouldChunk = durationInSeconds > 180
                let chunkDuration: Float? = shouldChunk ? 120.0 : nil
                print("Audio duration: \(durationInSeconds)s, chunking: \(shouldChunk)")

                // Create decoding configuration with Parakeet-specific settings
                let decodingConfig = DecodingConfig(
                    decoding: "greedy",
                    maxNewSymbolsPerStep: 500,
                    temperature: 0.0,
                    languageHint: settings.selectedLanguage != "auto" ? settings.selectedLanguage : nil
                )
                print("Parakeet decoding config: temperature=\(decodingConfig.temperature), maxSymbols=\(decodingConfig.maxNewSymbolsPerStep)")

                let result: AlignedResult
                if let chunkDuration {
                    print("Transcribing with manual chunking (chunk: \(chunkDuration)s)...")
                    let sr = Float(model.preprocessConfig.sampleRate)
                    let chunkSamples = Int(chunkDuration * sr)
                    let overlapSamples = Int(15.0 * sr)
                    let totalSamples = Int(audioArray.shape[0])

                    var allTokens: [AlignedToken] = []
                    var processedSamples: Float = 0
                    var startSample = 0
                    while startSample < totalSamples {
                        let endSample = min(startSample + chunkSamples, totalSamples)
                        let chunk = audioArray[startSample..<endSample].asType(.float16)
                        let mel = try getLogMel(chunk, config: model.preprocessConfig)
                        let inputMel = mel.ndim == 2 ? mel.expandedDimensions(axis: 0) : mel
                        let (features, lengths) = model.encode(inputMel)

                        let blankId = model.vocabulary.count
                        let initLastToken: [Int?] = [blankId]
                        let (tokenBatches, _) = try model.decode(
                            features: features,
                            lengths: lengths,
                            lastToken: initLastToken,
                            hiddenState: nil,
                            config: decodingConfig
                        )
                        var tokens = tokenBatches.first ?? []

                        // Offset tokens by chunk start
                        if !tokens.isEmpty {
                            let offsetSeconds = Float(startSample) / sr
                            for i in 0..<tokens.count {
                                var t = tokens[i]
                                t.start += offsetSeconds
                                tokens[i] = t
                            }
                            allTokens.append(contentsOf: tokens)
                        }

                        processedSamples = Float(endSample)
                        let step = max(1, chunkSamples - overlapSamples)
                        startSample = min(endSample, startSample + step)

                        // Progress callback (avoid capturing mutated variables)
                        let localProgress = min(processedSamples / Float(totalSamples), 1.0)
                        Task { @MainActor in
                            if serviceRef.isCancelled { return }
                            serviceRef.progress = localProgress.isFinite ? localProgress : 0.0
                        }
                    }

                    let sentences = TranscriptionService.tokensToSentences(allTokens)
                    result = AlignedResult(sentences: sentences)
                } else {
                    // Manual decode to ensure correct RNNT blank initialization
                    print("Transcribing without chunking (manual decode)...")
                    let processedAudio = audioArray.asType(.float16)
                    let mel = try getLogMel(processedAudio, config: model.preprocessConfig)
                    let inputMel = mel.ndim == 2 ? mel.expandedDimensions(axis: 0) : mel
                    let (features, lengths) = model.encode(inputMel)

                    // Initialize decoder with blank token as per RNNT (blank_as_pad)
                    let blankId = model.vocabulary.count
                    let initLastToken: [Int?] = [blankId]
                    let (tokenBatches, _) = try model.decode(
                        features: features,
                        lengths: lengths,
                        lastToken: initLastToken,
                        hiddenState: nil,
                        config: decodingConfig
                    )

                    // Convert tokens to an AlignedResult (mirror library utility)
                    let tokens = tokenBatches.first ?? []
                    let sentences = TranscriptionService.tokensToSentences(tokens)
                    result = AlignedResult(sentences: sentences)
                }
                print("Transcription completed")

                try Task.checkCancellation()

                let text: String
                if settings.showTimestamps {
                    let lines = result.sentences.map { sentence -> String in
                        String(
                            format: "[%.1f->%.1f] %@",
                            sentence.start,
                            sentence.end,
                            sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                    text = lines.joined(separator: "\n")
                } else {
                    text = result.text
                }
                print("Transcribed text length: \(text.count) characters")

                let cleanedText = text
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                var processedText = cleanedText
                if ["zh", "ja", "ko"].contains(settings.selectedLanguage),
                   settings.useAsianAutocorrect,
                   !cleanedText.isEmpty
                {
                    processedText = AutocorrectWrapper.format(cleanedText)
                }

                let finalText = processedText.isEmpty ? "No speech detected in the audio" : processedText
                print("Final text: \(finalText.prefix(100))...")

                await MainActor.run {
                    if !serviceRef.isCancelled {
                        serviceRef.transcribedText = finalText
                        serviceRef.progress = 1.0
                        print("Transcription result set in service")
                    }
                }

                return finalText
            }
        }
        
        await MainActor.run {
            self.transcriptionTask = task
        }
        
        do {
            return try await task.value
        } catch is CancellationError {
            await MainActor.run {
                self.isCancelled = true
                self.abortFlag?.pointee = true
            }
            throw TranscriptionError.processingFailed
        }
    }
    
    // Make this method nonisolated to be callable from any context
    nonisolated func processNewSegment(context: OpaquePointer, state: OpaquePointer?, nNew: Int) -> (text: String, timestamp: Float) {
        let nSegments = Int(whisper_full_n_segments(context))
        let startIdx = max(0, nSegments - nNew)
        
        var newText = ""
        var latestTimestamp: Float = 0
        
        for i in startIdx..<nSegments {
            guard let cString = whisper_full_get_segment_text(context, Int32(i)) else { continue }
            let segmentText = String(cString: cString)
            newText += segmentText + " "
            
            let t1 = Float(whisper_full_get_segment_t1(context, Int32(i))) / 100.0
            latestTimestamp = max(latestTimestamp, t1)
        }
        
        let cleanedText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleanedText, latestTimestamp)
    }
    
    // Removed unused createContext() to avoid cross-actor access to AppPreferences
    
    nonisolated static func convertAudioToPCM(fileURL: URL) async throws -> [Float]? {
        return try await Task.detached(priority: .userInitiated) {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: 16000,
                                       channels: 1,
                                       interleaved: false)!
            
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let converter = AVAudioConverter(from: audioFile.processingFormat, to: format)!
            
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: audioFile.processingFormat)
            
            let lengthInFrames = UInt32(audioFile.length)
            let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                          frameCapacity: AVAudioFrameCount(lengthInFrames))
            
            guard let buffer = buffer else { return nil }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                do {
                    let tempBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat,
                                                      frameCapacity: AVAudioFrameCount(inNumPackets))
                    guard let tempBuffer = tempBuffer else {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    try audioFile.read(into: tempBuffer)
                    outStatus.pointee = .haveData
                    return tempBuffer
                } catch {
                    outStatus.pointee = .endOfStream
                    return nil
                }
            }
            
            converter.convert(to: buffer,
                              error: &error,
                              withInputFrom: inputBlock)
            
            if let error = error {
                print("Conversion error: \(error)")
                return nil
            }
            
            guard let channelData = buffer.floatChannelData else { return nil }
            return Array(UnsafeBufferPointer(start: channelData[0],
                                             count: Int(buffer.frameLength)))
        }.value
    }
}

enum TranscriptionError: Error {
    case contextInitializationFailed
    case audioConversionFailed
    case processingFailed
}

// MARK: - Local helpers for Parakeet alignment post-processing
extension TranscriptionService {
    nonisolated static func tokensToSentences(_ tokens: [AlignedToken]) -> [AlignedSentence] {
        guard !tokens.isEmpty else { return [] }
        var sentences: [AlignedSentence] = []
        var current: [AlignedToken] = []
        for tok in tokens {
            current.append(tok)
            if tok.text.contains(".") || tok.text.contains("!") || tok.text.contains("?") {
                sentences.append(AlignedSentence(tokens: current))
                current.removeAll()
            }
        }
        if !current.isEmpty {
            sentences.append(AlignedSentence(tokens: current))
        }
        return sentences
    }
}

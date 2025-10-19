import Foundation

enum SpeechModelVendor: String, CaseIterable {
    case whisper = "whisper"
    case parakeet = "parakeet"

    var displayName: String {
        switch self {
        case .whisper:
            return "Whisper"
        case .parakeet:
            return "Parakeet MLX"
        }
    }
}

struct LocalSpeechModel: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let vendor: SpeechModelVendor
    let path: URL
    let repositoryID: String?

    static func == (lhs: LocalSpeechModel, rhs: LocalSpeechModel) -> Bool {
        return lhs.path == rhs.path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}
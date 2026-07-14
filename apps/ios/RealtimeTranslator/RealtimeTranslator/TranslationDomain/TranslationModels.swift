import Foundation

enum Side: String, Codable, CaseIterable {
    case russianSpeaker = "russian"
    case englishSpeaker = "english"
    
    var displayName: String {
        switch self {
        case .russianSpeaker: return "Русский"
        case .englishSpeaker: return "English"
        }
    }
}

enum TranslationMode: String, Codable {
    case oneWayRuToEn = "one_way_ru_to_en"
    case dialogue = "dialogue"
}

struct LegConfiguration: Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    let clientLegId: String
    let targetLanguage: String
    let clientSecret: String
    let callsUrl: String
    
    var description: String {
        "LegConfiguration(clientLegId: \(clientLegId), targetLanguage: \(targetLanguage), callsUrl: \(callsUrl), secret: ***)"
    }
    
    var debugDescription: String { description }
}

enum CloseReason: String, Codable {
    case userStopped
    case errorOccurred
    case sessionCompleted
    case connectionTimeout
}

struct TranscriptSegment: Identifiable, Codable, Equatable {
    let id: String
    var text: String
    let timestamp: Date
    let side: Side
    var isFinal: Bool
}

enum LegConnectionState: String, Codable {
    case connecting
    case connected
    case disconnected
    case failed
}

struct TranslationError: Error, Identifiable, Codable {
    var id: String { code }
    let code: String
    let message: String
    let retryable: Bool
}

enum TranslationEvent {
    case transcriptDelta(TranscriptSegment)
    case audioReceived(Data)
    case connectionStateChanged(LegConnectionState)
    case error(TranslationError)
}

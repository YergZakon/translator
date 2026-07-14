import Foundation

struct DataChannelEvent: Codable {
    let type: String
    let eventId: String?
}

struct TranscriptDeltaEvent: Codable {
    let type: String // "session.output_transcript.delta" or "session.input_transcript.delta"
    let delta: String
    let itemId: String?
}

struct TranscriptDoneEvent: Codable {
    let type: String
    let itemId: String?
}

class EventDecoder {
    static let shared = EventDecoder()
    private let decoder = JSONDecoder()
    
    func decodeEvent(from data: Data, side: Side) -> TranslationEvent? {
        // Here we attempt to parse known events from the WebRTC Data Channel
        guard let base = try? decoder.decode(DataChannelEvent.self, from: data) else {
            return nil
        }
        
        switch base.type {
        case "response.audio_transcript.delta", "session.output_transcript.delta", "session.input_transcript.delta":
            if let deltaEvent = try? decoder.decode(TranscriptDeltaEvent.self, from: data) {
                let segment = TranscriptSegment(
                    id: deltaEvent.itemId ?? UUID().uuidString,
                    text: deltaEvent.delta,
                    timestamp: Date(),
                    side: side,
                    isFinal: false
                )
                return .transcriptDelta(segment)
            }
        case "response.audio_transcript.done", "session.output_transcript.done", "session.input_transcript.done":
            if let doneEvent = try? decoder.decode(TranscriptDoneEvent.self, from: data) {
                let segment = TranscriptSegment(
                    id: doneEvent.itemId ?? UUID().uuidString,
                    text: "",
                    timestamp: Date(),
                    side: side,
                    isFinal: true
                )
                return .transcriptDelta(segment)
            }
        case "error":
            return .error(TranslationError(code: "SERVER_ERROR", message: "Received error from server", retryable: false))
        default:
            // Unhandled event
            break
        }
        
        return nil
    }
}

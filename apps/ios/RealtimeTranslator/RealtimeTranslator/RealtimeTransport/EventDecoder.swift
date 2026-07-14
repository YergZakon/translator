import Foundation

struct DataChannelEvent: Codable {
    let type: String
    let eventId: String?
}

struct TranscriptDeltaEvent: Codable {
    let type: String
    let delta: String
    let itemId: String?
}

struct TranscriptDoneEvent: Codable {
    let type: String
    let itemId: String?
}

class EventDecoder {
    private let decoder: JSONDecoder

    private var activeSyntheticIds: [String: String] = [:]

    init() {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec
    }

    private func getOrCreateSyntheticId(for side: Side, isInput: Bool) -> String {
        let key = "\(side.rawValue)_\(isInput ? "in" : "out")"
        if let existing = activeSyntheticIds[key] { return existing }
        let newId = "synth_" + UUID().uuidString.prefix(8)
        activeSyntheticIds[key] = String(newId)
        return String(newId)
    }

    private func clearSyntheticId(for side: Side, isInput: Bool) {
        let key = "\(side.rawValue)_\(isInput ? "in" : "out")"
        activeSyntheticIds.removeValue(forKey: key)
    }

    func decodeEvent(from data: Data, side: Side) -> TranslationEvent? {
        guard let base = try? decoder.decode(DataChannelEvent.self, from: data) else {
            return nil
        }

        let isInput = base.type.contains("input")

        switch base.type {
        case "response.audio_transcript.delta", "session.output_transcript.delta", "session.input_transcript.delta":
            if let deltaEvent = try? decoder.decode(TranscriptDeltaEvent.self, from: data) {
                let id = deltaEvent.itemId ?? getOrCreateSyntheticId(for: side, isInput: isInput)
                let segment = TranscriptSegment(
                    id: id,
                    text: deltaEvent.delta,
                    timestamp: Date(),
                    side: side,
                    isFinal: false
                )
                return .transcriptDelta(segment)
            }
        case "response.audio_transcript.done", "session.output_transcript.done", "session.input_transcript.done":
            if let doneEvent = try? decoder.decode(TranscriptDoneEvent.self, from: data) {
                let id = doneEvent.itemId ?? getOrCreateSyntheticId(for: side, isInput: isInput)
                clearSyntheticId(for: side, isInput: isInput)

                let segment = TranscriptSegment(
                    id: id,
                    text: "",
                    timestamp: Date(),
                    side: side,
                    isFinal: true
                )
                return .transcriptDelta(segment)
            }
        case "session.closed":
            return .sessionClosed
        case "error":
            return .error(TranslationError(code: "SERVER_ERROR", message: "Received error from server", retryable: false))
        default:
            break
        }

        return nil
    }
}

import Foundation

class Redactor {
    static func redact(_ metadata: [String: String]) -> [String: String] {
        var clean = metadata
        // Avoid sending any raw audio transcripts or PII
        for key in clean.keys {
            if key.contains("text") || key.contains("transcript") || key.contains("audio") {
                clean[key] = "[REDACTED]"
            }
        }
        return clean
    }
}

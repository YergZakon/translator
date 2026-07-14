import Foundation

struct FeatureFlags: Codable {
    var enableAutoSideDetection: Bool = false
    var enableGlossary: Bool = false
    var enableLocalTranscriptSave: Bool = false
}

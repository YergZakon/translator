import Foundation

protocol TranslationProvider {
    func createLeg(configuration: LegConfiguration) async throws -> TranslationLeg
}

protocol TranslationLeg: AnyObject {
    var events: AsyncStream<TranslationEvent> { get }
    func connect() async throws
    func setMicrophoneEnabled(_ enabled: Bool) async
    func setOutputEnabled(_ enabled: Bool) async
    func close(reason: CloseReason) async
}

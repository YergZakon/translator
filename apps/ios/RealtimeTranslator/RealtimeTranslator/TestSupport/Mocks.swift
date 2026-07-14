import Foundation

class FakeTranslationLeg: TranslationLeg {
    let events: AsyncStream<TranslationEvent>
    private let continuation: AsyncStream<TranslationEvent>.Continuation

    init() {
        let (stream, cont) = AsyncStream<TranslationEvent>.makeStream()
        self.events = stream
        self.continuation = cont
    }

    func connect() async throws {
        continuation.yield(.connectionStateChanged(.connected))
    }

    func setMicrophoneEnabled(_ enabled: Bool) async {}

    func setOutputEnabled(_ enabled: Bool) async {}

    func close(reason: CloseReason) async {
        continuation.yield(.connectionStateChanged(.disconnected))
    }
}

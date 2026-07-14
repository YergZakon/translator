import Foundation

actor OutputArbiter {
    private let diagnostics: DiagnosticsStore
    private var activeLegId: String? = nil

    init(diagnostics: DiagnosticsStore) {
        self.diagnostics = diagnostics
    }

    func acquireOutputRights(for legId: String) -> Bool {
        if activeLegId == nil || activeLegId == legId {
            activeLegId = legId
            diagnostics.log("OutputArbiter: Leg \(legId) acquired output rights")
            return true
        }
        diagnostics.log("OutputArbiter: Leg \(legId) denied output rights")
        return false
    }

    func releaseOutputRights(for legId: String) {
        if activeLegId == legId {
            activeLegId = nil
            diagnostics.log("OutputArbiter: Leg \(legId) released output rights")
        }
    }
}

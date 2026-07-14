import Foundation

class TelemetryClient {
    private let diagnostics: DiagnosticsStore
    
    init(diagnostics: DiagnosticsStore) {
        self.diagnostics = diagnostics
    }
    
    func logEvent(_ name: String, metadata: [String: String]) {
        // Redact any possible private data
        let redactedMetadata = Redactor.redact(metadata)
        diagnostics.log("Telemetry event: \(name), data: \(redactedMetadata)")
    }
}

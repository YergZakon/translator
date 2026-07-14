import Foundation

class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()

    let environment: AppEnvironment
    @Published var featureFlags: FeatureFlags
    let sessionAPI: SessionAPI
    let audioController: AudioSessionController
    let outputArbiter: OutputArbiter
    let telemetryClient: TelemetryClient
    let diagnosticsStore: DiagnosticsStore

    init(environment: AppEnvironment = .development) {
        self.environment = environment
        self.featureFlags = FeatureFlags()

        let diag = DiagnosticsStore()
        let tele = TelemetryClient(diagnostics: diag)

        self.diagnosticsStore = diag
        self.telemetryClient = tele
        self.sessionAPI = MockBackendClient()
        self.audioController = AudioSessionController(diagnostics: diag)
        self.outputArbiter = OutputArbiter(diagnostics: diag)
    }
}

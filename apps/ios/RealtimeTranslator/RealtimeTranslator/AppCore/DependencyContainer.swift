import Foundation

class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()

    let environment: AppEnvironment
    @Published var featureFlags: FeatureFlags
    let sessionAPI: SessionAPI
    let configAPI: ConfigAPI
    let audioController: AudioSessionController
    let outputArbiter: OutputArbiter
    let telemetryClient: TelemetryClient
    let diagnosticsStore: DiagnosticsStore

    init(
        environment: AppEnvironment = AppEnvironment.current,
        sessionAPI: SessionAPI? = nil,
        configAPI: ConfigAPI? = nil
    ) {
        self.environment = environment
        self.featureFlags = FeatureFlags()

        let diag = DiagnosticsStore()
        let tele = TelemetryClient(diagnostics: diag)

        self.diagnosticsStore = diag
        self.telemetryClient = tele

        let backendClient = LiveBackendClient(
            baseURL: environment.baseURL,
            appToken: environment.prototypeAppToken
        )
        self.sessionAPI = sessionAPI ?? backendClient
        self.configAPI = configAPI ?? backendClient

        self.audioController = AudioSessionController(diagnostics: diag)
        self.outputArbiter = OutputArbiter(diagnostics: diag)
    }
}

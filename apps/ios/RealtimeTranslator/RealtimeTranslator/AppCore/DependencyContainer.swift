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
    
    init(environment: AppEnvironment = AppEnvironment.current, sessionAPI: SessionAPI? = nil, configAPI: ConfigAPI? = nil) {
        self.environment = environment
        self.featureFlags = FeatureFlags()

        let diag = DiagnosticsStore()
        let tele = TelemetryClient(diagnostics: diag)

        self.diagnosticsStore = diag
        self.telemetryClient = tele
        
        if let sessionAPI = sessionAPI, let configAPI = configAPI {
            self.sessionAPI = sessionAPI
            self.configAPI = configAPI
        } else {
            let backendClient = LiveBackendClient(baseURL: environment.baseURL)
            self.sessionAPI = backendClient
            self.configAPI = backendClient
        }
        
        self.audioController = AudioSessionController(diagnostics: diag)
        self.outputArbiter = OutputArbiter(diagnostics: diag)
    }
}

import Foundation

class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()

    let environment: AppEnvironment
    @Published var featureFlags: FeatureFlags
    let sessionAPI: SessionAPI
    let configAPI: ConfigAPI
    let installationAPI: InstallationAPI
    let audioController: AudioSessionController
    let outputArbiter: OutputArbiter
    let telemetryClient: TelemetryClient
    let diagnosticsStore: DiagnosticsStore
    let tokenStorage: TokenStorage

    init(
        environment: AppEnvironment = AppEnvironment.current,
        sessionAPI: SessionAPI? = nil,
        configAPI: ConfigAPI? = nil,
        installationAPI: InstallationAPI? = nil,
        tokenStorage: TokenStorage? = nil
    ) {
        self.environment = environment
        self.featureFlags = FeatureFlags()

        let diag = DiagnosticsStore()
        let tele = TelemetryClient(diagnostics: diag)

        self.diagnosticsStore = diag
        self.telemetryClient = tele

        let storage = tokenStorage ?? KeychainTokenStorage()
        self.tokenStorage = storage

        let backendClient = LiveBackendClient(
            baseURL: environment.baseURL,
            tokenStorage: storage
        )
        self.sessionAPI = sessionAPI ?? backendClient
        self.configAPI = configAPI ?? backendClient
        self.installationAPI = installationAPI ?? backendClient

        self.audioController = AudioSessionController(diagnostics: diag)
        self.outputArbiter = OutputArbiter(diagnostics: diag)
    }
}

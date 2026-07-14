import Foundation
import WebRTC

class OpenAITranslationLeg: NSObject, TranslationLeg {
    private let configuration: LegConfiguration
    private let side: Side
    private let diagnostics: DiagnosticsStore

    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?

    private let eventDecoder = EventDecoder()

    private var desiredOutputEnabled: Bool = false
    private var isClosedByServer: Bool = false

    // To support AsyncStream
    private var continuation: AsyncStream<TranslationEvent>.Continuation?
    lazy var events: AsyncStream<TranslationEvent> = {
        AsyncStream { [weak self] cont in
            self?.continuation = cont
        }
    }()

    // WebRTC Factory (simplified for spike)
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }()

    init(configuration: LegConfiguration, side: Side, diagnostics: DiagnosticsStore) {
        self.configuration = configuration
        self.side = side
        self.diagnostics = diagnostics
        super.init()
    }

    func connect() async throws {
        diagnostics.log("OpenAITranslationLeg: Connecting to \(configuration.callsUrl)")

        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        guard let pc = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw TranslationError(code: "WEBRTC_ERROR", message: "Cannot create RTCPeerConnection", retryable: false)
        }
        self.peerConnection = pc

        // Add Audio Track
        let audioSource = Self.factory.audioSource(with: nil)
        let audioTrack = Self.factory.audioTrack(with: audioSource, trackId: "audio0")
        audioTrack.isEnabled = false
        self.localAudioTrack = audioTrack
        pc.add(audioTrack, streamIds: ["stream0"])

        // Add Data Channel
        let dcConfig = RTCDataChannelConfiguration()
        guard let dc = pc.dataChannel(forLabel: "oai-events", configuration: dcConfig) else {
            throw TranslationError(code: "WEBRTC_ERROR", message: "Cannot create RTCDataChannel", retryable: false)
        }
        dc.delegate = self
        self.dataChannel = dc

        // Create Offer
        let offer = try await createOffer(for: pc, constraints: constraints)
        try await setLocalDescription(offer, for: pc)

        // Send to Server
        let answer = try await sendOfferToServer(offer: offer)
        try await setRemoteDescription(answer, for: pc)

        // Ensure remote output is initially disabled until state machine enables it
        self.desiredOutputEnabled = false
        await setOutputEnabled(false)
    }

    func setMicrophoneEnabled(_ enabled: Bool) async {
        localAudioTrack?.isEnabled = enabled
        diagnostics.log("OpenAITranslationLeg: Microphone enabled=\(enabled)")
    }

    func setOutputEnabled(_ enabled: Bool) async {
        self.desiredOutputEnabled = enabled
        // Find remote audio tracks and mute/unmute
        if let receivers = peerConnection?.receivers {
            for receiver in receivers {
                if let track = receiver.track as? RTCAudioTrack {
                    track.isEnabled = enabled
                }
            }
        }
        diagnostics.log("OpenAITranslationLeg: Output enabled=\(enabled)")
    }

    func close(reason: CloseReason) async {
        diagnostics.log("OpenAITranslationLeg: Closing with reason \(reason). Draining events...")

        // Send a client event to close the session gracefully if needed,
        // and allow some time for remaining transcript deltas to arrive.
        if let dc = dataChannel, dc.readyState == .open {
            let closeEvent = "{\"type\": \"session.close\"}"
            if let data = closeEvent.data(using: .utf8) {
                dc.sendData(RTCDataBuffer(data: data, isBinary: false))
            }

            // Poll wait for session.closed event up to 2 seconds
            for _ in 0..<20 {
                if self.isClosedByServer { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        dataChannel?.close()
        peerConnection?.close()
        continuation?.finish()
        diagnostics.log("OpenAITranslationLeg: Closed")
    }

    // MARK: - SDP Helpers
    private func createOffer(for pc: RTCPeerConnection, constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation { cont in
            pc.offer(for: constraints) { sdp, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if let sdp = sdp {
                    cont.resume(returning: sdp)
                } else {
                    cont.resume(throwing: TranslationError(code: "SDP_ERROR", message: "Empty SDP", retryable: false))
                }
            }
        }
    }

    private func setLocalDescription(_ sdp: RTCSessionDescription, for pc: RTCPeerConnection) async throws {
        return try await withCheckedThrowingContinuation { cont in
            pc.setLocalDescription(sdp) { error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    private func setRemoteDescription(_ sdp: RTCSessionDescription, for pc: RTCPeerConnection) async throws {
        return try await withCheckedThrowingContinuation { cont in
            pc.setRemoteDescription(sdp) { error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    private func sendOfferToServer(offer: RTCSessionDescription) async throws -> RTCSessionDescription {
        guard let url = URL(string: configuration.callsUrl) else {
            throw TranslationError(code: "INVALID_URL", message: "Invalid callsUrl", retryable: false)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.clientSecret)", forHTTPHeaderField: "Authorization")
        request.httpBody = offer.sdp.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw TranslationError(code: "SERVER_ERROR", message: "Server returned error", retryable: false)
        }

        guard let sdpString = String(data: data, encoding: .utf8) else {
            throw TranslationError(code: "PARSE_ERROR", message: "Cannot parse SDP answer", retryable: false)
        }

        return RTCSessionDescription(type: .answer, sdp: sdpString)
    }
}

// MARK: - RTCPeerConnectionDelegate
extension OpenAITranslationLeg: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCAudioTrack {
            track.isEnabled = self.desiredOutputEnabled
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let state: LegConnectionState
        switch newState {
        case .connected, .completed: state = .connected
        case .disconnected: state = .disconnected
        case .failed: state = .failed
        default: state = .connecting
        }
        continuation?.yield(.connectionStateChanged(state))
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - RTCDataChannelDelegate
extension OpenAITranslationLeg: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        diagnostics.log("DataChannel state: \(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if let event = eventDecoder.decodeEvent(from: buffer.data, side: self.side) {
            if case .sessionClosed = event {
                self.isClosedByServer = true
            }
            continuation?.yield(event)
        }
    }
}

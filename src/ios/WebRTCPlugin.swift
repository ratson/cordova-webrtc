import WebRTC

@objc(WebRTCPlugin)
public class WebRTCPlugin : CDVPlugin {
    lazy var agent: Agent = { return Agent(self) } ()

    var readyCallbackId: String?

    deinit {
        readyCallbackId = nil
    }

    public override func pluginInitialize() {
        super.pluginInitialize()

        SimplePeer.initialize()

        NotificationCenter.default.addObserver(
            self, selector: #selector(Self.handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(Self.handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil)
    }

    @objc func ready(_ command: CDVInvokedUrlCommand) {
        readyCallbackId = command.callbackId
    }

    @objc func renewAgent(_ command: CDVInvokedUrlCommand) {
        self.agent = Agent(self)
        self.resolve(command)
    }

    func emit(_ eventName: String, data: Any = NSNull()) {
        guard let callbackId = readyCallbackId else { return }

        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["type": eventName, "data": data])
        result?.setKeepCallbackAs(true)
        self.commandDelegate.send(result, callbackId: callbackId)
    }

    public func reject(_ command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_ERROR)
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }
    public func resolve(_ command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }
}

extension WebRTCPlugin {
    @objc func handleAudioSessionInterruption(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let _ = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        let data: Dictionary<String, Any> = [
            "interruptionType": typeValue,
        ]
        self.emit("audioSession.interruption", data: data)
    }

    @objc func handleAudioSessionRouteChange(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let _ = AVAudioSession.RouteChangeReason(rawValue:reasonValue) else {
            return
        }

        let data: Dictionary<String, Any> = [
            "changeReason": reasonValue,
        ]
        self.emit("audioSession.routeChange", data: data)
    }
}

extension WebRTCPlugin {
    @objc func configAudio(_ command: CDVInvokedUrlCommand) {
        guard let opt = command.argument(at: 0) as? Dictionary<String, Any>,
              let active = opt["active"] as? Bool?,
              let isAudioEnabled = opt["isAudioEnabled"] as? Bool?,
              let category = opt["category"] as? String?,
              let categoryOptions = opt["categoryOptions"] as? UInt?,
              let inputGain = opt["inputGain"] as? Float?,
              let mode = opt["mode"] as? String?,
              let portOverride = opt["portOverride"] as? String?
        else {
            self.reject(command)
            return
        }

        let audioSession = RTCAudioSession.sharedInstance()

        if let v = isAudioEnabled {
            audioSession.isAudioEnabled = v
        }

        audioSession.lockForConfiguration()

        do {
            if let v = category {
                let category = AVAudioSession.Category(rawValue: v)

                if let i = categoryOptions {
                    try audioSession.setCategory(category.rawValue, with: AVAudioSession.CategoryOptions(rawValue: i))
                } else {
                    try audioSession.setCategory(category.rawValue, with: [
                        .allowAirPlay,
                        .allowBluetoothA2DP,
                        .defaultToSpeaker,
                        .mixWithOthers
                    ])
                }
            }
            if let v = inputGain {
                try audioSession.setInputGain(v)
            }
            if let v = mode {
                let mode = AVAudioSession.Mode(rawValue: v)
                try audioSession.setMode(mode.rawValue)
            }
            if let v = portOverride {
                if v == "speaker" {
                    try audioSession.overrideOutputAudioPort(.speaker)
                } else {
                    try audioSession.overrideOutputAudioPort(.none)
                }
            }
            if let v = active {
                try audioSession.setActive(v)
            }
        } catch let error {
            print("Error changeing AVAudioSession category: \(error)")
        }
        audioSession.unlockForConfiguration()

        self.resolve(command)
    }
}

extension WebRTCPlugin {
    @objc func agentStart(_ command: CDVInvokedUrlCommand) {
        self.agent.offer() { _, _ in
            self.resolve(command)
        }
    }

    @objc func agentAnswer(_ command: CDVInvokedUrlCommand) {
        guard let optDesc = command.argument(at: 0) as? Dictionary<String, String>,
              let optSdp = optDesc["sdp"],
              let desc = RTCSessionDescription(type: .answer, sdp: optSdp) as RTCSessionDescription?
        else {
            self.reject(command)
            return
        }

        self.agent.pc.setRemoteDescription(desc) { error in
            self.resolve(command)
        }
    }

    @objc func agentCandidate(_ command: CDVInvokedUrlCommand) {
        guard let optDesc = command.argument(at: 0) as? Dictionary<String, Any>,
              let candidate = RTCIceCandidate(
                sdp: optDesc["candidate"] as! String,
                sdpMLineIndex: optDesc["sdpMLineIndex"] as! Int32,
                sdpMid: optDesc["sdpMid"] as? String
              ) as RTCIceCandidate?
        else {
            self.reject(command)
            return
        }

        self.agent.add(candidate)

        self.resolve(command)
    }

    @objc func agentSend(_ command: CDVInvokedUrlCommand) {
        guard let enable = command.argument(at: 0) as? Bool else {
            self.reject(command)
            return
        }

        self.agent.enableSender(enable)

        self.resolve(command)
    }
}

class Agent: NSObject {
    let plugin: WebRTCPlugin

    var sender: RTCRtpSender?

    var inboundStream: RTCMediaStream?

    lazy var pcf: RTCPeerConnectionFactory = {
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()

    lazy var pcConfig: RTCConfiguration = {
        let config = RTCConfiguration()
        config.iceServers = []
        config.sdpSemantics = .unifiedPlan
        config.certificate = RTCCertificate.generate(withParams: ["expires" : 100000, "name" : "RSASSA-PKCS1-v1_5"])
        return config
    }()

    lazy var offerConstraints: RTCMediaConstraints = {
        let yes = kRTCMediaConstraintsValueTrue
        let no = kRTCMediaConstraintsValueFalse
        return RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: yes,
                kRTCMediaConstraintsOfferToReceiveVideo: no,
            ],
            optionalConstraints: [
                "DtlsSrtpKeyAgreement": yes,
                "RtpDataChannels" : yes,
                "internalSctpDataChannels" : yes,
            ]
        )
    }()

    lazy var audioTrack: RTCAudioTrack = {
        let audioSource = pcf.audioSource(with: RTCMediaConstraints(mandatoryConstraints: [:], optionalConstraints: nil))
        let audioTrack = pcf.audioTrack(with: audioSource, trackId: "ARDAMSa0")
        return audioTrack
    }()

    lazy var pc: RTCPeerConnection = {
        return pcf.peerConnection(with: self.pcConfig, constraints: SimplePeer.defaultMediaConstraints, delegate: self)
    }()

    init(_ plugin: WebRTCPlugin) {
        self.plugin = plugin

        super.init()

        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.add(self)
    }

    deinit {
        RTCAudioSession.sharedInstance().remove(self)

        pc.close()
        pc.delegate = nil
    }

    func offer(completionHandler: ((RTCSessionDescription?, Error?) -> Void)? = nil) {
        pc.offer(for: self.offerConstraints) { (desc, error) in
            guard let desc = desc else {
                completionHandler?(nil, error)
                return
            }

            self.pc.setLocalDescription(desc) { error in
                if error != nil {
                    completionHandler?(desc, error)
                    return
                }

                self.plugin.emit("agent.offer", data: [
                    "offer": [
                        "type": RTCSessionDescription.string(for: desc.type),
                        "sdp": desc.sdp,
                    ]
                ])
                completionHandler?(desc, nil)
            }
        }
    }

    func add(_ candidate: RTCIceCandidate) {
        self.pc.add(candidate)
    }

    func enableSender(_ enable: Bool) {
        if let sender = self.sender {
            sender.track = enable ? self.audioTrack : nil
        } else if enable {
            self.sender = pc.add(audioTrack, streamIds: ["ARDAMS"])
        }
    }
}

extension Agent: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        self.plugin.emit("agent.didAddMediaStream")
        self.inboundStream = stream
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        self.plugin.emit("agent.didRemoveMediaStream")
    }

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        self.offer()
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        self.plugin.emit("agent.candidate", data: [
            "type": "candidate",
            "candidate": [
                "candidate": candidate.sdp,
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdpMid": candidate.sdpMid!
            ]
        ])
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        self.plugin.emit("agent.didRemoveCandidates")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn rtpTransceiver: RTCRtpTransceiver) {
        self.plugin.emit("agent.didStartReceivingOn")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        self.plugin.emit("agent.didAddRtpReceiver")
    }
}

extension Agent: RTCAudioSessionDelegate {
    public func audioSessionDidStartPlayOrRecord(_ session: RTCAudioSession) {
        self.plugin.emit("agent.audioSessionDidStartPlayOrRecord")
    }

    public func audioSessionDidStopPlayOrRecord(_ session: RTCAudioSession) {
        self.plugin.emit("agent.audioSessionDidStopPlayOrRecord")
    }

    public func audioSession(_ session: RTCAudioSession, didChangeCanPlayOrRecord canPlayOrRecord: Bool) {
        self.plugin.emit("agent.didChangeCanPlayOrRecord", data: ["canPlayOrRecord": canPlayOrRecord])
    }
}

extension Agent : RTCVideoCapturerDelegate {
    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
    }
}

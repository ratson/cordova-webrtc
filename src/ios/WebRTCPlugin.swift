import WebRTC

@objc(WebRTCPlugin)
public class WebRTCPlugin : CDVPlugin, RTCPeerConnectionDelegate, RTCAudioSessionDelegate {
    var pc: RTCPeerConnection!
    var sender: RTCRtpSender?

    var readyCallbackId: String!

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
        return RTCMediaConstraints(
            mandatoryConstraints: [kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse,
                                   kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue],
            optionalConstraints: nil)
    }()

    lazy var audioTrack: RTCAudioTrack = {
        let audioSource = pcf.audioSource(with: RTCMediaConstraints(mandatoryConstraints: [:], optionalConstraints: nil))
        let audioTrack = pcf.audioTrack(with: audioSource, trackId: "ARDAMSa0")
        return audioTrack
    }()

    deinit {
        readyCallbackId = nil
    }

    public override func pluginInitialize() {
        super.pluginInitialize()

        SimplePeer.initialize()

        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.add(self)
    }

    @objc func ready(_ command: CDVInvokedUrlCommand) {
        readyCallbackId = command.callbackId
    }

    func emit(_ eventName: String, data: Any = NSNull()) {
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["type": eventName, "data": data])
        result?.setKeepCallbackAs(true)
        self.commandDelegate.send(result, callbackId: readyCallbackId)
    }

    @objc func start(_ command: CDVInvokedUrlCommand) {
        let mediaTrackStreamIDs = ["ARDAMS"]

        let pc = pcf.peerConnection(with: self.pcConfig, constraints: SimplePeer.defaultMediaConstraints, delegate: self)
        self.pc = pc

        self.sender = pc.add(audioTrack, streamIds: mediaTrackStreamIDs)
        pc.offer(for: self.offerConstraints) { (desc, error) in
            guard let desc = desc else { return }
            pc.setLocalDescription(desc) { (error) in
                if error != nil {
                    let result = CDVPluginResult(status: CDVCommandStatus_ERROR)
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                    return
                }
            }

            let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: [
                "type": RTCSessionDescription.string(for: desc.type),
                "sdp": desc.sdp,
            ])
            self.commandDelegate.send(result, callbackId: command.callbackId)
        }
    }

    @objc func answer(_ command: CDVInvokedUrlCommand) {
        guard let optDesc = command.argument(at: 0) as? Dictionary<String, String>,
              let optSdp = optDesc["sdp"],
              let desc = RTCSessionDescription(type: .answer, sdp: optSdp) as RTCSessionDescription?
        else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR)
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        pc.setRemoteDescription(desc) { error in

        }

        self.reolsve(command)
    }

    @objc func candidate(_ command: CDVInvokedUrlCommand) {
        guard let optDesc = command.argument(at: 0) as? Dictionary<String, Any>,
              let candidate = RTCIceCandidate(
                sdp: optDesc["candidate"] as! String,
                sdpMLineIndex: optDesc["sdpMLineIndex"] as! Int32,
                sdpMid: optDesc["sdpMid"] as? String
              ) as RTCIceCandidate?
        else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR)
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        self.pc.add(candidate)

        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc func configAudio(_ command: CDVInvokedUrlCommand) {
        guard let opt = command.argument(at: 0) as? Dictionary<String, Any>,
              let active = opt["active"] as? Bool?,
              let isAudioEnabled = opt["isAudioEnabled"] as? Bool?,
              let category = opt["category"] as? String?,
              let inputGain = opt["inputGain"] as? Float?,
              let mode = opt["mode"] as? String?,
              let port = opt["port"] as? String?
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
            if let v = resovleCategory(category) {
                try audioSession.setCategory(v.rawValue, with: [
                    .allowAirPlay,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .defaultToSpeaker,
                    .mixWithOthers,
                ])
            }
            if let v = inputGain {
                try audioSession.setInputGain(v)
            }
            if let v = mode {
                try audioSession.setMode(v)
            }
            if let v = port {
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

    @objc func toggleSender(_ command: CDVInvokedUrlCommand) {
        guard let enable = command.argument(at: 0) as? Bool,
              let sender = self.sender else {
            self.reject(command)
            return
        }

        if enable {
            if sender.track != self.audioTrack {
                sender.track = self.audioTrack
            }
        } else {
            pc.removeTrack(sender)
        }

        self.resolve(command)
    }

    func resovleCategory(_ s: String?) -> AVAudioSession.Category? {
        switch s {
        case "ambient":
            return AVAudioSession.Category.ambient
        case "playAndRecord":
            return AVAudioSession.Category.playAndRecord
        case "multiRoute":
            return AVAudioSession.Category.multiRoute
        case "playback":
            return AVAudioSession.Category.playback
        case "record":
            return AVAudioSession.Category.record
        case "soloAmbient":
            return AVAudioSession.Category.soloAmbient
        default:
            return nil
        }
    }

    private func reject(_ command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_ERROR)
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }
    private func resolve(_ command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {

    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        self.emit("candidate", data: [
            "type": "candidate",
            "candidate": [
                "candidate": candidate.sdp,
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdpMid": candidate.sdpMid!
            ]
        ])
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    }

    public func audioSessionDidStartPlayOrRecord(_ session: RTCAudioSession) {
        RTCDispatcher.dispatchAsync(on: .typeMain) {
            SimplePeer.configureAudioSession()
        }
        self.emit("audioSessionDidStartPlayOrRecord")
    }

    public func audioSessionDidStopPlayOrRecord(_ session: RTCAudioSession) {
    }

    public func audioSession(_ session: RTCAudioSession, didChangeCanPlayOrRecord canPlayOrRecord: Bool) {
        RTCDispatcher.dispatchAsync(on: .typeMain) {
            SimplePeer.configureAudioSession()
        }
    }
}

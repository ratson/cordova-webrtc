import WebRTC

@objc(WebRTCPlugin)
public class WebRTCPlugin : CDVPlugin, RTCPeerConnectionDelegate, RTCAudioSessionDelegate {
    var pcf: RTCPeerConnectionFactory!
    var pc: RTCPeerConnection!
    var audioPlayer: AVAudioPlayer!

    var readyCallbackId: String!

    deinit {
        readyCallbackId = nil
    }

    public override func pluginInitialize() {
        super.pluginInitialize()

        SimplePeer.initialize()

        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.add(self)

        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        pcf = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
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
        let audioSource = pcf.audioSource(with: RTCMediaConstraints(mandatoryConstraints: [:], optionalConstraints: nil))
        let audioTrack = pcf.audioTrack(with: audioSource, trackId: "ARDAMSa0")
        let mediaTrackStreamIDs = ["ARDAMS"]

        let session = RTCAudioSession.sharedInstance()
        session.add(self)

        let config = RTCConfiguration()
        config.iceServers = []
        config.sdpSemantics = .unifiedPlan
        config.certificate = RTCCertificate.generate(withParams: ["expires" : 100000, "name" : "RSASSA-PKCS1-v1_5"])
        let pc = pcf.peerConnection(with: config, constraints: SimplePeer.defaultMediaConstraints, delegate: self)
        self.pc = pc

        pc.add(audioTrack, streamIds: mediaTrackStreamIDs)
        pc.offer(for: RTCMediaConstraints(
                    mandatoryConstraints: ["OfferToReceiveVideo": kRTCMediaConstraintsValueFalse,
                                           "OfferToReceiveAudio": kRTCMediaConstraintsValueTrue],
                    optionalConstraints: nil)) { (desc, error) in
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

        let result = CDVPluginResult(status: CDVCommandStatus_OK)
        self.commandDelegate.send(result, callbackId: command.callbackId)
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

    @objc func setIsAudioEnabled(_ command: CDVInvokedUrlCommand) {
        guard let optValue = command.argument(at: 0) as? Bool?,
              let value = optValue else {
            self.reject(command)
            return
        }

        RTCAudioSession.sharedInstance().isAudioEnabled = value

        self.resolve(command)
    }

    private func reject(_ command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_ERROR)
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }
    private func resolve(_ command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_ERROR)
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

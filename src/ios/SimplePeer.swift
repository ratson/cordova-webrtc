import WebRTC

public class SimplePeer {
    static let defaultMediaConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

    public static func configureAudioSession() {
        let audioSession = RTCAudioSession.sharedInstance()

        let config = RTCAudioSessionConfiguration()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.categoryOptions = [
            .allowAirPlay,
            .allowBluetooth,
            .allowBluetoothA2DP,
            .defaultToSpeaker,
            .mixWithOthers,
        ]
        config.mode = AVAudioSession.Mode.default.rawValue

        audioSession.lockForConfiguration()
        do {
            if audioSession.isActive {
                try audioSession.setConfiguration(config)
            } else {
                try audioSession.setConfiguration(config, active: true)
            }
            try audioSession.overrideOutputAudioPort(.none)
        } catch let error {
            print("Error changeing AVAudioSession category: \(error)")
        }
        audioSession.unlockForConfiguration()
    }

    public static func initialize() {
        RTCPeerConnectionFactory.initialize()
        RTCInitializeSSL()
        configureAudioSession()
    }
}

/// <reference types="cordova" />

const SERVICE = "WebRTC";

const execAsync = (method: string, ...args: unknown[]) =>
  new Promise((resolve, reject) => {
    cordova.exec(resolve, reject, SERVICE, method, args);
  });

class Agent {
  _isNegotiating = false;
  _pc: RTCPeerConnection;
  _stream: MediaStream | undefined;

  constructor() {
    const pc = new RTCPeerConnection({});
    this._pc = pc;

    pc.onicecandidate = async (event) => {
      if (event.candidate) {
        await execAsync("agentCandidate", event.candidate);
      }
    };
    pc.onsignalingstatechange = () => {
      if (pc.signalingState === "stable") {
        this._isNegotiating = false;
      }
    };
    pc.ontrack = (event) => {
      const stream = event.streams[0];
      this._stream = stream;
    };

    document.addEventListener(
      "webrtc.agent.offer",
      async (data: any) => {
        this._isNegotiating = true;
        await this._answer(data.offer);
      },
      false,
    );

    document.addEventListener("webrtc.agent.candidate", (data: any) => {
      pc.addIceCandidate(data.candidate);
    }, false);
  }

  async getStream() {
    if (this._stream) {
      await this.toggleSend(true);
      return this._stream;
    }

    const streamPromise = new Promise<MediaStream>((resolve) => {
      this._pc.addEventListener("track", (e) => {
        const stream = e.streams[0];
        resolve(stream);
      }, { once: true, passive: true });
    });

    await this.toggleSend(true);
    await execAsync("agentStart");
    this._stream = await streamPromise;
    return this._stream;
  }

  async addStream(stream: MediaStream) {
    const pc = this._pc;
    stream.getTracks().forEach((track) => {
      pc.addTrack(track, stream);
    });
    await execAsync("agentStart");
  }

  async toggleSend(enable: boolean) {
    return execAsync("agentSend", enable);
  }

  async _answer(offer: RTCSessionDescriptionInit) {
    const pc = this._pc;
    await pc.setRemoteDescription(offer);

    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await execAsync("agentAnswer", answer);
  }
}

class WebRTCPlugin {
  agent = new Agent();

  constructor() {
    document.addEventListener("deviceready", () => {
      cordova.exec(
        (event) => {
          if (!event || !event.type) return;
          // @ts-expect-error
          cordova.fireDocumentEvent(`webrtc.${event.type}`, event.data);
        },
        () => {},
        SERVICE,
        "ready",
      );
    }, false);
  }

  configAudio(opts: {
    active?: boolean;
    isAudioEnabled?: boolean;
    inputGain?: number;
    category?:
      | "ambient"
      | "multiRoute"
      | "playAndRecord"
      | "playback"
      | "record"
      | "soloAmbient";
    mode?:
      | "default"
      | "gameChat"
      | "measurement"
      | "moviePlayback"
      | "spokenAudio"
      | "videoChat"
      | "videoRecording"
      | "voicePrompt";
    port?: "speaker" | "none";
  }) {
    const category = opts.category
      ? `AVAudioSessionCategory${opts.category[0].toUpperCase()}${
        opts.category.substr(1)
      }`
      : undefined;
    const mode = opts.mode
      ? `AVAudioSessionMode${opts.mode[0].toUpperCase()}${opts.mode.substr(1)}`
      : undefined;
    return execAsync("configAudio", { ...opts, category, mode });
  }

  __start() {
    return execAsync("start");
  }

  __answer(desc) {
    return execAsync("answer", desc);
  }

  __candidate(desc) {
    return execAsync("candidate", desc);
  }

  __toggleSender(enable) {
    return execAsync("toggleSender", enable);
  }
}

export default new WebRTCPlugin();

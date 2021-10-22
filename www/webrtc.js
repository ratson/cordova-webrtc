const SERVICE = "WebRTC";

const execAsync = (method, ...args) =>
  new Promise((resolve, reject) => {
    cordova.exec(resolve, reject, SERVICE, method, args);
  });

class Agent {
  _isNegotiating = false;

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

    document.addEventListener("webrtc.agent.offer", async (data) => {
      this._isNegotiating = true;
      await this._answer(data.offer);
    }, false);

    document.addEventListener("webrtc.agent.candidate", (data) => {
      pc.addIceCandidate(data.candidate);
    }, false);
  }

  async getStream() {
    if (this._stream) {
      await this.toggleSend(true);
      return this._stream;
    }

    const streamPromise = new Promise((resolve) => {
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

  async addStream(stream) {
    const pc = this._pc;
    stream.getTracks().forEach((track) => {
      pc.addTrack(track, stream);
    });
    await execAsync("agentStart");
  }

  async toggleSend(enable) {
    return execAsync("agentSend", enable);
  }

  async _answer(offer) {
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
          cordova.fireDocumentEvent(`webrtc.${event.type}`, event.data);
        },
        () => {},
        SERVICE,
        "ready",
      );
    }, false);
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

  __configAudio(opts) {
    return execAsync("configAudio", opts);
  }

  __toggleSender(enable) {
    return execAsync("toggleSender", enable);
  }
}

module.exports = new WebRTCPlugin();

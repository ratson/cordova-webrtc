const SERVICE = "WebRTC";

const execAsync = (method, ...args) =>
  new Promise((resolve, reject) => {
    cordova.exec(resolve, reject, SERVICE, method, args);
  });

class Agent {
  constructor() {
    const pc = new RTCPeerConnection({});
    this._pc = pc;

    pc.onicecandidate = async (event) => {
      if (event.candidate) {
        await execAsync("agentCandidate", e.candidate);
      }
    };
    pc.ontrack = (event) => {
      const stream = event.streams[0];
      this._stream = stream;
    };

    document.addEventListener("webrtc.agent.offer", async (data) => {
      await pc.setRemoteDescription(data.offer);

      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await execAsync("agentAnswer", answer);
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
      pc.addEventListener("track", (e) => {
        const stream = e.streams[0];
        resolve(stream);
      }, { once: true, passive: true });
    });

    await execAsync("agentStart");
    await this.toggleSend(true);
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
}

class WebRTCPlugin {
  agent = new Agent();

  constructor() {
    document.addEventListener("deviceready", () => {
      cordova.exec(
        (event) => {
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

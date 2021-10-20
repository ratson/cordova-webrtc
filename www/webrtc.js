const execAsync = (method, ...args) =>
  new Promise((resolve, reject) => {
    cordova.exec(resolve, reject, "WebRTC", method, args);
  });

class WebRTCPlugin {
  constructor() {
    document.addEventListener("deviceready", () => {
      cordova.exec(
        (event) => {
          cordova.fireDocumentEvent(`webrtc.__.${event.type}`, event.data);
        },
        () => {},
        "WebRTC",
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

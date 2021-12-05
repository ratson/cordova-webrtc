# cordova-webrtc

## Installation

```sh
cordova plugin add cordova-webrtc --save
```

update `config.xml` with the following content,

```xml
<widget>
    <preference name="scheme" value="https" />
    <preference name="hostname" value="localhost" />
    <allow-navigation href="https://localhost/*"/>
    <platform name="ios">
        <preference name="AllowInlineMediaPlayback" value="true" />
        <preference name="deployment-target" value="14.3" />
        <preference name="SwiftVersion" value="5.3" />
    </platform>
</widget>
```

## Status

This is an expiremental Cordova plugin for using WebRTC.

Android has good support for using WebRTC in webview, by setting the neccessary permissions through this plugin, it works flawlessly.

Recent iOS webview provides some support for WebRTC, but the integration is not good, especially when use with media playback or in background. This plugin provides an `agent` API to workaround it. The idea is to establish a peer connection between native code and webview for `getUserMedia()`, then forward the stream to other peer connections.

Some example usage could be found in [cordova-webrtc-lab repo](https://github.com/ratson/cordova-webrtc-lab). Feel free to opne new issues if there is any questions.

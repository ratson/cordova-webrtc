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

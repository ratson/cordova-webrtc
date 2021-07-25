# cordova-webrtc

## Installation

```sh
cordova plugin add cordova-webrtc --save
```

update `config.xml` with the following content,

```xml
<widget>
    <preference name="scheme" value="app" />
    <preference name="hostname" value="localhost" />
    <platform name="ios">
        <preference name="AllowInlineMediaPlayback" value="true" />
    </platform>
</widget>
```

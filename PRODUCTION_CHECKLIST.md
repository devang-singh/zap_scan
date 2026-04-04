# Production Readiness & Bulletproofing Guide for `zap_scan`

To ensure `zap_scan` runs flawlessly in production, follow this checklist to configure your host application correctly.

## 1. Platform Permissions

### Android (`AndroidManifest.xml`)
The plugin handles its own dependencies, but your app must declare these permissions in `<your_app>/android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.NFC" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.nfc" android:required="false" />
    
    <application ...>
        <!-- For NFC support -->
        <intent-filter>
            <action android:name="android.nfc.action.NDEF_DISCOVERED"/>
            <category android:name="android.intent.category.DEFAULT"/>
        </intent-filter>
    </application>
</manifest>
```

### iOS (`Info.plist`)
Add the following keys to `<your_app>/ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to scan your card and boarding pass.</string>
<key>NFCReaderUsageDescription</key>
<string>We need NFC access to read your contactless card details.</string>
```

## 2. NFC Configuration (iOS)

To enable NFC on iOS, you must add the NFC entitlement to your 프로젝트:
1. In Xcode, go to **Signing & Capabilities**.
2. Click **+ Capability** and add **Near Field Communication Tag Reading**.
3. Ensure your `Runner.entitlements` includes:
   ```xml
   <key>com.apple.developer.nfc.readersession.formats</key>
   <array>
       <string>NDEF</string>
       <string>TAG</string>
   </array>
   ```

## 3. Min SDK & Build Settings

### Android
Ensure `minSdkVersion` is set to **21** in `android/app/build.gradle`.

### iOS
Ensure `IPHONEOS_DEPLOYMENT_TARGET` is set to **16.0** in your Xcode project settings.

## 4. Proguard / R8 (Android)
If you enable shrinking/obfuscation, add these rules to `android/app/proguard-rules.pro`:

```proguard
# ML Kit Text Recognition
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.mlkit.vision.text.** { *; }

# NFC Manager
-keep class io.flutter.plugins.nfcmanager.** { *; }
```

## 5. UI/UX "Bulletproofing"

- **Glare Detection**: Use the `glareDetected` observable in `UniversalScannerController`. If `true`, show a subtle toast or overlay saying *"Tilt your card to avoid glare"* to improve OCR success rates.
- **Vibration Feedback**: Trigger a haptic feedback (`HapticFeedback.heavyImpact()`) as soon as `onResultScanned` is called. It makes the app feel responsive and "premium".
- **Camera Lifecycle**: Always use `ZapScanWidget` inside a screen that manages the controller. Ensure `controller.stopCamera()` is called in `dispose` (the widget does this automatically if you pass the controller).

## 6. Performance Optimization

- **Selective Scanning**: If you only need cards, set `scanBarcodes: false` in the controller. This reduces CPU usage by stopping the barcode detection loop.
- **Image Enhancement**: Turn it on only when detection is slow. It's powerful for embossed cards but adds processing overhead per frame.

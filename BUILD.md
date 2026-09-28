# Gaming DNS - Build

## Local build

This repository contains the application code and the Android app-specific files. If the Flutter Android Gradle wrapper is missing on a fresh checkout, run:

```bash
flutter pub get
flutter create --platforms=android --org com.example --project-name gaming_dns .
flutter pub get
flutter build apk --release
```

If `flutter create` regenerates `AndroidManifest.xml` or the Kotlin files, restore the project versions of:

- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/example/gaming_dns/MainActivity.kt`
- `android/app/src/main/kotlin/com/example/gaming_dns/GamingVpnService.kt`

## GitHub Actions

Push to `main` or start **Build Gaming DNS APK** manually from Actions. The workflow pins Flutter 3.38.1, generates the matching Android/Gradle platform, restores the VPN files, runs `flutter analyze`, and builds the release APK.

The resulting artifact is:

`build/app/outputs/flutter-apk/app-release.apk`

## Important VPN limitation

The Android service in this project creates a DNS-oriented `VpnService` profile. It does **not** implement a full packet-forwarding/tunneling engine. It should not be advertised as a general VPN or traffic optimizer. For a true DNS interception VPN, a TUN packet loop and DNS proxy/forwarder are required.

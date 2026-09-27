# Palmy native clients

`android/` is a Kotlin and Jetpack Compose application. `ios/` is a SwiftUI application with a separately testable Swift package, `PalmyCore`. There is no Flutter runtime, web view, or shared UI framework. Both use the Indonesian interface, palette, navigation, exact decimal strings and API contract in [the protocol](../docs/protocol.md).

The implemented slice supports account creation with recovery acknowledgement, recovery, encrypted profile editing, live summaries/wallets/history, wallet creation, income/expense posting, pagination, refresh and session revocation. Data comes from the API; the UI contains no sample financial balances. Financial corrections, transfers and the remaining source PRD modules are not implemented here.

## Run iOS

Open `ios/Palmy.xcodeproj`, select the shared **Palmy** scheme and an iOS simulator. The checked-in project is ready to build; no project generator is needed to use it. Minimum deployment target is iOS 17. Xcode 27 and Swift 6.4 were used locally.

Debug connects to `http://127.0.0.1:8100/api/v1`. Start the repository's development API first. For a physical device or Release build, supply the real HTTPS endpoint through the `PALMY_API_URL` Xcode build setting. The endpoint includes `/api/v1`. Release contains no fabricated hostname and refuses to operate if the setting is missing. Release has no HTTP transport exception. Debug allows only local networking, and the API client also restricts HTTP to loopback hosts.

```sh
cd mobile/ios
swift test
PALMY_TEST_API_URL=http://127.0.0.1:8100 swift test
xcodebuild -project Palmy.xcodeproj -scheme Palmy -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

The second test command uses fresh synthetic accounts against a disposable API. Without the environment variable, the live integration test reports an explicit skip; cryptography, validation and network policy tests still run. The live test checks registration, both profile directions, exact finance, idempotency, recovery and revocation. It does not test the SwiftUI interface.

To regenerate the Xcode project after adding source files, install the generator locally and run the checked-in script:

```sh
gem install xcodeproj --version 1.28.1 --install-dir .tools/gems --no-document
GEM_HOME="$PWD/.tools/gems" ruby tools/generate-project.rb
```

## Run Android

Open `android/` in Android Studio. Minimum Android API 28; compile/target SDK 36. Versions are pinned: AGP 9.1.1, Gradle 9.3.1, Compose BOM 2026.03.01, Kotlin Compose compiler 2.2.10. The Compose BOM is selected for SDK 36 compatibility. The Gradle wrapper JAR matches the official published checksum; the distribution checksum is pinned in `gradle-wrapper.properties`.

Debug connects to `http://10.0.2.2:8100/api/v1`, the emulator's host alias. Release requires the real HTTPS endpoint as the Gradle project property `PALMY_API_URL`. Missing configuration fails closed. Only Debug has a cleartext exception for emulator/loopback hosts. No credentials or API endpoint editor appear in product onboarding.

On this Mac, Android Studio includes a JDK and the Android SDK is already installed:

```sh
cd mobile/android
export JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
PALMY_TEST_API_URL=http://127.0.0.1:8100 ./gradlew :app:testDebugUnitTest --rerun-tasks
```

On other hosts, use a Gradle 9.3 compatible JDK and set `ANDROID_HOME` to the installed SDK. The live JVM test uses OkHttp, the same crypto library and API implementation as the app. The environment variable is optional; omission skips only that test. [Android lifecycle validation](android/TESTING.md) describes the actual-model regressions and four instrumented Activity scenarios. [iOS validation](ios/README.md) covers its model regressions and simulator UI checks.

## Key handling and privacy

Both clients derive independent signing/profile keys from the same recovery format and verify the shared [public test vectors](../contracts/crypto-vectors.json). iOS uses CryptoKit HKDF/AES-GCM/Ed25519. Android uses Bouncy Castle HKDF/Ed25519 and platform JCA AES-GCM. Production encryption always generates a fresh 12-byte nonce. No handcrafted cipher or curve implementation is included.

CryptoKit deliberately randomizes Ed25519 signatures. iOS verifies both the published signatures and locally generated signatures against the same public key/messages; it does not assert byte-for-byte signature equality. Android's deterministic signatures match the fixture exactly. See [Apple's signature documentation](https://developer.apple.com/documentation/cryptokit/curve25519/signing/privatekey/signature(for:)).

Recovery secrets, authentication tokens, decrypted profiles and account data remain in process memory. They are never saved to defaults, preferences, state restoration, files or logs. There is no remember-device feature and no claim that a Keychain/Keystore persistence layer is implemented. The [credential-lifecycle proposal](../docs/credential-lifecycle.md) separates future scoped device credentials from root recovery authority. Adding persistence requires that protocol's review, platform Keychain/Keystore controls, backup exclusions and appropriate device authentication. The Android app already disables backup and screenshot capture; iOS hides the application contents while inactive.

Signed-in clients lock and attempt server revocation on backgrounding. In-flight sign-in is cancelled too, and generation checks prevent old responses from reopening a locked or replaced session. Idle onboarding stays in memory while switching to a password manager to save the newly generated recovery key. The account is not submitted until the user acknowledges saving it. Quitting during onboarding loses that unregistered key. If revocation cannot reach the API, local state is cleared and the UI explains the server session's one-hour lifetime.

Profile fields are encrypted before submission. Finance amounts, categories, descriptions and wallet names are deliberately readable; identity inference from those fields and metadata remains possible. Both interfaces communicate that boundary and ask users to omit personal details from finance fields. This is identity-field encryption, not a guarantee of anonymity.

## Validation boundaries

Shared crypto vectors, tamper/wrong-owner checks, exact decimal validation, HTTPS policies, native HTTP integration and debug builds are automated. Store signing, release distribution, physical-device checks, secure persistence, screen-reader testing and a complete native UI interaction matrix require additional work. Production endpoints and signing identities belong in deployment configuration, not sample source.

# Android lifecycle validation

`PalmyModelTest` uses the actual `PalmyModel` with its production cryptography and an injected `PalmyTransport`. A controlled coroutine dispatcher and explicitly released responses cover backgrounding during registration/recovery, late authentication and revocation, immediate local lock during refresh/posting, ViewModel disposal, and stable idempotency after a committed write or lost response. Tests do not rely on sleeps or real network timing.

`ActivityLifecycleTest` runs the actual `MainActivity` and Android main dispatcher. The instrumentation-only application factory substitutes HTTP transport, while the production ViewModel, Compose screen, `onStop`, recreation, and secure-window policy remain active. The four device scenarios cover recovery-key onboarding across background/recreation, backgrounded registration, backgrounded recovery with a late session, and rotation versus background locking after sign-in.

Use the installed SDK and a JDK compatible with Gradle 9.3.1. On the inspected macOS host:

```sh
export JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew --no-daemon :app:testDebugUnitTest :app:assembleDebug :app:lintDebug :app:assembleRelease :app:assembleDebugAndroidTest
PALMY_TEST_API_URL=http://127.0.0.1:8100 ./gradlew --no-daemon :app:testDebugUnitTest --rerun-tasks
```

The optional live API test is skipped only when `PALMY_TEST_API_URL` is absent. It exercises the production HTTP client, identity encryption, profile versioning, exact amounts, idempotency, recovery, and revocation against a disposable local account. Release assembly is unsigned; a real HTTPS endpoint and signing remain distribution requirements.

Run device lifecycle checks on a booted API 36 emulator (Linux CI: x86_64; Apple Silicon: arm64-v8a) or an attached supported Android device:

```sh
./gradlew --no-daemon :app:connectedDebugAndroidTest
```

These instrumented tests do not need a live API. Gradle uses `com.palmy.app.LifecycleTestRunner`, with test-only AndroidX core 1.7.0, runner 1.7.0, and JUnit extension 1.3.0. Results are in `app/build/reports/androidTests/connected/`; JVM results are in `app/build/reports/tests/testDebugUnitTest/`.

The model preserves an unsubmitted recovery-key screen while the owner saves the key in a password manager. Once authentication begins, backgrounding cancels work, releases candidates and private state immediately, and revokes any session returned late. A configuration change retains the existing ViewModel. After a confirmed write, the form's save counter advances once even if refresh fails; repeat submissions retain the idempotency key until a successful refresh confirms current data. Unknown write outcomes also retain the key for the same draft. No keys, tokens, or retry state are persisted across process death or locking.

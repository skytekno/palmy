# iOS verification

The SwiftUI app uses the same `PalmyCore.AppModel` exercised by the package tests. A
`PalmyService` dependency supplies transport; the app always supplies the real `API`.
Tests hold individual responses with continuations, release them after lock or a newer
login, and assert state and request effects without timing sleeps.

From the repository root:

```sh
swift test --package-path mobile/ios
PALMY_TEST_API_URL=http://127.0.0.1:8100 swift test --package-path mobile/ios
python3 mobile/ios/tools/test-simulator.py
PALMY_UI_LIVE_API=1 python3 mobile/ios/tools/test-simulator.py
```

The package suite contains 13 app-state regressions, 5 identity/money/network-policy
tests, and 1 HTTP interoperability test. The HTTP test skips unless
`PALMY_TEST_API_URL` is set. Use a disposable local API: the live tests create
synthetic accounts and financial records.

The app-state regressions cover queued and in-flight authentication on background,
idle recovery-key onboarding, stale authentication/profile responses, immediate
local lock while revocation hangs or fails, stale revocation feedback, initial
dashboard failure, committed writes followed by failed refresh, and ambiguous
write-response retries with stable idempotency keys. Confirmed writes retain their
retry key until a successful refresh; repeated stale submissions do not double-count
form-reset signals, and a fresh snapshot permits a new identical write. These are model tests, not UI
tests. Shared cryptographic vectors and real HTTP tests verify a separate boundary.

The simulator suite launches the real SwiftUI app and drives two lifecycle cases:
idle onboarding survives Home/reactivation, and an authenticated app returns locked
after Home/reactivation. Only the second case requires `PALMY_UI_LIVE_API=1` and the
Debug API at `127.0.0.1:8100`. Without that flag it is explicitly skipped. The suite
does not claim UI coverage of financial entry or all device lifecycle permutations.

The runner selects an available iPhone from `simctl` JSON, preferring a booted device.
Set `PALMY_SIMULATOR_ID` to select an installed device explicitly. It fails if no iPhone
runtime is installed; it does not skip the simulator gate silently. CI needs macOS,
Xcode with an available iOS simulator, Python 3, and the checked-in project and scheme.
No Ruby dependency is needed to build or run tests. To regenerate the project after
adding app/core/test sources, use `ruby mobile/ios/tools/generate-project.rb` with the
`xcodeproj` gem available.

Unsigned simulator build checks:

```sh
xcodebuild -project mobile/ios/Palmy.xcodeproj -scheme Palmy \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project mobile/ios/Palmy.xcodeproj -scheme Palmy \
  -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

These checks do not verify device signing, distribution, or production endpoint
configuration. Release uses the `PALMY_API_URL` build setting through its Info.plist
and refuses requests when it is absent or invalid. Debug uses the local development
endpoint. Recovery material remains memory-only; background lock requires recovery
to sign in again. Protocol design and secure persistent storage remain separate work.

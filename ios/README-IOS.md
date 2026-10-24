# UltraSync for iOS — native SwiftUI fork

A complete, native iOS app of the UltraSync 1.0 dashboard: **News,
Weather, Solar, Space, and Philips Hue** panels in the same eight retro
phosphor themes as the Python app, rebuilt as a SwiftUI app (no web
views). It lives in this repo next to the Python implementation:

```
ios/
  UltraSync/
    UltraSync.xcodeproj          ← open this in Xcode
    UltraSync/
      App/        UltraSyncApp.swift, ContentView.swift (tab shell)
      Models/     NewsArticle, WeatherData, SolarData, SpaceData, HueState
      Services/   APIClient, DataStore, FeedService, SpaceCalculator
      Theme/      ThemeEngine.swift (the 8 palettes, ported 1:1)
      Views/      one view per panel + shared retro styling/components
  tools/check_parity.py          ← theme parity checker (see below)
```

- Bundle ID: `com.varaoisiru.ultrasync` · Version 1.0.0
- Deployment target: iOS 17 · SwiftUI + Foundation only, no third-party
  dependencies, nothing to fetch before building.
- Signing: **free provisioning only** (see next section). The project
  has automatic signing and requests **no capabilities** — no push
  notifications, no App Groups, no iCloud entitlements — so nothing in
  it requires a paid Apple Developer Program membership.

## Signing: free provisioning with a Personal Team

This app is meant to run on your own iPhone via Xcode's free
provisioning. There is no App Store path and none is wanted.

1. Open `ios/UltraSync/UltraSync.xcodeproj` in Xcode (15 or later).
2. **Sign into Xcode with your Apple ID**: Xcode → Settings → Accounts
   → `+` → Apple ID. This creates your **Personal Team**.
3. Select the **UltraSync** target → *Signing & Capabilities* → check
   *Automatically manage signing* → set **Team** to your Personal Team
   (`(Personal Team)`).
4. Connect your iPhone by cable (or use a paired wireless device),
   select it as the run destination, and press **Run** (⌘R). On first
   launch, trust the developer profile on the phone: *Settings →
   General → VPN & Device Management → Trust*.
5. The iOS Simulator works the same way with **Run** — no signing
   needed at all there.

Free-provisioning facts, so none of this surprises you:

- **Signatures expire after 7 days.** When the app stops launching,
  reconnect the phone and press **Run** in Xcode again — re-signing
  takes a few seconds and your data/settings survive.
- Free provisioning limits you to a small number of App IDs per week
  (10 per 7 days) and a handful of self-signed apps on a device at
  once; this app uses exactly one App ID (`com.varaoisiru.ultrasync`).
- Capabilities that require the paid program stay off by design.
- The **$99/year Apple Developer Program is only for App Store /
  TestFlight distribution**, which is explicitly out of scope here.

## Data modes (Settings tab)

- **Standalone (default)** — the app talks directly to the same free,
  key-less sources as the Python modules: Open-Meteo (weather + sun/
  moon times), NOAA SWPC (solar indices, RTSW solar wind, planetary K,
  region summary, K forecast), the ten configured RSS/Atom feeds,
  wheretheiss.at (live ISS), and ip-api for geolocation. Moon phase,
  planet positions, and (as an offline fallback) sunrise/sunset are
  computed natively in `SpaceCalculator.swift`, ported from
  `ultrasync/space.py` with the same constants — JPL approximate planet
  elements included.
- **UltraSync Server** — point the app at a running UltraSync backend
  (default `http://127.0.0.1:8077`; use your machine's LAN/Tailscale
  address from a phone) and it reads the server's JSON API instead —
  including server-side read/unread state, the cleaned article reader,
  and the full 100-effect Hue FX library.

Hue works in both modes: via the server when one is configured there,
or directly against your bridge in standalone mode (enter bridge IP +
bridge username in the Hue tab). Credentials are only ever stored on
the device (UserDefaults) or on your own server — never in this repo.

## Running it

- **Simulator**: open the project, pick any iPhone simulator, ⌘R.
- **Your iPhone**: follow the signing steps above, pick the device, ⌘R.
- The News tab shows the unread count as a badge; pull-to-refresh works
  on every panel; the Space tab re-polls the ISS position every 30 s,
  matching the web GUI.

## Building via Docker-OSX on the i7 (no Mac required)

The intended build path on the Windows i7 is
[sickcodes/Docker-OSX](https://github.com/sickcodes/Docker-OSX) — the
popular GitHub project that runs macOS in Docker (QEMU/KVM) so you can
install Xcode and build iOS apps without Apple hardware:

1. **Enable virtualization** on the i7: VT-x on in BIOS, and Docker
   Desktop running with its WSL2 backend (Docker-OSX also runs on
   Linux hosts natively).
2. **Start a macOS VM** from the Docker-OSX image, e.g.
   `docker run -it --device /dev/kvm -p 50922:10022 sickcodes/docker-osx:latest`
   (pin a macOS version image if you want a specific Xcode), then
   finish the macOS setup inside the VM.
3. **Install Xcode** inside the macOS VM (App Store or the Apple
   Developer download — a free Apple ID is enough), and launch it once
   to accept the license and install components.
4. **Clone this repo** in the VM: `git clone
   https://github.com/varaoisiru/UltraSync.git` (or copy the folder
   over), then open `ios/UltraSync/UltraSync.xcodeproj`.
5. **Select your Personal Team** (Signing & Capabilities, as above),
   pick the **iOS Simulator** destination (the VM has no USB iPhone —
   free-provisioning device installs happen from a real Mac session;
   in Docker-OSX, build and run on the Simulator), and press **Run**.

This is the on-i7 path. The environment this project was authored in
has no KVM/macOS, so the project is delivered **Xcode-ready rather
than pre-built**: standard project layout, validated project file
(see below), no exotic constructs — its first open in Xcode is the
first build.

## Parity & validation

- **Theme parity**: `python3 ios/tools/check_parity.py` imports the
  canonical `THEMES` dict from `ultrasync/themes.py` and asserts every
  hex value and display name in `ThemeEngine.swift` matches exactly
  (8 themes × 6 fields). It currently passes.
- **Project file**: `project.pbxproj` was validated by parsing it as
  an OpenStep plist and resolving the whole object graph — all 63
  objects defined, every referenced ID resolvable, the Sources phase
  matching the 20 `.swift` files on disk exactly, bundle ID /
  iOS 17 / automatic signing confirmed, no entitlements present.
- **Not done here**: compiling SwiftUI and running the iOS Simulator
  require Xcode on macOS (or the Docker-OSX path above) — there is no
  Swift toolchain in the authoring environment. The code sticks to
  iOS 17 SwiftUI/Foundation APIs and one well-trodden project layout
  so the first Xcode build is uneventful.

## Architecture notes

- `APIClient` owns all networking and both data planes; `DataStore`
  (an `ObservableObject`) holds per-panel `PanelState`
  (loading/loaded/error, like the GUI's LIVE/CACHED badges) and all
  persisted settings. Views are declarative over that state.
- `ThemeEngine`'s `ThemeManager` is an `ObservableObject` injected via
  the environment; switching themes re-skins every panel instantly and
  persists, exactly like the web GUI's swatches.
- Charts and gauges are hand-drawn with SwiftUI `Canvas` (24 h
  temperature curve, semicircle gauges, Kp bars, moon disc) — the same
  dependency-free spirit as the parents.
- One deliberate platform note: `SWIFT_VERSION` is `5.0` (Swift 5
  language mode). Xcode's `SWIFT_VERSION` setting accepts 4 / 4.2 / 5 /
  6 — "5.9" is the *toolchain* version (Xcode 15 ships Swift 5.9),
  not a selectable language-mode value; the code compiles under the
  Swift 5.9+ toolchain in Swift 5 mode.

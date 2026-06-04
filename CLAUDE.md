# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Two-app system for device-wide iOS GPS spoofing (including Find My) via Apple's Developer Services. An **iOS app** selects a location and sends it to a **macOS menu bar app**, which executes `pymobiledevice3` to apply the spoof over USB.

## Build & Run

Both projects use **xcodegen** to generate `.xcodeproj` files from `project.yml` specs.

```bash
# Regenerate Xcode projects after adding/removing files
cd LocationSpoof && xcodegen generate
cd LocationSpoofMac && xcodegen generate

# Build from command line (prefer building in Xcode directly)
xcodebuild -project LocationSpoof/LocationSpoof.xcodeproj -scheme LocationSpoof -sdk iphonesimulator build
xcodebuild -project LocationSpoofMac/LocationSpoofMac.xcodeproj -scheme LocationSpoofMac build

# Run tests
xcodebuild test -project LocationSpoof/LocationSpoof.xcodeproj -scheme LocationSpoof -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -project LocationSpoofMac/LocationSpoofMac.xcodeproj -scheme LocationSpoofMac

# Run a single test class or method (-only-testing: Target/Class[/method])
xcodebuild test -project LocationSpoof/LocationSpoof.xcodeproj -scheme LocationSpoof -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LocationSpoofTests/SpoofMessageTests

# Launch everything (starts tunnel daemon, builds macOS app, opens iOS project)
./start.sh

# Teardown
./stop.sh
```

**Deployment targets:** iOS 17.0+, macOS 14.0+

## Architecture

```
iPhone (iOS App)                    Mac (Menu Bar App)
┌─────────────────┐                ┌──────────────────────┐
│ SpoofService    │──Bonjour TCP──▶│ BonjourServer        │
│ (orchestrator)  │   or HTTP      │ HTTPServer (port 8765)│
│                 │                │         │             │
│ BonjourClient   │                │ CommandHandler        │
│ RemoteSpoofClient│               │         │             │
└─────────────────┘                │ DeviceService         │
                                   │    └─ pymobiledevice3 │
                                   └──────────────────────┘
```

**Communication:** Newline-delimited JSON over TCP (Bonjour `_locspoof._tcp`) or HTTP REST (port 8765 for remote/Tailscale access).

**Message protocol** (in `Shared/Models/`):
- `SpoofMessage`: `{action: "set"/"clear"/"ping", lat?, lng?}`
- `SpoofResponse`: `{status: "ok"/"error"/"pong", spoofing?, lat?, lng?, message?, device?}`

**HTTP REST API** (`HTTPServer`, port 8765) — mirrors the Bonjour actions for remote/Tailscale clients:
- `GET /status` (and `GET /`) → current `SpoofResponse` (status, spoofing, lat/lng).
- `POST /set` with JSON body `{lat, lng}` → applies the spoof.
- `POST /clear` → clears the spoof.
- `GET /dashboard` → self-contained HTML control page (the `dashboardHTML` string), usable from any browser without the iOS app.

**Connection routing:** `SpoofService.start()` checks for a configured remote URL (`RemoteConfig`). If set, uses `RemoteSpoofClient` (HTTP); otherwise uses `BonjourClient` (local Bonjour discovery).

## Key Files

| File | Role |
|------|------|
| `LocationSpoof/Services/SpoofService.swift` | iOS orchestrator — routes to local or remote client |
| `LocationSpoof/Services/BonjourClient.swift` | Bonjour discovery + TCP connection to Mac |
| `LocationSpoof/Services/RemoteSpoofClient.swift` | HTTP client for remote Mac access |
| `LocationSpoofMac/Services/CommandHandler.swift` | Mac-side message dispatcher |
| `LocationSpoofMac/Services/DeviceService.swift` | Wraps pymobiledevice3 CLI subprocess |
| `LocationSpoofMac/Services/BonjourServer.swift` | Listens for iOS connections over Bonjour |
| `LocationSpoofMac/Services/HTTPServer.swift` | Optional REST API for remote clients |
| `Shared/Models/SpoofMessage.swift` | Shared request type |
| `Shared/Models/SpoofResponse.swift` | Shared response type |
| `scripts/remote-tunnel.py` | Standalone off-LAN helper (not yet wired into the app — see below) |

## Important Conventions

- **Shared models** live in `Shared/Models/` and are referenced by both `project.yml` files via path includes. When adding shared types, add them there and update both specs.
- **CoreData model** is defined programmatically in `PersistenceController.swift` (no `.xcdatamodeld` file) because xcodegen handles it better this way.
- **macOS app runs without sandbox** (`com.apple.security.app-sandbox: false`) to allow subprocess execution of pymobiledevice3.
- **pymobiledevice3 timeout:** `DeviceService` uses a 10-second timeout because the `simulate-location set` command often hangs after successfully applying the spoof. An empty stdout after timeout is treated as success.
- **pymobiledevice3 path:** DeviceService searches `~/.local/bin/pymobiledevice3` first (pipx install location), then falls back to `PATH`.
- **Spoof persistence / keepalive:** The simulated location is a live DVT session, not stored on the device — it dies when the Mac↔device tunnel drops (e.g. phone leaves WiFi). `CommandHandler` tracks `desiredSpoofing` intent separately from `isSpoofing`, re-applies the location every 30s via a keepalive timer, and persists/restores state across relaunch. The iOS `SpoofService` persists intent and re-asserts the last location on reconnect; `RemoteSpoofClient` polls `/status` every 5s. Off-WiFi persistence requires Tailscale so the Mac can still reach the device. See `docs/remote-persistence.md`.
- **Bonjour service type:** `_locspoof._tcp` — declared in iOS `Info.plist` and used by both apps for discovery.
- **App Transport Security:** the iOS app sets `NSAppTransportSecurity → NSAllowsArbitraryLoads: true` so `RemoteSpoofClient` can reach the Mac's HTTP API over cleartext `http://<mac>:8765` (and Tailscale IPs). Without it, iOS blocks the request with "the resource could not be loaded… requires a secure connection." Bonjour mode uses a raw TCP socket and is unaffected. This lives in `LocationSpoof/project.yml` under `info.properties` (the source of truth) — editing the generated `Info.plist` directly is overwritten by `xcodegen generate`.
- **Off-LAN tunnel is not yet integrated:** the app's `DeviceService` drives `simulate-location` via `tunneld` (USB/LAN only). `scripts/remote-tunnel.py` is a researched/standalone path that reaches the device over Tailscale by IP (`CoreDeviceTunnelProxy` + `--rsd`, iOS 17.4+) and holds the spoof on a keepalive — but it must be validated live before being wired into `DeviceService`. Full rationale and setup in `docs/remote-persistence.md`.
- **SwiftUI + @Observable:** Both apps use the Observation framework (`@Observable` macro), not the older `ObservableObject`/`@Published` pattern.

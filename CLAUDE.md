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

## Important Conventions

- **Shared models** live in `Shared/Models/` and are referenced by both `project.yml` files via path includes. When adding shared types, add them there and update both specs.
- **CoreData model** is defined programmatically in `PersistenceController.swift` (no `.xcdatamodeld` file) because xcodegen handles it better this way.
- **macOS app runs without sandbox** (`com.apple.security.app-sandbox: false`) to allow subprocess execution of pymobiledevice3.
- **pymobiledevice3 timeout:** `DeviceService` uses a 10-second timeout because the `simulate-location set` command often hangs after successfully applying the spoof. An empty stdout after timeout is treated as success.
- **pymobiledevice3 path:** DeviceService searches `~/.local/bin/pymobiledevice3` first (pipx install location), then falls back to `PATH`.
- **Bonjour service type:** `_locspoof._tcp` — declared in iOS `Info.plist` and used by both apps for discovery.
- **SwiftUI + @Observable:** Both apps use the Observation framework (`@Observable` macro), not the older `ObservableObject`/`@Published` pattern.

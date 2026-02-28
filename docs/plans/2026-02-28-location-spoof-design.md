# Location Spoof — Design Document

**Date:** 2026-02-28
**Status:** Approved

## Overview

Location Spoof is a two-app system that spoofs device-wide GPS location on iOS, including Find My and all other apps. It uses Apple's Developer Services simulated location feature via `pymobiledevice3`.

## Architecture

```
iOS App (SwiftUI)  ── Bonjour/TCP ──►  macOS Menu Bar App (SwiftUI)
                                              │
                                              │ pymobiledevice3
                                              ▼
                                        iPhone Device
                                        (Developer Mode)
                                        System-wide GPS spoofed
```

### Flow

1. User opens iOS app, picks a location on the map or selects a favorite
2. Taps "Spoof Location"
3. iOS app sends `{lat, lng}` to the macOS app over Bonjour
4. macOS app runs `pymobiledevice3 developer dvt simulate-location set --lat X --lng Y`
5. Device-wide GPS is now faked — Find My, Maps, all apps see the new location
6. To stop: user taps "Reset Location", macOS app runs `simulate-location clear`

## iOS App

**Tech stack:** SwiftUI, MapKit, CoreData, Network framework

### Screens

**Main Screen (Map View)**
- Full-screen MapKit map with draggable pin
- Search bar (MapKit geocoding) for finding locations by name/address
- Bottom card with:
  - Selected coordinates display
  - "Spoof Location" button
  - "Reset to Real Location" button (when active)
  - Connection status indicator

**Favorites Screen**
- List of saved locations (name, address, coordinates)
- Tap to select, swipe to delete
- Add button saves current pin with custom name

**Settings Screen**
- Mac app connection status & device info
- Auto-reconnect toggle
- Setup instructions

### Data Model (CoreData)

```
SavedLocation
  - id: UUID
  - name: String
  - latitude: Double
  - longitude: Double
  - address: String (optional)
  - createdAt: Date
```

## macOS Menu Bar App

**Tech stack:** SwiftUI, Network framework, Process (pymobiledevice3 CLI)

### UI

- Menu bar icon (location pin) with color states:
  - Gray: No device connected
  - Blue: Device connected, not spoofing
  - Green: Actively spoofing
- Click to see: device name, current spoofed coordinates, "Clear Spoof" button, "Quit"

### Behavior

1. Starts Bonjour service (`_locspoof._tcp`) on launch
2. Listens for iOS app connections
3. On `set` command: runs `pymobiledevice3 developer dvt simulate-location set --lat {lat} --lng {lng}`
4. On `clear` command: runs `pymobiledevice3 developer dvt simulate-location clear`
5. Returns status to iOS app

### pymobiledevice3

- App checks for pymobiledevice3 availability on launch
- Guides user through installation if not found
- Future: bundle standalone binary in app Resources

## Communication Protocol

**Discovery:** Bonjour, service type `_locspoof._tcp`

**Message format:** Newline-delimited JSON over TCP

```
iOS → Mac:
  {"action": "set", "lat": 35.6762, "lng": 139.6503}
  {"action": "clear"}
  {"action": "ping"}

Mac → iOS:
  {"status": "ok", "spoofing": true, "lat": 35.6762, "lng": 139.6503}
  {"status": "ok", "spoofing": false}
  {"status": "error", "message": "Device not connected"}
  {"status": "pong", "device": "Anthony's iPhone", "spoofing": false}
```

**Connection lifecycle:**
- macOS app starts Bonjour listener on launch
- iOS app discovers service, connects
- iOS sends `ping` to confirm and get state
- User actions send `set` or `clear`
- Auto-reconnect every 3 seconds on disconnect
- Single iOS client at a time

**Error handling:**
- Device not in Developer Mode → setup instructions
- Device not paired → USB pairing guide
- pymobiledevice3 not found → install instructions
- Connection lost → auto-reconnect with status indicator

## Project Structure

```
Location Spoof iOS/
├── LocationSpoof/                    # iOS App
│   ├── LocationSpoof.xcodeproj
│   ├── LocationSpoof/
│   │   ├── App/
│   │   │   └── LocationSpoofApp.swift
│   │   ├── Views/
│   │   │   ├── MapView.swift
│   │   │   ├── FavoritesView.swift
│   │   │   ├── SettingsView.swift
│   │   │   └── LocationCardView.swift
│   │   ├── Models/
│   │   │   └── SavedLocation.swift
│   │   ├── Services/
│   │   │   ├── BonjourClient.swift
│   │   │   └── SpoofService.swift
│   │   └── Resources/
│   │       └── LocationSpoof.xcdatamodeld
│   └── Info.plist
│
├── LocationSpoofMac/                 # macOS Menu Bar App
│   ├── LocationSpoofMac.xcodeproj
│   ├── LocationSpoofMac/
│   │   ├── App/
│   │   │   └── LocationSpoofMacApp.swift
│   │   ├── Views/
│   │   │   └── MenuBarView.swift
│   │   ├── Services/
│   │   │   ├── BonjourServer.swift
│   │   │   ├── CommandHandler.swift
│   │   │   └── DeviceService.swift
│   │   └── Resources/
│   └── Info.plist
│
└── docs/
    └── plans/
```

## Build Targets

- iOS app: iOS 16+, SwiftUI, MapKit, Network framework
- macOS app: macOS 13+, SwiftUI, Network framework

## Prerequisites for Users

1. iPhone has Developer Mode enabled (Settings > Privacy & Security > Developer Mode)
2. iPhone paired with Mac at least once via USB
3. pymobiledevice3 installed on Mac

# Off-WiFi Location Persistence

**Date:** 2026-05-31
**Status:** Implemented

## The problem

The last time the app was used, the spoofed location reset to the real location
the moment the iPhone left the Mac's WiFi network.

## Why it happens (root cause)

`pymobiledevice3 developer dvt simulate-location set` is **not stored on the
iPhone**. It is a live Developer Services session (DVT over the iOS 17+
RemoteXPC tunnel). The simulated location is held only while **both** of these
stay alive:

1. The `pymobiledevice3` process on the Mac that owns the DVT session.
   `DeviceService` deliberately leaves this process running after its 10s
   "hang" — that lingering process *is* the spoof.
2. The `pymobiledevice3 remote tunneld` tunnel from the Mac to the device.

When the phone is on the Mac's WiFi, that tunnel rides over the LAN. The instant
the phone leaves the network, the tunnel drops, the DVT session closes, and iOS
reverts to real GPS. A reboot does the same thing.

**Consequence:** the iPhone cannot hold a device-wide spoof by itself once it is
away from the host. Persisting it off-WiFi requires the Mac to keep a live tunnel
to the *device* over the internet.

## Two separate layers

| Layer | Responsibility | Component |
|-------|----------------|-----------|
| Transport | Keep the Mac able to reach the *device* off-LAN | Tailscale (VPN overlay) |
| Control | Let the iOS app send set/clear to the Mac off-LAN | HTTP API (`HTTPServer` + `RemoteSpoofClient`) |

The HTTP API alone only solves **control**. If the Mac cannot reach the device,
sending "set" just returns an error because `simulate-location` has nothing to
talk to. This is why Tailscale (which keeps the *phone* reachable from the Mac)
is required for persistence, whereas a plain Cloudflare Tunnel (which only
exposes the Mac's HTTP port) is not sufficient.

## What was implemented

### Mac (`CommandHandler`)
- **Spoof intent** (`desiredSpoofing`) is tracked separately from whether the
  device-side apply succeeded (`isSpoofing`).
- **Keepalive loop**: while spoofing is desired, the last location is re-applied
  every 30s. If the DVT session dropped during a transient network blip, this
  re-establishes it automatically — no user action needed.
- **Persistence + restore**: the desired state and coordinates are saved to
  `UserDefaults` and re-applied on app relaunch (`restoreIfNeeded()`).
- `/status` now returns the current coordinates so a reconnecting client can
  restore its map pin.

### iOS (`SpoofService` / `RemoteSpoofClient`)
- **Status polling**: in remote mode the client polls `/status` every 5s to keep
  connection state and the spoof location fresh.
- **Re-assert on reconnect**: the desired state and last location are persisted.
  If the Mac reports it is *not* spoofing while the user still wants it to be
  (e.g. after the phone rejoined the network), the app re-sends the last
  location — throttled to once every 8s so polling can't spam the Mac.

## Reaching the device off-LAN (researched method)

There are two separate channels and both must reach across the network:

1. **Control channel** (iOS app → Mac): the HTTP API on port 8765, reachable at
   the Mac's Tailscale IP. This is the easy part.
2. **Device channel** (Mac → iPhone): the pymobiledevice3 tunnel that actually
   carries `simulate-location`. This is the hard part, because `tunneld` only
   auto-discovers devices over USB and LAN Bonjour — neither of which works once
   the phone has left the network. Bonjour/mDNS does not cross a Tailscale link.

### How the device channel works off-LAN

iOS 17.4+ added a lockdown service (`CoreDeviceTunnelProxy`) that establishes the
trusted RemoteXPC tunnel over the *existing lockdown connection* — and lockdownd
can be reached over the network, not just USB. So the documented remote path is:

1. **Pair once over USB** (creates a trust/pair record on the Mac).
2. **Enable network access to lockdownd:** `pymobiledevice3 lockdown wifi-connections on`.
3. Later, with the phone reachable at its Tailscale IP, connect to lockdownd by
   IP and reuse the saved pair record:
   `create_using_tcp(<tailscale-ip>, autopair=False)`.
4. Start the tunnel over that connection (`CoreDeviceTunnelProxy` → `start_tunnel`),
   which yields an `--rsd <addr> <port>`.
5. Run `simulate-location set --rsd <addr> <port> -- <lat> <lng>` and re-apply on
   a keepalive loop.

`tunneld` cannot do steps 3–4 over Tailscale on its own, so this needs the
explicit-IP helper. See `scripts/remote-tunnel.py`, which performs the whole
flow and holds the location with a 30s keepalive.

### Setup

1. Install Tailscale on the Mac and the iPhone, same tailnet.
2. One time, with the iPhone plugged in via USB:
   - `pymobiledevice3 lockdown pair`
   - `pymobiledevice3 lockdown wifi-connections on`
   - `pymobiledevice3 mounter auto-mount` (Developer Mode + DDI)
3. Find the iPhone's Tailscale IP (Tailscale app on the phone, or `tailscale status` on the Mac).
4. Run: `sudo python3 scripts/remote-tunnel.py <iphone-tailscale-ip> <lat> <lng>`.
5. For app-driven control, also set the **Mac API URL** in iOS Settings to
   `http://<mac-tailscale-ip>:8765`.

## What works, and the honest limit

- **Unplugged, on Wi-Fi (same or a different Wi-Fi), reachable via Tailscale:**
  supported. This is the realistic target and removes the USB tether.
- **On cellular only:** unverified, and likely limited. lockdownd's network
  listener is historically a Wi-Fi-sync feature; whether iOS accepts the
  lockdown connection delivered over Tailscale's interface while the phone's only
  active path is cellular has to be tested on the actual device. Do not assume
  it works until confirmed.
- The Mac must stay awake; if it sleeps the tunnel drops. Use `caffeinate` while
  spoofing.
- A device reboot clears the spoof; re-run the helper / let the keepalive
  re-apply once the phone is reachable again.

### Integration plan (not yet wired into the app)

The menu bar app currently relies on `tunneld` + `simulate-location` with no
`--rsd`. To make off-LAN spoofing first-class, `DeviceService` would gain a
"remote tunnel" mode: when a device Tailscale IP is configured, it runs the
`remote-tunnel.py` flow (or the equivalent in-process Python), captures the
`--rsd` endpoint, and routes `setLocation` through it. The keepalive already
built into `CommandHandler` then maintains it. This step should be implemented
only after the method is validated live on the target device.

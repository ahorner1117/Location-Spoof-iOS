#!/usr/bin/env python3
"""
remote-tunnel.py — hold a device-wide location spoof alive over the network
(e.g. Tailscale), without USB.

This is the off-LAN counterpart to `tunneld`. `tunneld` only auto-discovers
devices over USB and LAN Bonjour, so it cannot reach a phone that has left your
network. This script instead connects to the device's lockdown daemon at an
explicit IP (its Tailscale address), starts the iOS 17.4+ lockdown tunnel over
that connection, and re-applies the simulated location on a keepalive loop.

ONE-TIME SETUP, while the iPhone is plugged into this Mac via USB:
    pymobiledevice3 lockdown pair                 # trust this Mac
    pymobiledevice3 lockdown wifi-connections on  # allow lockdownd over the network
    pymobiledevice3 mounter auto-mount            # ensure Developer Mode + DDI

REQUIREMENTS:
    - iOS 17.4 or later (uses CoreDeviceTunnelProxy over the lockdown channel,
      so no separate `remoted` pairing is needed).
    - Tailscale running on BOTH the Mac and the iPhone, same tailnet.
    - Run with sudo (the tunnel creates a utun interface).

USAGE:
    sudo python3 remote-tunnel.py <tailscale-ip> <lat> <lng>
    # example:
    sudo python3 remote-tunnel.py 100.101.102.103 37.7749 -122.4194

Press Ctrl+C to clear the spoof and tear down the tunnel.

NOTE: pymobiledevice3's Python API symbols occasionally move between releases.
If an import fails, check the installed version's
`pymobiledevice3/cli/lockdown.py` for the current `CoreDeviceTunnelProxy` /
`start_tunnel` entry points. This script was written against the documented API
on master and is intended to be validated against your device before wiring it
into the menu bar app.
"""
import asyncio
import subprocess
import sys

from pymobiledevice3.lockdown import create_using_tcp
from pymobiledevice3.remote.common import TunnelProtocol
from pymobiledevice3.remote.module_imports import start_tunnel
from pymobiledevice3.remote.tunnel_service import CoreDeviceTunnelProxy

KEEPALIVE_SECONDS = 30
APPLY_TIMEOUT = 20


def _simulate_location(args: list[str]) -> None:
    """Run a simulate-location subcommand, tolerating the hang that the
    `set` command sometimes exhibits after it has already applied."""
    try:
        subprocess.run(
            ["pymobiledevice3", "developer", "dvt", "simulate-location", *args],
            timeout=APPLY_TIMEOUT,
            check=False,
        )
    except subprocess.TimeoutExpired:
        # The location was applied; the process just didn't exit. Safe to ignore.
        pass


async def main(ip: str, lat: str, lng: str) -> None:
    # Reuse the pair record created during the USB pairing above. The device does
    # not allow pairing over the network, only reuse of an existing trust.
    lockdown = await create_using_tcp(ip, autopair=False)
    proxy = await CoreDeviceTunnelProxy.create(lockdown)

    async with start_tunnel(proxy, protocol=TunnelProtocol.TCP) as tunnel:
        rsd_addr = tunnel.address
        rsd_port = str(tunnel.port)
        print(f"tunnel up — RSD {rsd_addr} {rsd_port}", flush=True)
        try:
            while True:
                _simulate_location(["set", "--rsd", rsd_addr, rsd_port, "--", lat, lng])
                print(f"applied {lat}, {lng}", flush=True)
                await asyncio.sleep(KEEPALIVE_SECONDS)
        except (KeyboardInterrupt, asyncio.CancelledError):
            print("clearing spoof…", flush=True)
            _simulate_location(["clear", "--rsd", rsd_addr, rsd_port])


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    try:
        asyncio.run(main(sys.argv[1], sys.argv[2], sys.argv[3]))
    except KeyboardInterrupt:
        pass

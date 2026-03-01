#!/bin/bash
#
# Location Spoof — Start Everything
#
# Usage: ./start.sh
#
# This script:
# 1. Starts the pymobiledevice3 tunnel daemon (requires sudo)
# 2. Builds and launches the macOS menu bar app
# 3. Opens the iOS project in Xcode for you to run on your phone
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYMOBILE="$HOME/.local/bin/pymobiledevice3"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${GREEN}==============================${NC}"
echo -e "${GREEN}  Location Spoof — Starting   ${NC}"
echo -e "${GREEN}==============================${NC}"
echo ""

# Step 0: Check pymobiledevice3
if [ ! -x "$PYMOBILE" ]; then
    echo -e "${RED}pymobiledevice3 not found at $PYMOBILE${NC}"
    echo "Install it with: pipx install pymobiledevice3"
    exit 1
fi
echo -e "${GREEN}✓${NC} pymobiledevice3 found"

# Step 1: Kill any existing tunneld or stuck simulate-location processes
echo ""
echo -e "${YELLOW}Cleaning up old processes...${NC}"
sudo pkill -f "pymobiledevice3 remote tunneld" 2>/dev/null || true
pkill -f "simulate-location" 2>/dev/null || true
sleep 1

# Step 2: Start tunneld in background
echo ""
echo -e "${YELLOW}Starting pymobiledevice3 tunnel daemon (requires sudo)...${NC}"
echo "Make sure your iPhone is connected via USB."
echo ""
sudo "$PYMOBILE" remote tunneld &
TUNNELD_PID=$!
sleep 3

# Check if tunneld is still running
if ! kill -0 $TUNNELD_PID 2>/dev/null; then
    echo -e "${RED}tunneld failed to start. Is your iPhone connected via USB?${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Tunnel daemon running (PID: $TUNNELD_PID)"

# Step 3: Build macOS app
echo ""
echo -e "${YELLOW}Building macOS menu bar app...${NC}"
cd "$SCRIPT_DIR"
xcodebuild build \
    -project LocationSpoofMac/LocationSpoofMac.xcodeproj \
    -scheme LocationSpoofMac \
    -destination 'platform=macOS,arch=arm64' \
    -quiet 2>&1

echo -e "${GREEN}✓${NC} macOS app built"

# Step 4: Find and launch the built app
MAC_APP=$(xcodebuild -project LocationSpoofMac/LocationSpoofMac.xcodeproj \
    -scheme LocationSpoofMac \
    -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | awk '{print $3}')

# Kill any existing instance
pkill -f "LocationSpoofMac" 2>/dev/null || true
sleep 1

open "$MAC_APP/LocationSpoofMac.app"
echo -e "${GREEN}✓${NC} macOS menu bar app launched (check your menu bar for the pin icon)"

# Step 5: Open iOS project
echo ""
echo -e "${YELLOW}Opening iOS project in Xcode...${NC}"
open "$SCRIPT_DIR/LocationSpoof/LocationSpoof.xcodeproj"
echo -e "${GREEN}✓${NC} iOS project opened in Xcode"

echo ""
echo -e "${GREEN}==============================${NC}"
echo -e "${GREEN}  All set! Next steps:        ${NC}"
echo -e "${GREEN}==============================${NC}"
echo ""
echo "  1. In Xcode, select your iPhone and press Cmd+R"
echo "  2. In the iOS app, tap the map to pick a location"
echo "  3. Tap 'Spoof Location'"
echo "  4. Once spoofed, you can unplug your phone — the fake"
echo "     location will persist until you reset it or reboot"
echo ""
echo -e "${YELLOW}To stop everything later, run: ./stop.sh${NC}"
echo ""
echo "Press Ctrl+C to stop the tunnel daemon when you're done."
echo ""

# Keep script alive so tunneld stays running in foreground
wait $TUNNELD_PID

#!/bin/bash
#
# Location Spoof — Stop Everything
#

GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo "Stopping Location Spoof..."

sudo pkill -f "pymobiledevice3 remote tunneld" 2>/dev/null || true
pkill -f "LocationSpoofMac" 2>/dev/null || true
pkill -f "simulate-location" 2>/dev/null || true

echo -e "${GREEN}✓${NC} All processes stopped"
echo ""
echo "Note: Your iPhone's spoofed location will persist until you"
echo "either clear it from the app or reboot your phone."
echo ""

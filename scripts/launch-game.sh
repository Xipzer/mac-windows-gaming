#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

APPID=""
ENABLE_HUD=0
TAIL_LOG=0

usage() {
    echo "Usage: $0 <AppID> [--hud] [--tail]"
    echo ""
    echo "Arguments:"
    echo "  AppID     Steam Application ID (numeric)"
    echo "  --hud     Enable Apple Metal Performance HUD"
    echo "  --tail    Follow the SteamBridge execution log"
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

for arg in "$@"; do
    case "$arg" in
        --hud)
            ENABLE_HUD=1
            ;;
        --tail)
            TAIL_LOG=1
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [ -z "$APPID" ] && [[ "$arg" =~ ^[0-9]+$ ]]; then
                APPID="$arg"
            else
                echo -e "${RED}Unknown argument: $arg${NC}"
                usage
            fi
            ;;
    esac
done

if [ -z "$APPID" ]; then
    echo -e "${RED}Error: Valid numeric AppID required.${NC}"
    usage
fi

if ! pgrep -x "steam_osx" >/dev/null 2>&1; then
    printf "${YELLOW}Steam is not running. Launching Steam...${NC}\n"
    open -a /Applications/Steam.app
    printf "Waiting for Steam to initialize...\n"
    sleep 5
fi

LOG_FILE="$HOME/Library/Application Support/Steam/steamapps/compatdata/$APPID/steambridge-run.log"
HUD_FILE="$HOME/Library/Application Support/Steam/steamapps/compatdata/$APPID/steambridge-hud"

if [ "$ENABLE_HUD" -eq 1 ]; then
    export MTL_HUD_ENABLED=1
    mkdir -p "$(dirname "$HUD_FILE")"
    printf '1' > "$HUD_FILE"
else
    rm -f "$HUD_FILE" 2>/dev/null || true
fi

printf "${BLUE}${BOLD}==>${NC} Launching Steam AppID ${BOLD}%s${NC} via SteamBridge...\n" "$APPID"
open "steam://rungameid/$APPID"

if [ "$TAIL_LOG" -eq 1 ]; then
    printf "${BLUE}Following log at: %s${NC}\n" "$LOG_FILE"
    printf "${YELLOW}(Press Ctrl+C to stop viewing log; game will continue running)${NC}\n\n"
    
    for _ in {1..20}; do
        [ -f "$LOG_FILE" ] && break
        sleep 0.5
    done
    
    if [ -f "$LOG_FILE" ]; then
        tail -n 20 -f "$LOG_FILE"
    else
        echo "Log file not created yet. Game may still be initializing."
    fi
fi

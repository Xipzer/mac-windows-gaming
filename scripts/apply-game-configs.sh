#!/bin/sh
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
S="$HOME/Library/Application Support/Steam/steamapps"
C="$S/compatdata"
ok() { printf '  ok %s\n' "$*"; }
skip() { printf '  -- %s\n' "$*"; }

for f in "$REPO"/configs/games/*.env; do
  id=$(basename "$f" .env)
  if [ -d "$C/$id" ]; then
    [ -f "$C/$id/steambridge.env" ] && cp -p "$C/$id/steambridge.env" "$C/$id/steambridge.env.bak"
    cp "$f" "$C/$id/steambridge.env"; ok "profile $id"
  else skip "profile $id (game not installed or never launched)"; fi
done

U="pfx/drive_c/users/steamuser"
I="$S/common/Batman Arkham Knight/BMGame/Config/BmSystemSettings.ini"
X="$HOME/Documents/WB Games/Batman Arkham Knight/GFXSettings.BatmanArkhamKnight.xml"
if [ -f "$I" ]; then
  perl -pi -e 's/^ResX=\d+/ResX=3024/; s/^ResY=\d+/ResY=1964/; s/^MaxFPS=[\d.]+/MaxFPS=1000.000000/; s/^UseVsync=\w+/UseVsync=False/' "$I"
  [ -f "$X" ] && python3 - "$X" <<'PY'
import re,sys
p=sys.argv[1]; raw=open(p,'rb').read(); enc='utf-16-be' if raw[0]==0 else 'utf-16-le'; s=raw.decode(enc)
s=re.sub(r'(Name="ResolutionX"[^>]*Value=")\d+"',r'\g<1>3024"',s); s=re.sub(r'(Name="ResolutionY"[^>]*Value=")\d+"',r'\g<1>1964"',s)
open(p,'wb').write(s.encode(enc))
PY
  ok "Batman 3024x1964, MaxFPS 1000, V-Sync off"
fi
L="$C/920210/$U/AppData/Roaming/Warner Bros. Interactive Entertainment/LEGO Star Wars - The Skywalker Saga/PCCONFIG.TXT"
if [ -f "$L" ]; then
  perl -pi -e 's/^(ScreenWidth|WindowWidth)(\s+)\d+/$1${2}3024/; s/^(ScreenHeight|WindowHeight)(\s+)\d+/$1${2}1964/; s/^(ScreenRefreshRate\s+)\d+/${1}120/; s/^(VerticalSyncMode\s+)\d+/${1}0/' "$L"
  ok "LEGO 3024x1964, 120 Hz, V-Sync off"
fi
X="$C/1237320/$U/AppData/Roaming/SEGA/SonicFrontiers/steam/x64/screen_setting.xml"
if [ -f "$X" ]; then
  sed -i '' 's/resolutionWidth="[0-9]*"/resolutionWidth="3024"/; s/resolutionHeight="[0-9]*"/resolutionHeight="1701"/; s/fullscreenStyle="[0-9]"/fullscreenStyle="1"/' "$X"
  ok "Sonic 3024x1701 borderless"
fi
if [ -d "$S/common/SonicFrontiers" ]; then
  cp "$REPO/games/sonicfrontiers/dinput8.dll" "$S/common/SonicFrontiers/dinput8.dll"; ok "Sonic fps cap removal (dinput8.dll)"
fi
G="$C/1790600/$U/AppData/Local/SparkingZERO/Saved/Config/Windows/GameUserSettings.ini"
if [ -f "$G" ]; then
  perl -pi -e 's/^(ResolutionSizeX|LastUserConfirmedResolutionSizeX|LastUserConfirmedDesiredScreenWidth)=\d+/$1=3024/; s/^(ResolutionSizeY|LastUserConfirmedResolutionSizeY|LastUserConfirmedDesiredScreenHeight)=\d+/$1=1964/' "$G"
  ok "Dragon Ball 3024x1964"
fi

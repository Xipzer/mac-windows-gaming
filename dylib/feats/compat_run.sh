#!/bin/sh
set -e

verb="$1"
shift || true

launch_env=""
argc=$#
argi=0
while [ "$argi" -lt "$argc" ]; do
  arg="$1"
  shift
  case "$arg" in
    CX_GRAPHICS*=*|D3DM_*=*|DXMT_*=*|DXVK_*=*|MTL_*=*|STEAMBRIDGE_*=*|ROSETTA_*=*|WINE*=*)
      export "$arg"
      launch_env="$launch_env $arg"
      ;;
    *) set -- "$@" "$arg" ;;
  esac
  argi=$((argi+1))
done

if [ -n "$STEAM_COMPAT_DATA_PATH" ] && [ -r "$STEAM_COMPAT_DATA_PATH/steambridge.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
      CX_GRAPHICS*=*|D3DM_*=*|DXMT_*=*|DXVK_*=*|MTL_*=*|STEAMBRIDGE_*=*|ROSETTA_*=*|WINE*=*)
        name=${line%%=*}
        eval "isset=\${$name+x}"
        if [ -z "$isset" ]; then
          export "$line"
          launch_env="$launch_env $line"
        fi
        ;;
    esac
  done < "$STEAM_COMPAT_DATA_PATH/steambridge.env"
fi
if [ "$verb" = waitforexitandrun ] && [ -n "$STEAMBRIDGE_ARGS" ]; then
  set -- "$@" $STEAMBRIDGE_ARGS
fi

case "$verb" in
  getcompatpath)
    printf '%s\n' "$STEAM_COMPAT_DATA_PATH"
    exit 0
    ;;
esac

LEGACY_OVERLAY_SHIM_ENV=NOTPROTON_OVERLAY_SHIM
CX_ROOT="$HOME/Library/Application Support/SteamBridge/runners/${STEAMBRIDGE_RUNNER:-current}"
export CX_ROOT

if [ -d "$CX_ROOT/Contents/Resources/wine" ]; then
  CX_ROOT="$CX_ROOT/Contents/Resources/wine"
  export CX_ROOT
fi

export CX_HOME="$HOME/Library/Application Support/CrossOver"

export D3DM_ENABLE_METALFX="${D3DM_ENABLE_METALFX:-1}"
export ROSETTA_ADVERTISE_AVX="${ROSETTA_ADVERTISE_AVX:-1}"

wine_unix="$CX_ROOT/lib/wine/aarch64-unix"
[ -d "$wine_unix" ] || wine_unix="$CX_ROOT/lib/wine/x86_64-unix"

if [ -x "$CX_ROOT/bin/wineserver" ]; then
  WINESERVER="$CX_ROOT/bin/wineserver"
elif [ -x "$CX_ROOT/CrossOver-Hosted Application/wineserver-arm64" ]; then
  WINESERVER="$CX_ROOT/CrossOver-Hosted Application/wineserver-arm64"
elif [ -x "$CX_ROOT/CrossOver-Hosted Application/wineserver" ]; then
  WINESERVER="$CX_ROOT/CrossOver-Hosted Application/wineserver"
elif [ -x "$CX_ROOT/CrossOver-Hosted Application/wineserver-x86" ]; then
  WINESERVER="$CX_ROOT/CrossOver-Hosted Application/wineserver-x86"
fi

if [ -x "$CX_ROOT/bin/wine64" ]; then
  WINELOADER="$CX_ROOT/bin/wine64"
elif [ -x "$CX_ROOT/bin/wine" ]; then
  WINELOADER="$CX_ROOT/bin/wine"
elif [ -x "$wine_unix/wine.app/Contents/MacOS/wine" ]; then
  WINELOADER="$wine_unix/wine.app/Contents/MacOS/wine"
elif [ -x "$wine_unix/wine" ]; then
  WINELOADER="$wine_unix/wine"
fi

export WINELOADER WINESERVER
export WINEDLLPATH="$CX_ROOT/lib/wine/x86_64-windows:$wine_unix"
export PATH="$CX_ROOT/bin:$PATH"
export DYLD_FALLBACK_LIBRARY_PATH="$CX_ROOT/lib/deps:$CX_ROOT/lib/external:${DYLD_FALLBACK_LIBRARY_PATH:-/usr/lib}"
export STEAMBRIDGE_RENDERER="${STEAMBRIDGE_RENDERER:-d3dmetal}"
[ -f "$CX_ROOT/runner.env" ] && . "$CX_ROOT/runner.env"

if [ -n "$STEAM_COMPAT_DATA_PATH" ]; then
  log="$STEAM_COMPAT_DATA_PATH/steambridge-run.log"
else
  log=/dev/null
fi
[ "$(stat -f %z "$log" 2>/dev/null || echo 0)" -gt 262144 ] \
  && : > "$log" || true
{
  echo "=== steambridge run $(date) ==="
  echo "verb=$verb"
  echo "args:"; for a in "$@"; do echo "  [$a]"; done
  echo "cwd=$(pwd)"
  echo "STEAM_COMPAT_DATA_PATH=$STEAM_COMPAT_DATA_PATH"
  echo "STEAM_COMPAT_INSTALL_PATH=$STEAM_COMPAT_INSTALL_PATH"
  echo "STEAM_COMPAT_APP_ID=$STEAM_COMPAT_APP_ID"
  echo "-- steam env passed through --"
  env | grep -iE '^(Steam|SDL_)' | sort
} >> "$log" 2>&1 || true

stage_step="startup"
report_early_exit() {
  status=$?
  [ "$status" = 0 ] && return 0
  echo "=== aborted during $stage_step (exit $status) before launch ===" \
    >> "$log" 2>&1 || true
}
trap report_early_exit EXIT

while :; do
  case "$STEAM_COMPAT_INSTALL_PATH" in
    ?*/) STEAM_COMPAT_INSTALL_PATH="${STEAM_COMPAT_INSTALL_PATH%/}" ;;
    *) break ;;
  esac
done
export STEAM_COMPAT_INSTALL_PATH

app_id="$STEAM_COMPAT_APP_ID"
case "$app_id" in ''|0) app_id="$SteamAppId" ;; esac
case "$app_id" in ''|0) app_id=$(basename "$STEAM_COMPAT_DATA_PATH" 2>/dev/null) ;; esac
case "$app_id" in ''|*[!0-9]*) app_id=0 ;; esac
echo "app_id=$app_id (STEAM_COMPAT_APP_ID=$STEAM_COMPAT_APP_ID)" >> "$log" 2>&1 || true

[ -n "$SteamAppId" ] || export SteamAppId="$app_id"
[ -n "$SteamGameId" ] || export SteamGameId="$app_id"
if [ -n "$app_id" ] && [ "$app_id" != 0 ] && [ -d "$STEAM_COMPAT_INSTALL_PATH" ]; then
  printf '%s\n' "$app_id" > "$STEAM_COMPAT_INSTALL_PATH/steam_appid.txt" 2>/dev/null || true
fi

prefix_machine() {
  dll="$WINEPREFIX/drive_c/windows/system32/ntdll.dll"
  [ -f "$dll" ] || return 1
  off=$(od -A n -t u4 -j 60 -N 4 "$dll" 2>/dev/null | tr -d ' ')
  case "$off" in ''|*[!0-9]*) return 1 ;; esac
  sig=$(od -A n -t x1 -j "$off" -N 4 "$dll" 2>/dev/null | tr -d ' \n')
  [ "$sig" = 50450000 ] || return 1
  od -A n -t x2 -j "$((off + 4))" -N 2 "$dll" 2>/dev/null | tr -d ' \n'
}

tool_name() {
  case "$1" in
    aa64) printf 'the FEX build of CrossOver' ;;
    8664) printf 'the Rosetta build of CrossOver' ;;
    *) printf 'an older 32-bit setup' ;;
  esac
}

refuse_foreign_prefix() {
  case "${wine_unix##*/}" in
    aarch64-unix) want=aa64 ;;
    *) want=8664 ;;
  esac
  have=$(prefix_machine) || return 0
  [ "$have" = "$want" ] && return 0
  echo "=== prefix ntdll is $have and this compatibility tool wants $want, rebuild the prefix in SteamBridge ===" >> "$log" 2>&1 || true

  if [ "$verb" != run ]; then
    osascript >/dev/null 2>&1 <<APPLESCRIPT || true
display alert "This game needs its prefix rebuilt" message "This game originally ran under $(tool_name "$have"), but $(tool_name "$want") is present now. The prefix needs to be rebuilt in SteamBridge in order to run the game. You will not lose game saves by rebuilding the prefix." as critical
APPLESCRIPT
  fi
  exit 1
}
merge_user_dir() {
  src=$1
  dst=$2
  failed=
  set -- ""
  while [ "$#" -gt 0 ]; do
    rest=$1
    shift
    src_dir="$src$rest"
    dst_dir="$dst$rest"
    if [ ! -r "$src_dir" ] || [ ! -x "$src_dir" ]; then failed=1; continue; fi
    if [ -L "$dst_dir" ] && [ ! -e "$dst_dir" ]; then
      rm -f "$dst_dir" 2>/dev/null || true
    fi
    probe=$dst_dir
    through=
    while [ -n "$probe" ] && [ "$probe" != "$dst" ]; do
      if [ -L "$probe" ]; then through=1; break; fi
      probe=${probe%/*}
    done
    if [ -n "$through" ]; then
      echo "=== $rest is held by a link, merge refused ===" >> "$log" 2>&1 || true
      failed=1
      continue
    fi
    if [ -n "$rest" ] && [ -e "$dst_dir" ]; then continue; fi
    if ! mkdir -p "$dst_dir" 2>/dev/null; then failed=1; continue; fi
    for entry in "$src_dir"/* "$src_dir"/.[!.]* "$src_dir"/..?*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      name=${entry##*/}
      if [ -d "$entry" ] && [ ! -L "$entry" ]; then
        set -- "$@" "$rest/$name"
        continue
      fi
      landing="$dst_dir/$name"
      if [ -e "$landing" ]; then continue; fi
      if [ -L "$landing" ]; then rm -f "$landing" 2>/dev/null || true; fi
      if [ -L "$entry" ]; then
        if ! cp -Pp "$entry" "$landing" 2>/dev/null; then
          rm -f "$landing" 2>/dev/null || true
          failed=1
        fi
      else
        if ! cp -p "$entry" "$landing" 2>/dev/null; then
          rm -f "$landing" 2>/dev/null || true
          failed=1
        fi
        chmod u+w "$landing" 2>/dev/null || true
      fi
    done
  done
  [ -z "$failed" ]
}

migrate_user_paths() {
  profile=$1
  for pair in \
    "Local Settings/Application Data|AppData/Local|../AppData/Local" \
    "Application Data|AppData/Roaming|./AppData/Roaming" \
    "My Documents|Documents|./Documents"; do
    old_rel=${pair%%|*}
    rest=${pair#*|}
    new_rel=${rest%%|*}
    link=${rest#*|}
    old="$profile/$old_rel"
    new="$profile/$new_rel"
    case "$(readlink "$new" 2>/dev/null || true)" in
      *"drive_c/users/steamuser/$old_rel") rm -f "$new" 2>/dev/null || true ;;
    esac
    if [ -L "$new" ]; then
      echo "=== $new_rel is a link, rebuild the prefix for cloud saves ===" \
        >> "$log" 2>&1 || true
      continue
    fi
    held=
    for rel in "$old_rel" "$new_rel"; do
      probe=$rel
      while [ "$probe" != "${probe%/*}" ]; do
        probe=${probe%/*}
        if [ -L "$profile/$probe" ]; then held=$probe; break; fi
      done
      if [ -n "$held" ]; then break; fi
    done
    if [ -n "$held" ]; then
      echo "=== $held is a link, rebuild the prefix for cloud saves ===" \
        >> "$log" 2>&1 || true
      continue
    fi
    if [ -e "$old" ] && [ ! -L "$old" ]; then
      if ! merge_user_dir "$old" "$new"; then
        echo "=== $old_rel did not merge into $new_rel, left in place ===" \
          >> "$log" 2>&1 || true
        continue
      fi
      rmdir "$old BACKUP" 2>/dev/null || true
      if [ -e "$old BACKUP" ] || [ -L "$old BACKUP" ] \
        || ! mv "$old" "$old BACKUP" 2>> "$log"; then
        echo "=== $old_rel could not be moved aside, cloud saves stay split ===" \
          >> "$log" 2>&1 || true
        continue
      fi
    fi
    if [ ! -e "$old" ] && [ ! -L "$old" ]; then
      mkdir -p "${old%/*}" 2>/dev/null || true
      ln -s "$link" "$old" 2>/dev/null \
        || echo "=== $old_rel could not be aliased onto $new_rel ===" >> "$log" 2>&1 \
        || true
    elif [ -L "$old" ] && [ "$(readlink "$old")" != "$link" ]; then
      rm -f "$old" 2>/dev/null || true
      ln -s "$link" "$old" 2>/dev/null \
        || echo "=== $old_rel could not be aliased onto $new_rel ===" >> "$log" 2>&1 \
        || true
    fi
  done
}

lay_out_proton_profile() {
  users="$WINEPREFIX/drive_c/users"
  if [ -d "$users/crossover" ] && [ ! -L "$users/crossover" ]; then
    echo "=== prefix predates the steamuser layout, rebuild it for cloud saves ===" \
      >> "$log" 2>&1 || true
    return 0
  fi
  profile="$users/steamuser"
  if [ -L "$profile" ]; then
    echo "=== the profile is a link, rebuild the prefix for cloud saves ===" \
      >> "$log" 2>&1 || true
    return 0
  fi
  mkdir -p "$profile" 2>/dev/null || return 0
  for folder in Documents Desktop Downloads Music Pictures Videos Templates \
      AppData/Local AppData/Roaming; do
    mkdir -p "$profile/$folder" 2>/dev/null || true
  done
  migrate_user_paths "$profile"
  if [ -L "$users/crossover" ] && [ ! -e "$users/crossover" ]; then
    rm -f "$users/crossover" 2>/dev/null || true
  fi
  if [ ! -e "$users/crossover" ] \
    && ln -s steamuser "$users/crossover" 2>/dev/null; then
    echo "=== pointed crossover at steamuser ===" >> "$log" 2>&1 || true
  fi
  mac_user=$(id -un 2>/dev/null || true)
  if [ -n "$mac_user" ] && [ "$mac_user" != steamuser ] && [ ! -L "$users/$mac_user" ]; then
    if [ -d "$users/$mac_user" ]; then
      rsync -a --ignore-existing "$users/$mac_user/" "$profile/" >> "$log" 2>&1 || true
      backup="$STEAM_COMPAT_DATA_PATH/steambridge-profile-backup-$mac_user"
      rm -rf "$backup" 2>/dev/null || true
      mv "$users/$mac_user" "$backup" 2>/dev/null || true
    fi
    if [ ! -e "$users/$mac_user" ] && ln -s steamuser "$users/$mac_user" 2>/dev/null; then
      echo "=== pointed $mac_user profile at steamuser (cloud saves) ===" >> "$log" 2>&1 || true
    fi
  fi
}

if [ -n "$STEAM_COMPAT_DATA_PATH" ]; then
  export WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx"
  mkdir -p "$WINEPREFIX"
  msync_from=launch-options
  [ -n "$WINEMSYNC" ] || msync_from=default
  export WINEMSYNC="${WINEMSYNC:-1}"
  if [ -f "$1" ] && file -b "$1" 2>/dev/null | grep -q "PE32 "; then
    if [ "$WINEMSYNC" = "1" ]; then
      echo "=== 32-bit binary ($1) detected: forcing WINEMSYNC=0 to prevent WoW64 deadlock ===" >> "$log" 2>&1 || true
      WINEMSYNC=0
      export WINEMSYNC=0
    fi
  fi
  rm -f "$STEAM_COMPAT_DATA_PATH/steambridge-msync"
  if [ -z "$MTL_HUD_ENABLED" ] && [ -r "$STEAM_COMPAT_DATA_PATH/steambridge-hud" ]; then
    MTL_HUD_ENABLED=$(tr -d ' \t\n' < "$STEAM_COMPAT_DATA_PATH/steambridge-hud" 2>/dev/null || true)
    export MTL_HUD_ENABLED
    echo "hud: MTL_HUD_ENABLED=$MTL_HUD_ENABLED from carry-over" >> "$log" 2>&1 || true
  fi
  stage_step="prefix arch check"
  refuse_foreign_prefix
  echo "sync: WINEMSYNC=$WINEMSYNC from $msync_from" >> "$log" 2>&1 || true
  "$WINESERVER" -k >> "$log" 2>&1 || true
  dispmode="$HOME/Library/Application Support/SteamBridge/dispmode"
  desktop_restore=""
  if [ "$verb" = waitforexitandrun ] && [ -n "$STEAMBRIDGE_DESKTOP_MODE" ] && [ -x "$dispmode" ]; then
    dm_w=${STEAMBRIDGE_DESKTOP_MODE%x*}
    dm_h=${STEAMBRIDGE_DESKTOP_MODE#*x}
    desktop_home="$HOME/Library/Application Support/SteamBridge/desktop-home"
    if desktop_prev=$("$dispmode" set "$dm_w" "$dm_h" 2>> "$log"); then
      [ -s "$desktop_home" ] || printf '%s\n' "$desktop_prev" > "$desktop_home"
      desktop_restore=$(cat "$desktop_home")
      echo "video: desktop $desktop_prev -> ${dm_w}x${dm_h}@2x" >> "$log" 2>&1 || true
    else
      echo "video: could not switch desktop to $STEAMBRIDGE_DESKTOP_MODE" >> "$log" 2>&1 || true
    fi
  fi
  prio_shim="$HOME/Library/Application Support/SteamBridge/prio-shim.dylib"
  if [ "${STEAMBRIDGE_PRIO:-0}" = "1" ] && [ -f "$prio_shim" ]; then
    "$WINESERVER" -w >> "$log" 2>&1 || true
    if DYLD_INSERT_LIBRARIES="$prio_shim" "$WINESERVER" >> "$log" 2>&1; then
      echo "sched: wineserver started with prio-shim (mode ${STEAMBRIDGE_PRIO_MODE:-mr}, latency ${STEAMBRIDGE_PRIO_LATENCY:-keep}, throughput ${STEAMBRIDGE_PRIO_THROUGHPUT:-keep})" >> "$log" 2>&1 || true
    fi
  fi
  stage_step="profile layout"
  lay_out_proton_profile
  "$WINELOADER" wineboot --init >> "$log" 2>&1 || true
  "$WINELOADER" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\AeDebug' /v Auto /t REG_SZ /d 0 /f >> "$log" 2>&1 || true
  "$WINELOADER" reg add 'HKLM\Software\Wow6432Node\Microsoft\Windows NT\CurrentVersion\AeDebug' /v Auto /t REG_SZ /d 0 /f >> "$log" 2>&1 || true
  "$WINELOADER" reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f >> "$log" 2>&1 || true

  STEAMBRIDGE_RETINA="${STEAMBRIDGE_RETINA:-1}"
  echo "video: RetinaMode=$STEAMBRIDGE_RETINA" >> "$log" 2>&1 || true
  echo "video: renderer=$STEAMBRIDGE_RENDERER" >> "$log" 2>&1 || true
  if [ "$STEAMBRIDGE_RETINA" = "1" ]; then
    "$WINELOADER" reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d y /f >> "$log" 2>&1 || true
  else
    "$WINELOADER" reg delete 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /f >> "$log" 2>&1 || true
  fi
  "$WINELOADER" reg add 'HKCU\Software\Wine\Mac Driver' /v OpenGLSurfaceMode /t REG_SZ /d behind /f >> "$log" 2>&1 || true


  "$WINELOADER" reg add 'HKLM\Software\Classes\steam' /v 'URL Protocol' /t REG_SZ /d '' /f >> "$log" 2>&1 || true
  "$WINELOADER" reg add 'HKLM\Software\Classes\steam\shell\open\command' /ve /t REG_SZ /d '"C:\Program Files (x86)\Steam\steam.exe" "%1"' /f >> "$log" 2>&1 || true
fi

bridge_src="$HOME/Library/Application Support/SteamBridge/bridge"
prefix_steam="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
verify_runner() {
  if [ ! -d "$bridge_src/wine" ]; then
    echo "=== no patched ntdll in the bridge, run SteamBridge ===" >> "$log" 2>&1 || true
    return
  fi
  for arch in x86_64-windows i386-windows aarch64-windows; do
    staged="$bridge_src/wine/$arch/ntdll.dll"
    live="$CX_ROOT/lib/wine/$arch/ntdll.dll"
    [ -f "$staged" ] || continue
    if [ ! -f "$live" ]; then
      echo "=== runner has no $arch ntdll, set up the runner in SteamBridge ===" >> "$log" 2>&1 || true
    elif ! cmp -s "$staged" "$live"; then
      echo "=== runner $arch ntdll is not the patched copy, set up the runner in SteamBridge ===" >> "$log" 2>&1 || true
    fi
  done
  for arch in i386-windows x86_64-windows "${wine_unix##*/}"; do
    case "$arch" in
      *-unix) name="lsteamclient.so" ;;
      *) name="lsteamclient.dll" ;;
    esac
    [ -f "$CX_ROOT/lib/wine/$arch/$name" ] && continue
    echo "=== runner is missing $arch/$name, set up the runner in SteamBridge ===" >> "$log" 2>&1 || true
  done
}
install_lsteamclient_trigger() {
  src="$bridge_src/i386-windows/lsteamclient.dll"
  dst="$WINEPREFIX/drive_c/windows/syswow64/lsteamclient.dll"
  if [ -f "$src" ] && [ -d "$WINEPREFIX/drive_c/windows/syswow64" ]; then
    if ! cmp -s "$src" "$dst"; then
      cp -f "$src" "$dst" && echo "=== installed syswow64 lsteamclient trigger ===" >> "$log" 2>&1 || true
    fi
  fi
  src64="$bridge_src/x86_64-windows/lsteamclient.dll"
  dst64="$WINEPREFIX/drive_c/windows/system32/lsteamclient.dll"
  dst64_sc="$WINEPREFIX/drive_c/windows/system32/steamclient64.dll"
  if [ -f "$src64" ] && [ -d "$WINEPREFIX/drive_c/windows/system32" ]; then
    if ! cmp -s "$src64" "$dst64"; then
      cp -f "$src64" "$dst64" && echo "=== installed system32 lsteamclient trigger ===" >> "$log" 2>&1 || true
    fi
    rm -f "$dst64_sc"
  fi
}

install_legacy_steam_dll() {
  src="$bridge_src/legacycompat/Steam.dll"
  dst="$WINEPREFIX/drive_c/windows/syswow64/Steam.dll"
  [ -f "$src" ] && [ -d "$WINEPREFIX/drive_c/windows/syswow64" ] || return 0
  cmp -s "$src" "$dst" && return 0
  if cp -f "$src" "$dst"; then
    echo "=== installed legacy Steam.dll ===" >> "$log" 2>&1 || true
  else
    echo "=== could not install the legacy Steam.dll ===" >> "$log" 2>&1 || true
  fi
}

install_legacycompat() {
  src="$bridge_src/legacycompat"
  dst="$STEAM_COMPAT_CLIENT_INSTALL_PATH/legacycompat"
  [ -d "$src" ] && [ -n "$STEAM_COMPAT_CLIENT_INSTALL_PATH" ] || return 0
  mkdir -p "$dst" || return 0
  for f in "$src"/*; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    cmp -s "$f" "$dst/$b" && continue
    cp -f "$f" "$dst/$b" && \
      echo "=== installed legacycompat/$b ===" >> "$log" 2>&1
  done
}

bridge_files="steamclient64.dll steamclient.dll tier0_s64.dll vstdlib_s64.dll"
bridge_files="$bridge_files tier0_s.dll vstdlib_s.dll"
bridge_files="$bridge_files lsteamclient.dll lsteamclient.so steam.exe steamclient.so steamclient64.so ntdll_compat.so"
if [ -d "$bridge_src" ] && [ -n "$WINEPREFIX" ]; then
  stage_step="bridge staging"
  mkdir -p "$prefix_steam"
  for f in $bridge_files; do
    src="$bridge_src/$f"
    case "$f" in
      *.so) src="$bridge_src/${wine_unix##*/}/$f" ;;
    esac
    if [ ! -f "$src" ]; then
      echo "=== bridge missing $f ===" >> "$log" 2>&1 || true
      continue
    fi
    cp -f "$src" "$prefix_steam/$f" || \
      echo "=== failed to stage $f ===" >> "$log" 2>&1
  done
  for f in "$prefix_steam"/*.dll "$prefix_steam"/*.so "$prefix_steam"/*.exe; do
    [ -f "$f" ] || continue
    case " $bridge_files " in
      *" $(basename "$f") "*) ;;
      *) rm -f "$f" && echo "=== pruned stale $(basename "$f") ===" >> "$log" 2>&1 ;;
    esac
  done
  verify_runner
  install_lsteamclient_trigger
  install_legacy_steam_dll
  export WINEDLLPATH="$prefix_steam:$WINEDLLPATH"
  export WINEDLLOVERRIDES="steamclient=n,b;steamclient64=n,b;lsteamclient=b;d3dcompiler_43=n,b;d3dx9_43=n,b;d3dcompiler_47=n,b;nvapi64,nvngx=n,b;${WINEDLLOVERRIDES}"
  native_client="$STEAM_COMPAT_CLIENT_INSTALL_PATH"
  if [ -z "$native_client" ]; then
    native_client="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$native_client"
  fi
  install_legacycompat
  if [ -s "$STEAM_COMPAT_DATA_PATH/steambridge-directx" ]; then
    echo "=== native DirectX DLLs from the game's redist: $(sort -u "$STEAM_COMPAT_DATA_PATH/steambridge-directx" | tr '\n' ' ')===" >> "$log" 2>&1 || true
  fi
  echo "=== bridge staged into $prefix_steam ===" >> "$log" 2>&1 || true
  echo "WINEDLLPATH=$WINEDLLPATH" >> "$log" 2>&1 || true
  echo "STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_COMPAT_CLIENT_INSTALL_PATH" >> "$log" 2>&1 || true
fi

export WINEDEBUG="${WINEDEBUG:-err+all,fixme-all}"
trap - EXIT
echo "launch_env=$launch_env" >> "$log" 2>&1 || true
echo "=== launching ($verb): $WINELOADER $* ===" >> "$log" 2>&1 || true

target="$1"
case "$target" in
  "$STEAM_COMPAT_INSTALL_PATH"/*) foreground=1 ;;
  *) foreground=0 ;;
esac

if [ "$foreground" = 0 ]; then
  echo "=== running helper on raw loader: $* ===" >> "$log" 2>&1 || true
  case "$target" in
    *iscriptevaluator.exe*)
      echo "=== iscriptevaluator bypassed for macOS compatibility ===" >> "$log" 2>&1 || true
      exit 0
      ;;
  esac
  "$WINELOADER" "$@" >> "$log" 2>&1
  status=$?
  echo "=== helper exited status=$status ===" >> "$log" 2>&1 || true
  exit $status
fi

steam_root="$(dirname "$(dirname "$(dirname "$STEAM_COMPAT_DATA_PATH")")")"
manifest="$steam_root/steamapps/appmanifest_$app_id.acf"
client_root="$STEAM_COMPAT_CLIENT_INSTALL_PATH"
while [ -n "$client_root" ] && [ "$client_root" != "/" ] && [ ! -d "$client_root/appcache" ]; do
  client_root=$(dirname "$client_root")
done
appinfo_tool="$HOME/Library/Application Support/SteamBridge/appinfo"
appinfo_vdf="$client_root/appcache/appinfo.vdf"
meta_name=""
meta_icon=""
meta_clienticon=""
if [ -x "$appinfo_tool" ] && [ -f "$appinfo_vdf" ]; then
  meta=$("$appinfo_tool" "$appinfo_vdf" "$app_id" 2>> "$log") || meta=""
  meta_name=$(printf '%s\n' "$meta" | sed -n 's/^name=//p')
  meta_icon=$(printf '%s\n' "$meta" | sed -n 's/^icon=//p')
  meta_clienticon=$(printf '%s\n' "$meta" | sed -n 's/^clienticon=//p')
fi
game_name="$meta_name"
if [ -z "$game_name" ] && [ -f "$manifest" ]; then
  game_name=$(sed -n 's/.*"name"[[:space:]]*"\(.*\)".*/\1/p' "$manifest" | head -1)
fi
[ -z "$game_name" ] && game_name=$(basename "$STEAM_COMPAT_INSTALL_PATH")
[ -z "$game_name" ] && game_name="Steam Game"
bundle_name=$(printf '%s' "$game_name" | tr -d '/:"`$\\')
game_name_xml=$(printf '%s' "$game_name" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
loader_root="$HOME/Library/Application Support/SteamBridge/launchers/$app_id"
mkdir -p "$loader_root"
loader_app="$loader_root/$bundle_name.app"
rm -rf "$loader_root"/*.app
loader_contents="$loader_app/Contents"
loader_macos="$loader_contents/MacOS"
loader_res="$loader_contents/Resources"
mkdir -p "$loader_macos" "$loader_res"

icon_arg=""
resolve_icon() {
  set +e
  iconmaker="$HOME/Library/Application Support/SteamBridge/iconmaker"
  art_dir="$client_root/appcache/librarycache/$app_id"
  art=""
  if [ -n "$meta_clienticon" ]; then
    ico="$loader_root/clienticon-$meta_clienticon.ico"
    absent="$loader_root/clienticon-$meta_clienticon.absent"
    find "$loader_root" -maxdepth 1 -name 'clienticon-*'   ! -name "clienticon-$meta_clienticon.*" -delete 2>/dev/null || true
    find "$absent" -mtime +14 -delete 2>/dev/null || true
    if [ ! -s "$ico" ] && [ ! -f "$absent" ]; then
      url="https://shared.fastly.steamstatic.com/community_assets/images/apps/$app_id/$meta_clienticon.ico"
      code=$(curl -fsL --connect-timeout 5 --max-time 20 -w '%{http_code}' -o "$ico.new" "$url" 2>>"$log")
      magic=$(od -An -tx1 -N4 "$ico.new" 2>/dev/null | tr -d ' \n')
      if [ "$magic" = "00000100" ]; then
        mv -f "$ico.new" "$ico"
        echo "fetched client icon $meta_clienticon" >> "$log" 2>&1 || true
      else
        rm -f "$ico.new"
        if [ "$code" = "404" ]; then
          : > "$absent"
          echo "no client icon published for $meta_clienticon" >> "$log" 2>&1 || true
        else
          echo "client icon fetch for $meta_clienticon failed (http ${code:-none}), will retry" >> "$log" 2>&1 || true
        fi
      fi
    fi
    [ -s "$ico" ] && art="$ico"
  fi
  if [ -z "$art" ] && [ -n "$meta_icon" ] && [ -f "$art_dir/$meta_icon.jpg" ]; then
    art="$art_dir/$meta_icon.jpg"
  fi
  if [ -z "$art" ]; then
    art=$(find "$art_dir" -maxdepth 1 -type f -name '*.jpg' 2>/dev/null |   grep -E '/[0-9a-f]{40}\.jpg$' | head -1)
  fi
  if [ -z "$art" ]; then
    for name in library_600x900.jpg header.jpg; do
      found=$(find "$art_dir" -name "$name" 2>/dev/null | head -1)
      [ -n "$found" ] && { art="$found"; break; }
    done
  fi
  if [ -z "$art" ] && [ -f "$target" ]; then
    case "$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')" in
      *.exe) art="$target" ;;
    esac
  fi
  icon_source=""
  if [ -n "$art" ]; then
    icon_source="$art $(stat -f %m "$art" 2>/dev/null || echo 0)"
  fi
  icon_cache="$loader_root/game.icns"
  if [ -n "$art" ] && [ -s "$icon_cache" ] &&   [ "$(cat "$loader_root/steambridge-icon.source" 2>/dev/null)" =   "$icon_source" ] && cp -f "$icon_cache" "$loader_res/game.icns"; then
    icon_arg="  <key>CFBundleIconFile</key><string>game</string>"
    echo "icon reused from $art" >> "$log" 2>&1 || true
  elif [ -n "$art" ] && [ -x "$iconmaker" ]; then
    if "$iconmaker" "$art" "$icon_cache" >> "$log" 2>&1 &&   cp -f "$icon_cache" "$loader_res/game.icns"; then
      icon_arg="  <key>CFBundleIconFile</key><string>game</string>"
      printf '%s\n' "$icon_source" > "$loader_root/steambridge-icon.source"
      echo "icon built from $art" >> "$log" 2>&1 || true
    elif [ "$art" = "$ico" ]; then
      rm -f "$ico"
      echo "discarded unreadable client icon $meta_clienticon" >> "$log" 2>&1 || true
    fi
  fi
  set -e
  return 0
}
resolve_icon || true
[ -n "$icon_arg" ] || echo "no icon resolved, launching without one" >> "$log" 2>&1 || true

uielement_arg=""
if [ "${STEAMBRIDGE_HIDE_LAUNCHER_TILE:-0}" = "1" ]; then
  uielement_arg="  <key>LSUIElement</key><true/>"
  echo "launcher tile hidden by STEAMBRIDGE_HIDE_LAUNCHER_TILE" >> "$log" 2>&1 || true
fi
cat > "$loader_contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$game_name_xml</string>
  <key>CFBundleDisplayName</key><string>$game_name_xml</string>
  <key>CFBundleIdentifier</key><string>com.steambridge.launcher.$app_id</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
$uielement_arg
$icon_arg
</dict>
</plist>
PLIST

for f in "$wine_unix"/*; do
  [ -e "$f" ] || continue
  base=${f##*/}
  case "$base" in
    wine|wine.app) continue ;;
  esac
  ln -sfn "$f" "$loader_macos/$base"
done
[ -d "$CX_ROOT/lib" ] && ln -sfn "$CX_ROOT/lib" "$loader_contents/lib"
ln "$WINELOADER" "$loader_macos/wine" 2>/dev/null || cp "$WINELOADER" "$loader_macos/wine"
loader_dir="$(dirname "$WINELOADER")"
if [ -f "$loader_dir/wine64-preloader" ]; then
  ln -sfn "$loader_dir/wine64-preloader" "$loader_macos/wine64-preloader" 2>/dev/null || true
  ln -sfn "$loader_dir/wine64-preloader" "$loader_macos/wine-preloader" 2>/dev/null || true
elif [ -f "$loader_dir/wine-preloader" ]; then
  ln -sfn "$loader_dir/wine-preloader" "$loader_macos/wine-preloader" 2>/dev/null || true
fi
if [ -x "$loader_macos/wine" ]; then
  WINELOADER="$loader_macos/wine"
  echo "loader staged in bundle for game mode" >> "$log" 2>&1 || true
else
  echo "loader staging failed, game mode unavailable" >> "$log" 2>&1 || true
fi

cat > "$loader_macos/launcher" <<LAUNCHER
#!/bin/sh
export WINELOADER="$WINELOADER"
export DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH"
wine_log="$loader_root/steambridge-wine.log"
exec > "\$wine_log" 2>&1
shim="$HOME/Library/Application Support/SteamBridge/overlay-shim.dylib"
if [ -f "\$shim" ]; then
  if [ -n "\$STEAM_DYLD_INSERT_LIBRARIES" ]; then
    export DYLD_INSERT_LIBRARIES="\$shim:\$STEAM_DYLD_INSERT_LIBRARIES"
  else
    export DYLD_INSERT_LIBRARIES="\$shim"
  fi
  export STEAMBRIDGE_OVERLAY_SHIM="\$shim"
  export $LEGACY_OVERLAY_SHIM_ENV="\$shim"
elif [ -n "\$STEAM_DYLD_INSERT_LIBRARIES" ]; then
  export DYLD_INSERT_LIBRARIES="\$STEAM_DYLD_INSERT_LIBRARIES"
fi
[ -n "\$STEAMBRIDGE_GAME_CWD" ] && cd "\$STEAMBRIDGE_GAME_CWD"
"$WINELOADER" "\$@"
exit \$?
LAUNCHER
chmod +x "$loader_macos/launcher"

prefix_server_dir() {
  [ -n "$WINEPREFIX" ] || return 1
  ids=$(stat -f '%d-%i' "$WINEPREFIX" 2>/dev/null) || return 1
  [ -n "$ids" ] || return 1
  printf '/tmp/.wine-%s/server-%s' "$(id -u)" \
    "$(printf '%s' "$ids" | awk -F- '{printf "%x-%x", $1, $2}')"
}

game_mode_on=0
gamepolicyctl=/Applications/Xcode.app/Contents/Developer/usr/bin/gamepolicyctl
[ -x "$gamepolicyctl" ] || gamepolicyctl=$(command -v gamepolicyctl 2>/dev/null || true)
game_mode_set() {
  [ "${STEAMBRIDGE_GAMEMODE:-0}" = "1" ] && [ -n "$gamepolicyctl" ] || return 0
  "$gamepolicyctl" game-mode set "$1" >> "$log" 2>&1 || true
  echo "=== game mode $1 ===" >> "$log" 2>&1 || true
}

kill_wine_prefix() {
  if [ "$game_mode_on" = "1" ]; then game_mode_set auto; game_mode_on=0; fi
  "$WINESERVER" -k >> "$log" 2>&1 || true
  "$WINESERVER" -w >> "$log" 2>&1 || true
  if [ -n "$desktop_restore" ]; then
    set -- $desktop_restore
    "$dispmode" set "$1" "$2" "$5" >> "$log" 2>&1 || true
    rm -f "$HOME/Library/Application Support/SteamBridge/desktop-home"
    echo "video: desktop restored to $1x$2" >> "$log" 2>&1 || true
    desktop_restore=""
  fi
  if command -v lsof >/dev/null 2>&1 && server_dir=$(prefix_server_dir); then
    if [ -d "$server_dir" ]; then
      survivors=$(lsof -t +D "$server_dir" 2>/dev/null | sort -u)
      if [ -n "$survivors" ]; then
        echo "=== sweeping prefix stragglers: $survivors ===" >> "$log" 2>&1 || true
        kill -9 $survivors 2>/dev/null || true
      fi
    fi
  fi
}

terminate() {
  echo "=== termination signal received, killing wine prefix ===" >> "$log" 2>&1 || true
  kill_wine_prefix
  [ -n "$open_pid" ] && kill "$open_pid" 2>/dev/null || true
  exit 0
}
trap terminate TERM INT HUP

shim_exe="C:\\Program Files (x86)\\Steam\\steam.exe"

game_cwd="$(pwd)"
game_name="$(basename "$1" 2>/dev/null || true)"
if [ "${STEAMBRIDGE_OVERLAY:-1}" = "0" ]; then
  STEAM_DYLD_INSERT_LIBRARIES=""
fi
if [ -n "$STEAM_DYLD_INSERT_LIBRARIES" ]; then
  echo "=== overlay injected from $STEAM_DYLD_INSERT_LIBRARIES ===" >> "$log" 2>&1 || true
else
  echo "=== client staged no overlay renderer, overlay disabled ===" >> "$log" 2>&1 || true
fi


set -- --args "$shim_exe" "$@"
for name in $(env | sed -nE 's/^(Steam[A-Za-z0-9]*|SikarugirApp[A-Za-z0-9]*|GST_PLUGIN_PATH|VK_DRIVER_FILES|(WINE|STEAMBRIDGE_|CX_GRAPHICS|CX_D3DMETAL|CX_APPLEGPT|CX_FWD|WINEDLLPATH_|D3DM_|DXMT_|DXVK_|MVK_|MTL_|ROSETTA_)[A-Z0-9_]*)=.*/\1/p'); do
  eval "value=\$$name"
  set -- --env "$name=$value" "$@"
done
set -- \
  --env CX_ROOT="$CX_ROOT" \
  --env CX_HOME="$CX_HOME" \
  --env WINESERVER="$WINESERVER" \
  --env WINEDLLPATH="$WINEDLLPATH" \
  --env WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
  --env WINEMSYNC="$WINEMSYNC" \
  --env WINEPREFIX="$WINEPREFIX" \
  --env WINEDEBUG="$WINEDEBUG" \
  --env DYLD_FALLBACK_LIBRARY_PATH="$DYLD_FALLBACK_LIBRARY_PATH" \
  --env PATH="$PATH" \
  --env STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
  --env STEAM_COMPAT_INSTALL_PATH="$STEAM_COMPAT_INSTALL_PATH" \
  --env STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_COMPAT_CLIENT_INSTALL_PATH" \
  --env STEAM_COMPAT_APP_ID="$STEAM_COMPAT_APP_ID" \
  --env STEAM_DYLD_INSERT_LIBRARIES="$STEAM_DYLD_INSERT_LIBRARIES" \
  --env STEAMBRIDGE_GAME_CWD="$game_cwd" "$@"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A"
lsregister="$lsregister/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$lsregister" ] && "$lsregister" -f "$loader_app" >> "$log" 2>&1 || true
open -n -W -a "$loader_app" "$@" >> "$log" 2>&1 &
open_pid=$!
game_mode_set on; game_mode_on=1
status=0
wait "$open_pid" || status=$?
echo "=== bundle exited status=$status ===" >> "$log" 2>&1 || true
if [ "$status" -le 128 ]; then
  "$WINESERVER" -w >> "$log" 2>&1 &
  wait $! || true
fi
echo "=== game exited status=$status, killing wine prefix ===" >> "$log" 2>&1 || true
kill_wine_prefix
echo "=== wine prefix killed, session ending ===" >> "$log" 2>&1 || true
exit $status

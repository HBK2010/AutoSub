#!/bin/sh
# ============================================================================
#  AutoSub AI - installer / updater / uninstaller for Enigma2
#  (c) 2026 Ahmad Alamri. All rights reserved.
#
#  Install / update :  wget -q -O - https://raw.githubusercontent.com/HBK2010/AutoSub/main/install.sh | sh
#  Uninstall        :  wget -q -O - https://raw.githubusercontent.com/HBK2010/AutoSub/main/install.sh | sh -s uninstall
#
#  - Downloads to a temp folder and checks the code with THIS receiver's python first.
#  - On any failure the previous version is restored; your API key and settings are kept.
#  - Works with systemd (Dreambox / DreamOS) and init based images (OpenATV, OpenPLi, Black Hole ...).
# ============================================================================
BASE="${AUTOSUB_BASE:-https://raw.githubusercontent.com/HBK2010/AutoSub/main}"
EXT="${AUTOSUB_EXT:-/usr/lib/enigma2/python/Plugins/Extensions}"
DEST="$EXT/AutoSub"
KEYFILE="${AUTOSUB_KEY:-/etc/enigma2/autosub.key}"
SETTINGS="${AUTOSUB_SETTINGS:-/etc/enigma2/settings}"
TMP="/tmp/autosub_install"
BAK="/tmp/autosub_backup"

say() { echo "[AutoSub AI] $*"; }
fail() { say "ERROR: $*"; rm -rf "$TMP"; exit 1; }

is_systemd() {
	command -v systemctl >/dev/null 2>&1 && systemctl status enigma2 >/dev/null 2>&1
}
gui_stop() {
	[ "${NORESTART:-0}" = "1" ] && return 0
	if is_systemd; then systemctl stop enigma2; else init 4 >/dev/null 2>&1 || killall -9 enigma2 >/dev/null 2>&1; sleep 3; fi
}
gui_start() {
	[ "${NORESTART:-0}" = "1" ] && { say "GUI restart skipped (NORESTART=1)"; return 0; }
	if is_systemd; then systemctl start enigma2; else init 3 >/dev/null 2>&1; fi
}

fetch() {  # $1 = url, $2 = output file  (tries wget/curl, with and without certificate checks)
	for m in 1 2 3 4; do
		case $m in
			1) command -v wget >/dev/null 2>&1 && wget -q -T 25 -O "$2" "$1" 2>/dev/null ;;
			2) command -v wget >/dev/null 2>&1 && wget -q -T 25 --no-check-certificate -O "$2" "$1" 2>/dev/null ;;
			3) command -v curl >/dev/null 2>&1 && curl -fsSL -m 25 -o "$2" "$1" 2>/dev/null ;;
			4) command -v curl >/dev/null 2>&1 && curl -fsSLk -m 25 -o "$2" "$1" 2>/dev/null ;;
		esac
		[ $? -eq 0 ] && [ -s "$2" ] && return 0
	done
	rm -f "$2"
	return 1
}

# ---- uninstall ---------------------------------------------------------------
if [ "$1" = "uninstall" ]; then
	say "Uninstalling..."
	gui_stop
	rm -rf "$DEST" "$KEYFILE" /tmp/autosub* /tmp/sfp_autosub*
	[ -f "$SETTINGS" ] && sed -i '/config.plugins.autosub/d' "$SETTINGS"
	say "AutoSub AI removed (plugin, API key, settings)."
	gui_start
	exit 0
fi

echo "------------------------------------------------------------"
say "Installer started"
echo "------------------------------------------------------------"

# ---- 1) environment ------------------------------------------------------------
PY=""
for p in python3 python; do
	command -v "$p" >/dev/null 2>&1 && { PY="$p"; break; }
done
[ -n "$PY" ] || fail "python not found (is this an Enigma2 receiver?)"
[ -d "$EXT" ] || fail "Enigma2 plugin folder not found: $EXT"
say "Python: $($PY --version 2>&1)"

# ---- 2) download + verify -------------------------------------------------------
rm -rf "$TMP"; mkdir -p "$TMP" || fail "cannot create $TMP"
say "Downloading AutoSub.tar.gz ..."
fetch "$BASE/AutoSub.tar.gz" "$TMP/AutoSub.tar.gz" \
	|| fail "download failed (check the internet connection; very old images may need curl or a different mirror)"
( cd "$TMP" && tar xzf AutoSub.tar.gz ) 2>/dev/null || fail "the downloaded archive is damaged"
[ -f "$TMP/AutoSub/plugin.py" ] || fail "plugin.py missing in the archive"
grep -q "AutoSub AI" "$TMP/AutoSub/plugin.py" || fail "plugin.py looks invalid"
$PY -c "import sys; compile(open(sys.argv[1], 'rb').read(), sys.argv[1], 'exec')" "$TMP/AutoSub/plugin.py" 2>/dev/null \
	|| fail "plugin.py does not compile on this receiver's python ($($PY --version 2>&1)) - nothing was changed"
say "Files verified"

# ---- 3) backup + install ----------------------------------------------------------
rm -rf "$BAK"
[ -d "$DEST" ] && cp -a "$DEST" "$BAK"
rm -rf "$DEST"
mkdir -p "$DEST" || fail "cannot create $DEST"
if ! cp -R "$TMP/AutoSub/." "$DEST/"; then
	rm -rf "$DEST"; [ -d "$BAK" ] && cp -a "$BAK" "$DEST"
	fail "could not copy the files - previous version restored"
fi
# stale compiled files are the classic cause of "old version still running"
rm -rf "$DEST/__pycache__"
rm -f "$DEST"/*.pyc "$DEST"/*.pyo
rm -rf "$TMP"
say "Installed in: $DEST"

if [ ! -s "$KEYFILE" ]; then
	echo "------------------------------------------------------------"
	say "Next step - add your free Groq key (console.groq.com -> API Keys):"
	echo "  echo \"YOUR_GROQ_KEY\" > $KEYFILE && chmod 600 $KEYFILE"
	echo "------------------------------------------------------------"
fi

# ---- 4) restart the GUI -------------------------------------------------------------
say "Restarting Enigma2 GUI..."
gui_stop
gui_start
exit 0

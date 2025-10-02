#!/usr/bin/env bash
# CYT Bootstrap — interactive, idempotent Linux-only setup for this host
# Revised to REQUIRE Kismet web user creation before proceeding.
# Behavior:
#  - Linux-only
#  - Kismet must be installed (script will attempt install via apt/pacman if missing)
#  - Starts Kismet and ensures web UI is reachable
#  - If --no-browser is provided, the script will still pause and REQUIRE that the
#    operator create a Kismet web user via the web UI (on localhost:2501 or remote host)
#  - The script will attempt an API-based login check (best-effort). If that check fails,
#    it will instruct the operator to create the user via the web UI and will NOT proceed until
#    the user confirms creation and a login test succeeds.
#  - All other features retained: venv, direnv support, autostart, symlinks, Wigle creds, etc.

set -euo pipefail
IFS=$'
    '

log(){ printf "[BOOTSTRAP] %s
" "$*" | tee -a "$LOGFILE"; }
err(){ printf "[ERROR] %s
" "$*" | tee -a "$LOGFILE" >&2; }
info(){ printf "
[INFO] %s

" "$*" | tee -a "$LOGFILE"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  printf "This bootstrap is Linux-only. Exiting.
" >&2
  exit 1
fi

# --- Parse flags
ASSUME_YES=false
NO_BROWSER=false
SKIP_UPDATE=false
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=true ;;
    --no-browser) NO_BROWSER=true ;;
    --skip-update) SKIP_UPDATE=true ;;
    --help|-h)
      cat <<'HLP'
Usage: ./bootstrap.sh [options]
  --yes, -y        Assume sensible defaults (non-interactive where possible)
  --no-browser     Do not auto-open Kismet web UI (script will still require user creation)
  --help, -h       Show this help
HLP
      exit 0 ;;
  esac
done

# --- Determine ROOT early so we can set LOGFILE
DETECTED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$DETECTED_ROOT"
LOGDIR_PRE="$DETECTED_ROOT/logs"
mkdir -p "$LOGDIR_PRE"
LOGFILE="$LOGDIR_PRE/bootstrap-$(date +%Y%m%d-%H%M%S).log"

info "Logs for this run will be written to: $LOGFILE"

# --- 0) prompt for project root
if $ASSUME_YES; then
  ROOT="$DETECTED_ROOT"
  log "--yes provided. Using detected project root: $ROOT"
else
  read -r -p "Detected project root: $DETECTED_ROOT
Use this path? (Press Enter for yes, or type a new full path): " input_root
  if [[ -n "$input_root" ]]; then
    ROOT="$(readlink -f "$input_root")"
  fi
fi
[[ -d "$ROOT" ]] || { log "Creating project root: $ROOT"; mkdir -p "$ROOT"; }
log "Project root: $ROOT"

# Re-point LOGFILE under final ROOT
mkdir -p "$ROOT/logs"
if [[ "$LOGDIR_PRE" != "$ROOT/logs" ]]; then
  mv "$LOGFILE" "$ROOT/logs/" 2>/dev/null || true
  LOGFILE="$ROOT/logs/$(basename "$LOGFILE")"
fi

# --- 1) System package maintenance (MANDATORY)
info "Step 1 — System package maintenance (MANDATORY)"
cat <<EOF | tee -a "$LOGFILE"
This bootstrap requires your system packages to be fully up to date.
We will run update/upgrade/autoremove using your package manager.
EOF
if command -v apt >/dev/null 2>&1; then
  log "Using apt to update/upgrade/autoremove"
  sudo apt update
  sudo apt -y full-upgrade
  sudo apt -y autoremove
elif command -v pacman >/dev/null 2>&1; then
  log "Using pacman to update/upgrade"
  sudo pacman -Syu --noconfirm
else
  err "Unsupported package manager (need apt or pacman). Exiting."
  exit 1
fi

# --- 2) Ensure Kismet is installed & UPDATED to newest available (REQUIRED)
info "Step 2 — Kismet (install/upgrade REQUIRED)"
get_kismet_version() { kismet --version 2>/dev/null | head -n1 || true; }
if command -v kismet >/dev/null 2>&1; then
  log "Current Kismet: $(get_kismet_version)"
else
  log "Kismet not found; installing..."
fi
if command -v apt >/dev/null 2>&1; then
  # Always attempt to (re)install and then upgrade to newest available
  sudo apt -y install kismet
  sudo apt -y install --only-upgrade kismet || true
elif command -v pacman >/dev/null 2>&1; then
  sudo pacman -S --noconfirm kismet
fi
if ! command -v kismet >/dev/null 2>&1; then
  err "Kismet installation failed or kismet not on PATH. Exiting."
  exit 1
fi
log "Post-install Kismet: $(get_kismet_version)"
info "Step 2 — Kismet (required)"
check_kismet_binary() { command -v kismet >/dev/null 2>&1; }
if check_kismet_binary; then
  log "Found Kismet: $(command -v kismet)"
else
  if $ASSUME_YES; then INSTALL_K="Y"; else read -r -p "Kismet not found. Install now? (y/N): " INSTALL_K; fi
  if [[ "${INSTALL_K:-N}" =~ ^[Yy] ]]; then
    if command -v apt >/dev/null 2>&1; then
      log "Installing Kismet via apt"
      sudo apt update
      sudo apt -y install kismet || { err "apt failed to install Kismet"; exit 1; }
    elif command -v pacman >/dev/null 2>&1; then
      log "Installing Kismet via pacman"
      sudo pacman -S --noconfirm kismet || { err "pacman failed to install Kismet"; exit 1; }
    else
      err "Unsupported package manager. Please install Kismet manually and re-run."
      exit 1
    fi
    check_kismet_binary || { err "Kismet still not on PATH after install"; exit 1; }
  else
    err "Kismet is required. Exiting."
    exit 1
  fi
fi

# --- 3) Create project directories
log "Creating project directories"
mkdir -p "$ROOT/logs" "$ROOT/reports" "$ROOT/surveillance_reports" "$ROOT/kml_files"
mkdir -p "$ROOT/secure_credentials" "$ROOT/etc_kismet" "$ROOT/bin"

# --- 3a) Create example etc_kismet templates if missing
if [[ -z "$(ls -A "$ROOT/etc_kismet" 2>/dev/null || true)" ]]; then
  log "No files in $ROOT/etc_kismet — creating example templates"
  cat > "$ROOT/etc_kismet/kismet_site.conf" <<'KSITE'
# Example kismet_site.conf — adjust as needed
log_prefix=~/cyt/logs
# Uncomment and set your sources here, e.g.:
# source=wlan0
KSITE
  cat > "$ROOT/etc_kismet/kismet.conf" <<'KCONF'
# Example kismet.conf — see Kismet docs for full options
allowunknown=true
KCONF
fi

# --- 4) Write refresh_kismet_db.sh
cat > "$ROOT/bin/refresh_kismet_db.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
LOGDIR="$HOME/cyt/logs"
TARGET="$HOME/cyt/kismet.db"
newest="$(ls -1t "$LOGDIR"/*.kismet 2>/dev/null | head -n 1 || true)"
if [[ -n "${newest:-}" ]]; then
  ln -sfn "$newest" "$TARGET"
  echo "[REFRESH] symlinked $TARGET -> $newest"
else
  echo "[REFRESH] no .kismet files found in $LOGDIR"
fi
BASH
chmod +x "$ROOT/bin/refresh_kismet_db.sh"
log "Wrote refresh script to $ROOT/bin/refresh_kismet_db.sh"

# --- 5) Install systemd user timer
log "Installing systemd user timer to refresh kismet db symlink"
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/cyt-refresh-kismet-db.service" <<EOF
[Unit]
Description=Refresh CYT kismet.db symlink to newest Kismet log

[Service]
Type=oneshot
ExecStart=%h/cyt/bin/refresh_kismet_db.sh
EOF

cat > "$HOME/.config/systemd/user/cyt-refresh-kismet-db.timer" <<EOF
[Unit]
Description=Run cyt-refresh-kismet-db every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
Persistent=true
Unit=cyt-refresh-kismet-db.service

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload || true
systemctl --user enable --now cyt-refresh-kismet-db.timer || true

# --- 6) GUI env helper
ENV_FILE="$HOME/.config/cyt/env"
mkdir -p "$(dirname "$ENV_FILE")"
if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<ENV
# CYT GUI env (created by bootstrap)
export DISPLAY=':0'
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
ENV
  chmod 600 "$ENV_FILE"
  log "Created GUI env file: $ENV_FILE"
else
  log "GUI env file already exists: $ENV_FILE"
fi

# --- 7) Autostart desktop entry + Desktop launcher
AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_DIR="$HOME/Desktop"
mkdir -p "$AUTOSTART_DIR" "$DESKTOP_DIR"
cat > "$AUTOSTART_DIR/cyt-gui.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CYT GUI
Comment=Launch Chasing Your Tail (CYT)
Exec=$ROOT/start_gui.sh
Path=$ROOT
Icon=$ROOT/cyt_ng_logo.png
Terminal=false
EOF
chmod 644 "$AUTOSTART_DIR/cyt-gui.desktop"
cp -f "$AUTOSTART_DIR/cyt-gui.desktop" "$DESKTOP_DIR/cyt-gui.desktop" 2>/dev/null || true
log "Installed autostart entry and Desktop shortcut"

# --- 8) Patch start_gui.sh to load env
if [[ -f "$ROOT/start_gui.sh" ]]; then
  if ! grep -q '. "$HOME/.config/cyt/env"' "$ROOT/start_gui.sh" 2>/dev/null; then
    sed -i '1i. "$HOME/.config/cyt/env" || true' "$ROOT/start_gui.sh"
  fi
  chmod +x "$ROOT/start_gui.sh"
else
  log "Warning: start_gui.sh not found in $ROOT"
fi

# --- 9) Symlink /etc/kismet configs to project copies
info "Step 3 — Symlink Kismet configs into /etc/kismet"
if $ASSUME_YES; then DO_SYMLINK="Y"; else read -r -p "Symlink $ROOT/etc_kismet/*.conf into /etc/kismet/? (y/N): " DO_SYMLINK; fi
if [[ "${DO_SYMLINK:-N}" =~ ^[Yy] ]]; then
  sudo mkdir -p /etc/kismet
  for f in "$ROOT/etc_kismet"/*; do
    base=$(basename "$f")
    if [[ -f "/etc/kismet/$base" && ! -L "/etc/kismet/$base" ]]; then
      sudo mv "/etc/kismet/$base" "/etc/kismet/$base.bak.$(date +%s)" || true
      log "Backed up /etc/kismet/$base"
    fi
    sudo ln -sfn "$f" "/etc/kismet/$base"
    log "Symlinked /etc/kismet/$base -> $f"
  done
fi

# --- 10) Wigle API key prompt
WIGLE_FILE="$ROOT/secure_credentials/wigle_api.key"
info "Step 4 — Wigle API credentials (optional)"
if $ASSUME_YES; then ADD_WIGLE="N"; else read -r -p "Add Wigle API credentials now? (y/N): " ADD_WIGLE; fi
if [[ "${ADD_WIGLE:-N}" =~ ^[Yy] ]]; then
  echo "Create a Wigle API key at https://wigle.net" | tee -a "$LOGFILE"
  read -r -p "Wigle API username: " W_USER
  read -r -s -p "Wigle API password (hidden): " W_PASS; echo
  printf "%s:%s
" "$W_USER" "$W_PASS" > "$WIGLE_FILE"
  chmod 600 "$WIGLE_FILE"
  log "Saved Wigle credentials to $WIGLE_FILE"
else
  log "Skipping Wigle API setup"
fi

# --- 11) Python venv
info "Step 5 — Python virtualenv"
VENV_DIR="$ROOT/.venv"
if [[ ! -d "$VENV_DIR" ]]; then
  log "Creating Python venv at $VENV_DIR"
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel || true
fi
if [[ -f "$ROOT/requirements.txt" ]]; then
  log "Installing requirements.txt"
  "$VENV_DIR/bin/pip" install -r "$ROOT/requirements.txt" || log "pip install had non-fatal errors"
fi

# --- 12) Auto-activate venv
info "Step 6 — Auto-activate venv on cd"
if $ASSUME_YES; then AUTOACT="Y"; else read -r -p "Enable auto-activation when you cd into the project? (y/N): " AUTOACT; fi
if [[ "${AUTOACT:-N}" =~ ^[Yy] ]]; then
  if command -v direnv >/dev/null 2>&1; then
    log "Using direnv for auto-activation"
    echo "source \"$VENV_DIR/bin/activate\"" > "$ROOT/.envrc"
    (cd "$ROOT" && direnv allow) || log "direnv allow failed"
  else
    SHELL_RC="$HOME/.bashrc"; [[ -n "${ZSH_VERSION-}" ]] && SHELL_RC="$HOME/.zshrc"
    cat >> "$SHELL_RC" <<SNIP
# --- CYT project auto-activate ---
_cyt_auto_activate() {
  if [[ -z "${VIRTUAL_ENV-}" && -f "$ROOT/.venv/bin/activate" && "$PWD" == "$ROOT"* ]]; then
    source "$ROOT/.venv/bin/activate"
  fi
}
if [[ -n "${ZSH_VERSION-}" ]]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd _cyt_auto_activate
  _cyt_auto_activate
else
  PROMPT_COMMAND="_cyt_auto_activate;${PROMPT_COMMAND:-}"
fi
# --- end CYT auto-activate ---
SNIP
    log "Added auto-activate snippet to $SHELL_RC"
  fi
else
  log "Auto-activation skipped"
fi

# --- 13) Start Kismet and enforce web user creation (REQUIRED)
info "Step 7 — Start Kismet and ensure web user exists (REQUIRED)"
# Ensure we are running the newest available service binary; restart if already running
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable --now kismet || true
  sudo systemctl restart kismet || true
else
  # foreground fallback
  pkill -f '^kismet' 2>/dev/null || true
  nohup kismet >/dev/null 2>&1 & sleep 3 || true
fi
KISMET_UI="http://localhost:2501"
# Try to open the UI unless --no-browser is set
if ! $NO_BROWSER; then
  if command -v xdg-open >/dev/null 2>&1; then
    log "Opening Kismet web UI at $KISMET_UI"
    xdg-open "$KISMET_UI" || true
  fi
else
  log "--no-browser set; you MUST create the Kismet web user via $KISMET_UI before continuing."
fi

attempt_kismet_login() {
  local user="$1" pass="$2"
  local endpoints=("$KISMET_UI/api/session/login" "$KISMET_UI/sessions" "$KISMET_UI/api/sessions" "$KISMET_UI/session")
  for ep in "${endpoints[@]}"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
      -d "{\"username\":\"$user\",\"password\":\"$pass\"}" "$ep" || true)
    if [[ "$code" == "200" || "$code" == "201" ]]; then
      return 0
    fi
  done
  return 1
}

while true; do
  echo
  echo "== Kismet web user requirement =="
  echo "A Kismet web user (username/password) must exist before this bootstrap will continue."
  echo "If you do not have a user yet, create one in the Kismet web UI at: $KISMET_UI"
  echo
  read -r -p "Enter Kismet web username to test (or type 'skip' to open UI and create manually): " KUSER
  if [[ "$KUSER" == "skip" ]]; then
    echo "Please create a web user in the browser now. When finished, return here and type the username to test."
    read -r -p "Press Enter when the web user has been created..." _
    continue
  fi
  read -r -s -p "Enter Kismet web password for $KUSER: " KPASS; echo

  log "Attempting to verify Kismet web credentials for user '$KUSER' (best-effort)"
  if attempt_kismet_login "$KUSER" "$KPASS"; then
    log "Kismet web login test succeeded for user $KUSER"
    # store a note (not the password) to assist operators later
    mkdir -p "$ROOT/secure_credentials"
    printf "kismet_user=%s
verified_at=%s
" "$KUSER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$ROOT/secure_credentials/kismet_web_user.txt"
    chmod 600 "$ROOT/secure_credentials/kismet_web_user.txt"
    break
  else
    err "Kismet login test failed. If you chose --no-browser, you must create the web user via the web UI."
    read -r -p "Would you like to open the Kismet web UI now to create the user? (y/N): " openit
    openit=${openit:-N}
    if [[ "$openit" =~ ^[Yy] ]]; then
      if command -v xdg-open >/dev/null 2>&1; then xdg-open "$KISMET_UI" || true; fi
      echo "Open the UI, create the user, then return here and enter the username to test."
    fi
    echo "Retrying..."
    sleep 1
  fi
done

# --- 14) Post-install health checks
info "Health checks"
# Check port 2501 listening
if ss -ltn 2>/dev/null | grep -q ':2501 '; then
  log "Kismet UI port 2501 is listening"
else
  log "Kismet port 2501 not detected; UI may not be up yet"
fi
# Check logs dir writable
if [[ -w "$ROOT/logs" ]]; then
  log "Logs directory writable"
else
  err "Logs directory not writable: $ROOT/logs"
fi

# --- Final notes
info "Bootstrap finished — Kismet web user verified and Kismet updated to newest available"
cat <<EOF | tee -a "$LOGFILE"
Artifacts:
  - Project root: $ROOT
  - Log file for this run: $LOGFILE
  - Venv: $VENV_DIR
  - Autostart: $AUTOSTART_DIR/cyt-gui.desktop
  - Desktop shortcut: $DESKTOP_DIR/cyt-gui.desktop
  - Wigle creds (if provided): $WIGLE_FILE
  - Kismet web user verified ($KUSER) and recorded in $ROOT/secure_credentials/kismet_web_user.txt
  - Kismet version: $(get_kismet_version)

EOF | tee -a "$LOGFILE"
Artifacts:
  - Project root: $ROOT
  - Log file for this run: $LOGFILE
  - Venv: $VENV_DIR
  - Autostart: $AUTOSTART_DIR/cyt-gui.desktop
  - Desktop shortcut: $DESKTOP_DIR/cyt-gui.desktop
  - Wigle creds (if provided): $WIGLE_FILE
  - Kismet web user verified and recorded in $ROOT/secure_credentials/kismet_web_user.txt

Run non-interactively next time with: ./bootstrap.sh --yes --skip-update
EOF

# End of script

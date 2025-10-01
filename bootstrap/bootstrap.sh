#!/usr/bin/env bash
# CYT Bootstrap — idempotent setup for this host
set -euo pipefail

ME="$(readlink -f "$0")"
ROOT="$(cd "$(dirname "$ME")/.." && pwd)"
USER_NAME="$(id -un)"
LOG(){ printf "[BOOTSTRAP] %s\n" "$*"; }

LOG "Project root: $ROOT"

# 1) Ensure expected dirs exist
mkdir -p "$ROOT/logs" "$ROOT/reports" "$ROOT/surveillance_reports" "$ROOT/kml_files"
mkdir -p "$ROOT/secure_credentials" "$ROOT/etc_kismet" "$ROOT/bin"

# 2) Kismet logs -> project logs (already configured in etc_kismet/kismet_site.conf)
if grep -q '^log_prefix=' /etc/kismet/kismet_site.conf 2>/dev/null; then
  cur=$(grep '^log_prefix=' /etc/kismet/kismet_site.conf | cut -d= -f2-)
  LOG "Current system log_prefix: $cur"
else
  LOG "NOTE: /etc/kismet/kismet_site.conf not readable; you may be using the project symlink."
fi

# 3) Maintain ~/cyt/kismet.db symlink to newest .kismet (for CYT)
cat > "$ROOT/bin/refresh_kismet_db.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
LOGDIR="$HOME/cyt/logs"
TARGET="$HOME/cyt/kismet.db"
newest="$(ls -1t "$LOGDIR"/*.kismet 2>/dev/null | head -n 1 || true)"
if [[ -n "${newest:-}" ]]; then
  ln -sfn "$newest" "$TARGET"
fi
BASH
chmod +x "$ROOT/bin/refresh_kismet_db.sh"

# 4) Systemd user unit + timer to refresh symlink every minute
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

systemctl --user daemon-reload
systemctl --user enable --now cyt-refresh-kismet-db.timer

# 5) GUI env helper (does NOT store your master password)
ENV_FILE="$HOME/.config/cyt/env"
if ! grep -q '^export DISPLAY=' "$ENV_FILE" 2>/dev/null; then
  {
    echo "export DISPLAY=':0'"
    echo 'export XDG_RUNTIME_DIR="/run/user/$(id -u)"'
    # Uncomment the next line if you want to auto-set password at login (not recommended):
    # echo "export CYT_MASTER_PASSWORD='your-password-here'"
  } >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
LOG "Wrote GUI env to $ENV_FILE"

# 6) Autostart desktop entry (uses start_gui.sh)
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
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
LOG "Autostart entry installed: $AUTOSTART_DIR/cyt-gui.desktop"

# 7) Make sure start_gui.sh is executable and loads env
if ! grep -q '. "$HOME/.config/cyt/env"' "$ROOT/start_gui.sh"; then
  sed -i '1a . "$HOME/.config/cyt/env" || true' "$ROOT/start_gui.sh"
fi
chmod +x "$ROOT/start_gui.sh"

# 8) Optional: ensure Kismet configs are symlinked from project (requires sudo)
if [[ ! -L /etc/kismet/kismet_site.conf ]] || [[ ! -L /etc/kismet/kismet.conf ]]; then
  LOG "You can link system Kismet configs to project copies with:"
  echo "  sudo mv /etc/kismet/kismet_site.conf /etc/kismet/kismet_site.conf.bak 2>/dev/null || true"
  echo "  sudo ln -s \"$ROOT/etc_kismet/kismet_site.conf\" /etc/kismet/kismet_site.conf"
  echo "  sudo mv /etc/kismet/kismet.conf /etc/kismet/kismet.conf.bak 2>/dev/null || true"
  echo "  sudo ln -s \"$ROOT/etc_kismet/kismet.conf\" /etc/kismet/kismet.conf"
else
  LOG "Kismet configs already symlinked to project."
fi

# 9) Nudge the symlink now
"$ROOT/bin/refresh_kismet_db.sh" || true

LOG "Bootstrap complete. You can log out/in to trigger autostart, or run:"
LOG "  ( . ~/.config/cyt/env && cd \"$ROOT\" && nohup python3 cyt_gui.py >> \"$ROOT/gui_startup.log\" 2>&1 & )"

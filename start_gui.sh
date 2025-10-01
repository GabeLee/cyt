# Source CYT environment
[ -f "$HOME/.config/cyt/env" ] && . "$HOME/.config/cyt/env"

#!/usr/bin/env bash
# minimal launcher for CYT (no sleeps, correct cwd)
cd /home/kali/cyt || exit 1
exec /usr/bin/python3 cyt_gui.py
# Auto environment for CYT GUI
export CYT_MASTER_PASSWORD='XUB*khfcr7C@Vz.fRJ*jxP_'
export DISPLAY=':0'
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

#!/usr/bin/env bash
set -euo pipefail
cd /home/kali/cyt
latest=$(ls -1t /home/kali/cyt/logs/*.kismet | head -n 1)
sudo ln -sf "$latest" /var/lib/kismet/kismet.db
echo "Linked /var/lib/kismet/kismet.db -> $latest"
exec python3 chasing_your_tail.py

# Chasing Your Tail (CYT)

Chasing Your Tail (CYT) is a comprehensive Wi-Fi probe request analyzer originally developed by **ArgeliusLabs**, and further enhanced and maintained by **Gabe Lee**.  
It integrates with **Kismet** for packet capture and the **WiGLE API** for SSID geolocation, providing advanced surveillance detection, persistence scoring, and powerful visualization outputs.  

This fork includes:
- A **bootstrap script** for consistent setup  
- Full integration of **encrypted credential storage**  
- All **Kismet configuration files** tracked under version control (`etc_kismet/`)  
- Improved **autostart and GUI launch flow**  
- Hardened security and safer defaults  

---

## Security Notice

This project has been hardened against common vulnerabilities:

- **SQL injection prevention** via parameterized queries  
- **Encrypted credential management** for API keys  
- **Input validation & sanitization**  
- **Secure ignore list loading** (no `exec()`)  

**First-time setup required:**  
Run `python3 migrate_credentials.py` to migrate any API keys to secure storage.

---

## Features

- **Real-time Wi-Fi monitoring** with Kismet integration  
- **Advanced surveillance detection** with persistence scoring  
- **Automatic GPS integration** from Bluetooth GPS via Kismet  
- **Location clustering** with 100m threshold  
- **KML visualization** for Google Earth (color-coded markers, heatmaps, paths)  
- **Multi-format reporting** (Markdown, HTML, KML)  
- **Time-window tracking** (5, 10, 15, 20 min)  
- **WiGLE API integration** for SSID geolocation  
- **GUI interface** with surveillance analysis tools  
- **Organized project structure** for logs, reports, and configs  

---

## Requirements

- Python 3.8+  
- Linux-based system (tested on Raspberry Pi + Kali)  
- Wi-Fi adapter supporting monitor mode  
- **Kismet** (for packet capture)  
- WiGLE API key (optional, for SSID geolocation)  

---

## Installation & Setup

### 1. Install Dependencies
```bash
pip3 install -r requirements.txt
```

### 2. Configure Kismet
Configs are version-controlled in **`etc_kismet/`** for reproducibility.  
System paths are symlinked to project copies:

```
/etc/kismet/kismet.conf        -> ~/cyt/etc_kismet/kismet.conf
/etc/kismet/kismet_site.conf   -> ~/cyt/etc_kismet/kismet_site.conf
```

Kismet logs are redirected to:
```
~/cyt/logs/
```

CYT always references:
```
~/cyt/kismet.db (symlink to newest .kismet log)
```

A systemd user timer refreshes this symlink automatically every minute.

### 3. Secure Credentials
Stored under:
```
~/cyt/secure_credentials/encrypted_credentials.json
```

Your **master password** is loaded automatically via:
```
export CYT_MASTER_PASSWORD='your_password'
```

This can be set in:
- `~/.profile` (auto on login), or  
- `~/cyt/start_gui.sh` (auto with GUI start)  

### 4. Bootstrap Script
For consistent startup and environment setup, run:
```bash
./start_gui.sh
```

This handles:
- Exporting `CYT_MASTER_PASSWORD`, `DISPLAY`, etc.  
- Starting Kismet cleanly  
- Launching the CYT GUI  

### 5. Autostart (Optional)
A `.desktop` entry is included:
```
~/.config/autostart/cyt-gui.desktop
```

This ensures CYT starts automatically on the Pi touchscreen.

---

## Usage

### GUI Interface
```bash
python3 cyt_gui.py
```

Features:
- Surveillance Analysis (GPS + KML)  
- Analyze Logs (historical probes)  
- Secure credential prompts (or env auto-load)  

### CLI
```bash
# Core monitoring
python3 chasing_your_tail.py

# Probe analysis (default = 14 days)
python3 probe_analyzer.py

# Probe analysis with WiGLE API (consumes credits)
python3 probe_analyzer.py --wigle

# Surveillance detection
python3 surveillance_analyzer.py
```

---

## Project Structure

```
cyt/
├── bin/                      # helper scripts (refresh_kismet_db.sh, etc.)
├── etc_kismet/               # version-controlled Kismet configs
├── logs/                     # Kismet + CYT logs (.gitkeep tracked, real logs ignored)
├── reports/                  # probe analysis reports
├── surveillance_reports/     # surveillance analysis (HTML, MD, KML)
├── secure_credentials/       # encrypted API keys & tokens
├── cyt_gui.py                # GUI entrypoint
├── chasing_your_tail.py      # core monitoring engine
├── probe_analyzer.py         # probe analysis tool
├── surveillance_analyzer.py  # advanced analysis + KML
├── gps_tracker.py            # GPS integration & clustering
├── start_gui.sh              # bootstrap script
├── config.json               # sanitized project config
└── README.md                 # this file
```

---

## Security Features

- Parameterized SQL queries (no injection risk)  
- Encrypted credential storage (Fernet + master password)  
- Input sanitization (validated via `input_validation.py`)  
- Safe ignore lists (JSON only)  
- Audit logging of security events  

---

## Technical Architecture

- **Time windows** (5/10/15/20 min) track persistence  
- **Surveillance scoring** (0–1.0 weighted)  
- **GPS correlation** from Kismet logs  
- **KML visualizations** (Google Earth, paths, clustering)  
- **Multi-location following detection**  

---

## Authors

- Original concept: **ArgeliusLabs**  
- Security hardening, bootstrap scripts, autostart, and system integration: **Gabe Lee**  

---

## License

MIT License  

---

## Disclaimer

This tool is intended for **legitimate research, network defense, and safety use cases only**.  
You are responsible for complying with laws and regulations in your jurisdiction.  
Unauthorized surveillance or misuse is strictly prohibited.

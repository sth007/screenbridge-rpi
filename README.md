# AutoVNC RPi1 (Linux → Raspberry Pi → HDMI)

AutoVNC macht aus einem **Raspberry Pi 1** einen **autostartenden VNC-Client**, der den Bildschirm
eines **Linux‑Laptops (z. B. Linux Mint)** automatisch auf einem **HDMI‑Display / TV** anzeigt.

Der Raspberry Pi wird vollständig **headless** betrieben und über eine **HTTPS‑WebUI**
konfiguriert.

---

## Features

- Raspberry Pi 1 als **VNC‑Client**
- Linux Mint (oder X11‑Linux) als **VNC‑Server**
- Autostart nach Boot (kein Login nötig)
- HDMI‑Ausgabe (720p oder 1080p)
- WebUI (HTTPS) für:
  - WLAN‑Konfiguration
  - VNC‑Host & Passwort
  - Startparameter (Delay, Quality, ViewOnly)
  - **HDMI‑Auflösung**
  - **WebUI‑Farbschema (Light / Dark / Blue / Custom)**
- Keine Eingaben am Pi nötig

---

## Architektur

```
Linux Laptop (x11vnc :5900)
        │
        │  VNC
        ▼
Raspberry Pi 1 (vncviewer)
        │
        ▼
     HDMI / TV
```

---

## Raspberry‑Pi‑Installation

### Voraussetzungen
- Raspberry Pi 1 (ARMv6)
- Raspberry Pi OS / Debian Bookworm ARMHF Lite
- ≥ 4 GB SD‑Karte

### Installation

```bash
chmod +x setup_pi1_autovnc_with_webui.sh
sudo ./setup_pi1_autovnc_with_webui.sh
```

Danach:
- WebUI: `https://<PI-IP>`
- Login: `admin / admin123`
- Autostart erfolgt automatisch nach Reboot

---

## WebUI – Einstellungen

### Netzwerk
- WLAN‑Land, SSID, Passwort

### VNC
- Hostname / IP des Linux‑Laptops
- Passwort (wird lokal als Datei gespeichert)
- Fullscreen / ViewOnly
- Quality & Compress
- Start‑Delay

### HDMI‑Auflösung
- **720p (empfohlen)** – stabil auf RPi1
- 1080p (experimentell)

> Nach Änderung der Auflösung ist ein Reboot erforderlich (Button erscheint automatisch).

### WebUI‑Farben
- Light / Dark / Blue
- Custom‑Theme mit:
  - Hintergrundfarbe
  - Textfarbe
  - Akzentfarbe

Änderungen werden **sofort** wirksam (kein Neustart nötig).

---

## Linux‑Laptop‑Setup (VNC‑Server)

Der Linux‑Desktop wird mit **x11vnc** geteilt und als **systemd‑User‑Service**
automatisch beim Login gestartet.

### Installation (Linux Mint)

```bash
chmod +x setup_mint_x11vnc_systemd.sh
./setup_mint_x11vnc_systemd.sh
```

- Port: `5900`
- Passwort: `~/.vnc/passwd`

Service‑Status:
```bash
systemctl --user status x11vnc.service
```

Logs:
```bash
journalctl --user -u x11vnc.service -f
```

Firewall (falls aktiv):
```bash
sudo ufw allow 5900/tcp
```

---

## Sicherheit

- WebUI über HTTPS (self‑signed Zertifikat)
- HTTP Basic Auth
- VNC‑Passwörter werden **nicht** im Klartext gespeichert
- Keine Cloud‑Abhängigkeiten

---

## Lizenz

Empfohlen:
**Creative Commons BY‑NC‑SA 4.0**

- Private Nutzung erlaubt
- **Kommerzielle Nutzung nicht erlaubt**
- Weitergabe nur unter gleichen Bedingungen


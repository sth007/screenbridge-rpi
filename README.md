# AutoVNC RPi1 (Linux → Raspberry Pi → HDMI)

Dieses Projekt macht aus einem **Raspberry Pi 1** einen **VNC-Client**, der den Bildschirm eines **Linux Mint (oder allgemein Linux/X11) Laptops** automatisch auf **HDMI/TV** anzeigt.

✅ Linux Laptop = **VNC Server** (x11vnc)  
✅ Raspberry Pi 1 = **VNC Client** (vncviewer)  
✅ Konfiguration per **WebUI (HTTPS)**: WLAN, VNC Host/Passwort, Startoptionen, **HDMI-Auflösung**

---

## Architektur

```
Linux Laptop (x11vnc, Port 5900)  --->  Raspberry Pi 1 (vncviewer)  --->  HDMI/TV
```

---

## Raspberry Pi Setup

### Voraussetzungen
- Raspberry Pi 1 (ARMv6)
- Raspberry Pi OS (Legacy) / Debian Bookworm ARMHF Lite
- SD-Karte (>= 4GB empfohlen)

### Installation (auf dem Pi)
1. Script auf den Pi kopieren
2. Ausführen:

```bash
chmod +x setup_pi1_autovnc_with_webui.sh
sudo ./setup_pi1_autovnc_with_webui.sh
```

Danach:
- WebUI: `https://<PI-IP>`
- Standard Login: `admin / admin123`
- Der Pi startet automatisch eine GUI (LightDM/Openbox) und startet danach den VNC Viewer.

---

## WebUI: Konfiguration

In der Weboberfläche kannst du einstellen:

### WLAN
- Country / SSID / Passwort

### VNC
- **VNC Host**: IP/Hostname des Linux-Laptops
- **VNC Passwort**: wird auf dem Pi als Datei gespeichert (für Auto-Connect)
- Fullscreen / ViewOnly
- Quality / Compress
- Boot-Delay

### HDMI-Auflösung (Output Mode)
- **720p (1280x720)** – empfohlen, stabil auf Pi 1
- **1080p (1920x1080)** – kann funktionieren, ist aber deutlich schwerer für Pi 1

⚠️ Nach Änderung der Auflösung ist ein **Reboot** nötig.  
Die WebUI zeigt dann automatisch einen Reboot-Button an.

---

## Linux Mint Setup (VNC Server)

Auf dem Linux Mint Laptop wird der Desktop mit **x11vnc** geteilt – als **systemd user service** (startet automatisch beim Login).

### Installation
```bash
chmod +x setup_mint_x11vnc_systemd.sh
./setup_mint_x11vnc_systemd.sh
```

Danach:
- Port: **5900**
- Passwort: `~/.vnc/passwd` (wird beim Setup gesetzt)
- Service:
  - Status: `systemctl --user status x11vnc.service`
  - Logs: `journalctl --user -u x11vnc.service -f`

### Firewall (falls nötig)
Wenn `ufw` aktiv ist:
```bash
sudo ufw allow 5900/tcp
```

---

## Troubleshooting

### WebUI zeigt 500 Internal Server Error
Prüfe:
```bash
sudo journalctl -u autovnc-web.service -n 200 --no-pager
```

### Pi zeigt nur Desktop, kein VNC-Bild
- Ist der Linux-Laptop erreichbar?
```bash
nc -vz <LINUX-IP> 5900
```
- Läuft `x11vnc`?
```bash
systemctl --user status x11vnc.service
```

### Auflösung / schwarzer Bildschirm am Pi
- Stelle im WebUI wieder auf **720p** und reboote.
- Pi 1 ist bei 1080p oft zu schwach.

---

## Security
- WebUI ist per HTTPS (self-signed) abgesichert, Login via HTTP Basic Auth.
- VNC Passwort wird am Pi als Datei abgelegt (`/home/pi/.vnc/client.passwd`).
  - Nicht öffentlich teilen.
  - Repo ohne echte Passwörter committen.

---

## License
(Deine Lizenz hier eintragen, z.B. CC BY-NC-SA 4.0, wenn du Non-Commercial willst)


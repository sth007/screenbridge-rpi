# TVStreamer – Headless HDMI Screen Mirroring via Raspberry Pi

TVStreamer ist ein leichtgewichtiges Setup, um den **Bildschirm eines Linux-Laptops**
automatisch über einen **Raspberry Pi (RPi 1)** per **HDMI auf einem Fernseher**
anzuzeigen – **ohne Tastatur oder Maus am Raspberry Pi**.

Die Konfiguration (WLAN, Ziel-IP, VNC-Optionen) erfolgt bequem über eine
**Weboberfläche (HTTPS)**.

---

## 🧩 Ziel & Motivation

- Alte Raspberry-Pi-Hardware sinnvoll weiterverwenden
- Kein Chromecast / Miracast nötig
- Stabiler Dauerbetrieb (z. B. Präsentationen, Infodisplays)
- Zentrale Konfiguration per Browser
- Automatischer Start nach Reboot

---

## 🖥️ Systemübersicht & Kommunikation

```
                 (HTTPS)
   +-------------------------------+
   |           Webbrowser          |
   |   Konfiguration (WebUI)       |
   +---------------+---------------+
                   |
                   v
+------------------+------------------+
|           Raspberry Pi 1            |
|------------------------------------|
|  - WLAN Client                     |
|  - LightDM + Openbox               |
|  - VNC Client (Fullscreen)         |
|  - WebUI (Flask)                   |
|                                    |
|  HDMI OUT --------------------+    |
+------------------------------ | ---+
                               |
                               v
                        +------+------
                        |     TV      |
                        |  HDMI IN    |
                        +-------------

        ^
        |
        |   (VNC)
        |
+-------+-----------------------------+
|         Linux Laptop (Mint)          |
|-------------------------------------|
|  - VNC Server                        |
|  - Desktop / Browser / Apps         |
+-------------------------------------+
```

**Kurz erklärt:**  
Der Raspberry Pi verbindet sich automatisch mit dem WLAN, startet eine minimale
grafische Oberfläche und öffnet eine VNC-Verbindung zum Linux-Laptop. Das Bild
wird per HDMI an den Fernseher ausgegeben. Alle Einstellungen können über eine
HTTPS-Weboberfläche geändert werden.

---

## 🔄 Kommunikationsfluss

1. **macOS (Deployment)**
   - Kopiert Setup-Skripte per SSH auf den Raspberry Pi
   - Führt die Installation remote aus

2. **Raspberry Pi**
   - Verbindet sich automatisch mit dem WLAN
   - Startet GUI (LightDM + Openbox)
   - Öffnet VNC-Verbindung zum Laptop
   - Gibt Bild über HDMI aus

3. **Webbrowser**
   - Zugriff per HTTPS auf WebUI
   - WLAN- und VNC-Ziel konfigurieren
   - Änderungen werden gespeichert & angewendet

---

## 🚀 Features

- ✅ Automatischer Start nach Reboot
- ✅ Headless Betrieb (kein Login nötig)
- ✅ Webbasierte Konfiguration (HTTPS)
- ✅ SSH-Key-Deployment
- ✅ Optimiert für Raspberry Pi 1
- ✅ Keine Cloud / keine Fremddienste

---

## 📦 Repository-Struktur

```
.
├── deploy_to_pi.sh
├── setup_pi1_autovnc_with_webui.sh
├── README.md
```

---

## 🛠️ Installation (Kurzfassung)

### Voraussetzungen
- macOS (für Deployment)
- Raspberry Pi OS **Legacy Lite**
- Raspberry Pi 1
- HDMI-TV
- Linux Laptop mit VNC-Server

### Deployment
```bash
chmod +x deploy_to_pi.sh
./deploy_to_pi.sh --host raspberrypi.local --reboot
```

---

## 🌐 Weboberfläche

Nach dem Setup erreichbar unter:

```
https://<PI-IP>
```

Konfigurierbar:
- WLAN SSID & Passwort
- VNC-Ziel (Laptop IP / Hostname)
- VNC-Qualität
- Startverzögerung

---

## ⚠️ Einschränkungen

- Nicht für Gaming geeignet (VNC-Latenz)
- Video-Wiedergabe abhängig von Netzwerk & Auflösung
- Raspberry Pi 1 ist leistungsschwach → bewusst minimalistisches Setup

---

## 🧠 Technischer Hintergrund

- **VNC** für Bildschirmübertragung
- **Openbox** als Window Manager
- **LightDM** für Autologin
- **Flask (APT)** für WebUI
- **systemd** für Autostart & Services
- **Nginx + SSL** für HTTPS

---

## 📜 Lizenz

MIT License – freie Nutzung & Anpassung.

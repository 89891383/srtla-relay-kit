# 📡 srtla-relay-kit

One-command SRT + SRTLA relay server for IRL streaming. Bond multiple cellular connections for rock-solid outdoor broadcasts.

![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-Ubuntu%2022.04-orange)
![Oracle Cloud](https://img.shields.io/badge/Oracle%20Cloud-Free%20Tier-red)

## What is this?

A self-hosted relay server that combines **[SRT Live Server (b3ck edit)](https://github.com/b3ck/sls-b3ck-edit)** and **[SRTLA (BELABOX)](https://github.com/BELABOX/srtla)** into a single installer. Send your IRL stream over multiple cellular connections (bonding), and receive a single stable stream in OBS at home.

```
┌──────────────────┐                          ┌─────────────────────┐
│  Moblin / Belabox │    SRTLA (bonded)        │    Your VPS         │
│  (on the street)  │ ── SIM 1 ──┐             │                     │
│                   │ ── SIM 2 ──┼──▶ :30001  │  srtla_rec ──▶ SLS  │
│                   │ ── WiFi  ──┘    (UDP)    │                     │
└──────────────────┘                          │  :30000 (SRT)       │
                                               │  :8181  (stats)     │
┌──────────────────┐    SRT play               └─────────────────────┘
│  OBS at home      │ ◀──── :30000 ────────────       │
│  (receive stream) │                                  │
└──────────────────┘                                   │
        │                                              │
        ▼                                              │
   Twitch / Kick / YouTube                             │
```

### Key Features

- **SRTLA bonding** — combine multiple internet connections (cellular + WiFi) for redundancy
- **Open feeds** — any stream name works without config changes (`feed1`, `mycam`, `anything`)
- **HTTP stats** — JSON endpoint for NOALBS integration (auto scene switching)
- **One-command install** — compiles everything from source, sets up systemd, opens firewall
- **Oracle Cloud Free Tier compatible** — runs on `VM.Standard.E2.1.Micro` (1 OCPU, 1GB RAM)

---

## Quick Start

### Prerequisites

- Ubuntu 22.04 VPS (Oracle Cloud Free Tier, AWS, DigitalOcean, etc.)
- SSH access with root/sudo
- Ports 30000/UDP, 30001/UDP, 8181/TCP open

### Install

```bash
git clone https://github.com/YOUR_USERNAME/srtla-relay-kit.git
cd srtla-relay-kit
sudo bash install.sh
```

That's it. The installer will:
1. Install build dependencies
2. Set up swap (for low-RAM instances)
3. Compile libSRT from [Haivision/srt](https://github.com/Haivision/srt)
4. Compile SRT Live Server from [b3ck/sls-b3ck-edit](https://github.com/b3ck/sls-b3ck-edit)
5. Compile SRTLA receiver from [BELABOX/srtla](https://github.com/BELABOX/srtla)
6. Write config with open feeds
7. Create systemd services (auto-start on boot)
8. Configure iptables firewall

### Custom Ports

```bash
SLS_PORT=40000 SRTLA_PORT=40001 HTTP_PORT=9090 sudo bash install.sh
```

---

## Usage

After installation, you get three endpoints (replace `YOUR_IP` with your server's public IP):

| Purpose | Protocol | URL |
|---------|----------|-----|
| **Publish (single)** | SRT | `srt://YOUR_IP:30000?streamid=publish/live/STREAM` |
| **Publish (bonded)** | SRTLA | `srtla://YOUR_IP:30001?streamid=publish/live/STREAM` |
| **Play (receive)** | SRT | `srt://YOUR_IP:30000?streamid=play/live/STREAM` |
| **Stats** | HTTP | `http://YOUR_IP:8181/stats` |

`STREAM` can be any name — `feed1`, `mycam`, `stream123`. No config changes needed.

> **Publish and Play must use the same STREAM name** to connect.

---

## Client Setup

### Moblin (iOS)

1. Settings → Streams → Add
2. URL: `srtla://YOUR_IP:30001?streamid=publish/live/mystream`
3. Codec: H.265/HEVC
4. Bitrate: 6000 kbps
5. Adaptive bitrate: ON

### Belabox

1. Open belaUI → SRTLA Settings
2. SRTLA receiver address: `YOUR_IP`
3. SRTLA receiver port: `30001`
4. SRT streamid: `publish/live/mystream`
5. SRT latency: `2000` ms

### OBS Studio (receive)

1. Sources → Media Source
2. Uncheck "Local File"
3. Input: `srt://YOUR_IP:30000?streamid=play/live/mystream`
4. Input Format: `mpegts`
5. Reconnect Delay: `3`
6. ✅ Use hardware decoding when available
7. ✅ Show nothing when playback ends
8. ❌ Close file when inactive (keep unchecked!)

### VLC

```
Media → Open Network Stream:
srt://YOUR_IP:30000?streamid=play/live/mystream
```

---

## Oracle Cloud Free Tier Setup

### Step 1: Open Ports in Security List

Before installing, open ports in the Oracle Cloud Console:

1. Go to **Networking → Virtual Cloud Networks** → click your VCN
2. Click your **subnet** → click **Security List**
3. Click **"Add Ingress Rules"** and add:

| Source CIDR | Protocol | Dest. Port | Description |
|-------------|----------|------------|-------------|
| `0.0.0.0/0` | UDP | 30000 | SRT |
| `0.0.0.0/0` | UDP | 30001 | SRTLA |
| `0.0.0.0/0` | TCP | 8181 | Stats |

> ⚠️ **This is critical** — Oracle blocks ports at the network level, not just the OS firewall.

### Step 2: SSH and Install

```bash
ssh -i your_key.pem ubuntu@YOUR_IP
git clone https://github.com/YOUR_USERNAME/srtla-relay-kit.git
cd srtla-relay-kit
sudo bash install.sh
```

### Resource Usage

On `VM.Standard.E2.1.Micro` (1 OCPU, 1GB RAM, 0.48 Gbps):

| Resource | Usage |
|----------|-------|
| CPU | 2-5% (one active stream) |
| RAM | 30-60 MB |
| Network | ~16 Mbps peak (8 Mbps in + 8 Mbps out) |
| Bandwidth cap | 0.48 Gbps = plenty of headroom |

---

## Management

```bash
# Status
sudo systemctl status sls srtla

# Quick status check
sudo bash /opt/srtla-relay/status.sh

# Restart both services
sudo systemctl restart sls srtla

# View logs (live)
sudo journalctl -u sls -u srtla -f

# Edit config
sudo nano /etc/sls/sls.conf
sudo systemctl restart sls srtla   # after changes

# Check active streams
curl -s http://localhost:8181/stats | python3 -m json.tool
```

---

## Configuration

Config file: `/etc/sls/sls.conf`

```
srt {
    worker_threads  1;           # Worker threads (1 is enough)
    worker_connections 300;      # Max simultaneous connections

    http_port 8181;              # Stats endpoint port
    cors_header *;               # CORS (for NOALBS etc.)

    server {
        listen 30000;            # SRT port
        latency 1000;            # Latency in ms
                                 # Increase to 2000 on unstable networks
                                 # Decrease to 500 on stable networks

        domain_player play;      # Play URL prefix
        domain_publisher publish; # Publish URL prefix

        default_sid publish/live/feed1;  # Default stream ID

        idle_streams_timeout 10; # Seconds before closing idle stream

        app {
            app_player live;     # App name: play/LIVE/name
            app_publisher live;  # App name: publish/LIVE/name
        }
    }
}
```

### How Stream IDs Work

Stream ID format: `domain/app/name`

- **Publish:** `publish/live/ANY_NAME`
- **Play:** `play/live/ANY_NAME`

`ANY_NAME` is truly anything — `feed1`, `mycam`, `stream_abc`. No config changes needed. Anyone who knows your server IP and stream name can publish or play.

> ⚠️ There's no authentication — if you need security, use non-standard ports and treat stream names as passwords, or restrict access via iptables.

---

## NOALBS Integration

[NOALBS](https://github.com/NOALBS/nginx-obs-automatic-low-bitrate-switching) automatically switches OBS scenes based on bitrate (LIVE → LOW → BRB).

Add this to your NOALBS `config.json`:

```json
{
  "streamServer": {
    "type": "SrtLiveServer",
    "statsUrl": "http://YOUR_IP:8181/stats",
    "publisher": "publish/live/mystream"
  },
  "name": "SRT Relay",
  "priority": 0,
  "overrideScenes": null,
  "dependsOn": null,
  "enabled": true
}
```

---

## Architecture

```
Phone (Moblin/Belabox)
  │
  ├── SIM 1 (Carrier A) ──┐
  ├── SIM 2 (Carrier B) ──┼──▶ :30001/UDP [srtla_rec]
  ├── WiFi ────────────────┘       │
  │                                │  (reassembles packets from
  │                                │   multiple connections into
  │                                │   a single SRT stream)
  │                                ▼
  │                          :30000/UDP [SLS]
  │                                │
  │                                │  (manages publish/play,
  │                                │   routes streams, stats)
  │                                ▼
  │                          :30000/UDP [SLS play output]
  │                                │
  ▼                                ▼
OBS at home ◀── SRT play ──────────
  │
  ▼
Twitch / Kick / YouTube
```

1. **SRTLA** (`srtla_rec`) listens on port 30001/UDP. Receives packets from multiple connections (bonding) and reassembles them into a single SRT stream, forwarding to localhost:30000.

2. **SLS** (`sls`) listens on port 30000/UDP. Handles both direct SRT connections and those forwarded by SRTLA. Manages streams (publish/play), serves HTTP stats.

3. **OBS** connects to port 30000/UDP with `streamid=play/live/name` and receives the stream.

---

## File Structure

```
/opt/srtla-relay/
├── bin/
│   ├── sls              # SRT Live Server binary
│   ├── slc              # SRT Live Client (testing)
│   └── srtla_rec        # SRTLA receiver binary
├── logs/
│   └── sls.log          # SLS log file
└── status.sh            # Quick status script

/etc/sls/
└── sls.conf             # SLS configuration

/etc/systemd/system/
├── sls.service          # SLS systemd unit
└── srtla.service        # SRTLA systemd unit
```

---

## Troubleshooting

### "Connection refused"

1. Check Oracle Cloud Security List (most common issue)
2. Check iptables: `sudo iptables -L -n | grep 3000`
3. Check services: `sudo systemctl status sls srtla`
4. Check logs: `sudo journalctl -u sls --no-pager -n 50`

### SRTLA won't start

```bash
# SLS must be running first (SRTLA depends on it)
sudo systemctl status sls
sudo journalctl -u sls --no-pager -n 20

# Check if port is in use
sudo ss -ulnp | grep 30000
```

### Stream freezes / pixelates

- Increase `latency` in sls.conf (e.g., 1000 → 2000)
- Lower bitrate in Moblin/Belabox (e.g., 6000 → 4000 kbps)
- Check stats: `curl http://YOUR_IP:8181/stats`

### "publisher is NULL" in logs

This is normal — it means a player (OBS) is trying to watch a stream that nobody is publishing yet. Once you start streaming from Moblin/Belabox, the message stops and OBS picks up the stream.

---

## Uninstall

```bash
sudo bash uninstall.sh
```

---

## Credits

- **[b3ck](https://github.com/b3ck/sls-b3ck-edit)** — SRT Live Server edit for IRL community
- **[BELABOX / rationalIRL](https://github.com/BELABOX/srtla)** — SRTLA bonding proxy
- **[Haivision](https://github.com/Haivision/srt)** — SRT protocol
- **[Edward Wu](https://github.com/Edward-Wu/srt-live-server)** — Original SRT Live Server
- **[NOALBS](https://github.com/NOALBS/nginx-obs-automatic-low-bitrate-switching)** — Auto scene switching

## License

MIT — see [LICENSE](LICENSE) for details.

SRTLA is licensed under AGPL-3.0. libSRT is licensed under MPL-2.0. See each project's license for their terms.

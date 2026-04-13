#!/bin/bash
###############################################################################
#  SRTLA Relay Kit — One-command installer
#  SRT Live Server (b3ck edit) + SRTLA receiver (BELABOX)
#  For: Ubuntu 22.04 / Oracle Cloud Free Tier / any VPS
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║         SRTLA Relay Kit — Installer v1.0              ║"
echo "║   SRT Live Server + SRTLA bonding for IRL streaming   ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Check root ──────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Run as root: sudo bash install.sh${NC}"
  exit 1
fi

# ── Config ──────────────────────────────────────────────────
SLS_PORT=${SLS_PORT:-30000}
SRTLA_PORT=${SRTLA_PORT:-30001}
HTTP_PORT=${HTTP_PORT:-8181}
INSTALL_DIR="/opt/srtla-relay"
SLS_CONF="/etc/sls/sls.conf"
SLS_USER="srt"

echo -e "${YELLOW}Ports:${NC}"
echo "  SRT  (publish/play): ${SLS_PORT}/udp"
echo "  SRTLA (bonding):     ${SRTLA_PORT}/udp"
echo "  HTTP  (stats):       ${HTTP_PORT}/tcp"
echo ""

# ── Step 1: Dependencies ───────────────────────────────────
echo -e "${GREEN}[1/7] Installing dependencies...${NC}"
apt update -qq
apt install -y -qq build-essential cmake git tcl openssl libssl-dev zlib1g-dev \
  pkg-config net-tools curl > /dev/null 2>&1
echo "  ✓ Dependencies installed"

# ── Step 2: Swap (for low-RAM VPS like Oracle micro) ───────
echo -e "${GREEN}[2/7] Setting up swap...${NC}"
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile > /dev/null 2>&1
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "  ✓ 2GB swap created"
else
  swapon /swapfile 2>/dev/null || true
  echo "  ✓ Swap already exists"
fi

# ── Step 3: Build libSRT ───────────────────────────────────
echo -e "${GREEN}[3/7] Building libSRT (Haivision)...${NC}"
cd /tmp
if [ ! -d "srt" ]; then
  git clone https://github.com/Haivision/srt.git 2>/dev/null
fi
cd srt
git checkout master 2>/dev/null || true
./configure > /dev/null 2>&1
make -j$(nproc) > /dev/null 2>&1
make install > /dev/null 2>&1
ldconfig
echo "  ✓ libSRT installed"

# ── Step 4: Build SLS (b3ck edit) ──────────────────────────
echo -e "${GREEN}[4/7] Building SRT Live Server (b3ck edit)...${NC}"
cd /tmp
[ -d "sls-b3ck-edit" ] && rm -rf sls-b3ck-edit

if [ -d "${INSTALL_DIR}/src/sls-b3ck-edit-master" ]; then
  cp -r ${INSTALL_DIR}/src/sls-b3ck-edit-master sls-b3ck-edit
elif [ -d "${INSTALL_DIR}/src/sls-b3ck-edit" ]; then
  cp -r ${INSTALL_DIR}/src/sls-b3ck-edit sls-b3ck-edit
else
  git clone https://github.com/b3ck/sls-b3ck-edit.git 2>/dev/null || {
    echo -e "${RED}Failed to fetch sls-b3ck-edit${NC}"; exit 1
  }
fi

cd sls-b3ck-edit

sed -i 's|INC_PATH = -I./ -I../ -I./slscore -I./include|INC_PATH = -I./ -I../ -I./slscore -I./include -I/usr/local/include -I/usr/local/include/srt|' Makefile
sed -i 's|LIB_PATH =  -L ./lib|LIB_PATH = -L./lib -L/usr/local/lib -L/usr/local/lib64|' Makefile

mkdir -p obj bin logs
make clean > /dev/null 2>&1 || true
make -j$(nproc) > /dev/null 2>&1

mkdir -p ${INSTALL_DIR}/bin
cp bin/sls ${INSTALL_DIR}/bin/sls
cp bin/slc ${INSTALL_DIR}/bin/slc 2>/dev/null || true
chmod +x ${INSTALL_DIR}/bin/*
echo "  ✓ SLS compiled"

# ── Step 5: Build SRTLA ───────────────────────────────────
echo -e "${GREEN}[5/7] Building SRTLA receiver (BELABOX)...${NC}"
cd /tmp
[ -d "srtla" ] && rm -rf srtla

if [ -d "${INSTALL_DIR}/src/srtla-main" ]; then
  cp -r ${INSTALL_DIR}/src/srtla-main srtla
elif [ -d "${INSTALL_DIR}/src/srtla" ]; then
  cp -r ${INSTALL_DIR}/src/srtla srtla
else
  git clone https://github.com/BELABOX/srtla.git 2>/dev/null || {
    echo -e "${RED}Failed to fetch SRTLA${NC}"; exit 1
  }
fi

cd srtla
sed -i 's/VERSION=$(shell git rev-parse --short HEAD)/VERSION=local/' Makefile 2>/dev/null || true
make clean > /dev/null 2>&1 || true
make -j$(nproc) > /dev/null 2>&1
cp srtla_rec ${INSTALL_DIR}/bin/srtla_rec
chmod +x ${INSTALL_DIR}/bin/srtla_rec
echo "  ✓ SRTLA compiled"

# ── Step 6: Configuration ─────────────────────────────────
echo -e "${GREEN}[6/7] Writing configuration...${NC}"
mkdir -p /etc/sls
mkdir -p ${INSTALL_DIR}/logs

cat > ${SLS_CONF} << SRTCONF
srt {
    worker_threads  1;
    worker_connections 300;

    http_port ${HTTP_PORT};
    cors_header *;

    log_file ${INSTALL_DIR}/logs/sls.log;
    log_level info;

    record_hls_path_prefix /tmp/mov/sls;

    server {
        listen ${SLS_PORT};
        latency 1000;

        domain_player play;
        domain_publisher publish;

        default_sid publish/live/feed1;

        backlog 100;
        idle_streams_timeout 10;

        app {
            app_player live;
            app_publisher live;

            record_hls off;
            record_hls_segment_duration 10;
        }
    }
}
SRTCONF

echo "  ✓ Config saved: ${SLS_CONF}"

# ── System user ────────────────────────────────────────────
id "${SLS_USER}" &>/dev/null || useradd -r -s /bin/false ${SLS_USER}
chown -R ${SLS_USER}:${SLS_USER} ${INSTALL_DIR}/logs 2>/dev/null || true

# ── Step 7: Systemd services ──────────────────────────────
echo -e "${GREEN}[7/7] Creating systemd services...${NC}"

cat > /etc/systemd/system/sls.service << EOF
[Unit]
Description=SRT Live Server (b3ck edit)
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/bin/sls -c ${SLS_CONF}
WorkingDirectory=${INSTALL_DIR}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
Environment="LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64"

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/srtla.service << EOF
[Unit]
Description=SRTLA Receiver (BELABOX bonding proxy)
After=network.target sls.service
Requires=sls.service

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/bin/srtla_rec ${SRTLA_PORT} 127.0.0.1 ${SLS_PORT}
Restart=on-failure
RestartSec=3
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo "  ✓ Services created"

# ── Firewall (iptables) ───────────────────────────────────
echo ""
echo -e "${YELLOW}Configuring firewall...${NC}"

iptables -C INPUT -p udp --dport ${SLS_PORT} -j ACCEPT 2>/dev/null || \
  iptables -I INPUT 1 -p udp --dport ${SLS_PORT} -j ACCEPT

iptables -C INPUT -p udp --dport ${SRTLA_PORT} -j ACCEPT 2>/dev/null || \
  iptables -I INPUT 1 -p udp --dport ${SRTLA_PORT} -j ACCEPT

iptables -C INPUT -p tcp --dport ${HTTP_PORT} -j ACCEPT 2>/dev/null || \
  iptables -I INPUT 1 -p tcp --dport ${HTTP_PORT} -j ACCEPT

if command -v netfilter-persistent &> /dev/null; then
  netfilter-persistent save 2>/dev/null || true
else
  apt install -y -qq iptables-persistent > /dev/null 2>&1 || true
  iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi
echo "  ✓ Firewall configured"

# ── Start ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}Starting services...${NC}"
systemctl enable sls.service > /dev/null 2>&1
systemctl enable srtla.service > /dev/null 2>&1
systemctl start sls.service
sleep 2
systemctl start srtla.service

PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "YOUR_IP")

echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║              INSTALLATION COMPLETE ✓                  ║${NC}"
echo -e "${CYAN}${BOLD}╠═══════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}${BOLD}║                                                       ║${NC}"
echo -e "${CYAN}${BOLD}║${NC}  ${YELLOW}PUBLISH (Moblin / Belabox / Larix):${NC}                  ${CYAN}${BOLD}║${NC}"
echo -e "${CYAN}${BOLD}║${NC}  SRT:   srt://${PUBLIC_IP}:${SLS_PORT}?streamid=publish/live/STREAM"
echo -e "${CYAN}${BOLD}║${NC}  SRTLA: srtla://${PUBLIC_IP}:${SRTLA_PORT}?streamid=publish/live/STREAM"
echo -e "${CYAN}${BOLD}║${NC}                                                       ${CYAN}${BOLD}║${NC}"
echo -e "${CYAN}${BOLD}║${NC}  ${YELLOW}PLAY (OBS / VLC):${NC}                                    ${CYAN}${BOLD}║${NC}"
echo -e "${CYAN}${BOLD}║${NC}  srt://${PUBLIC_IP}:${SLS_PORT}?streamid=play/live/STREAM"
echo -e "${CYAN}${BOLD}║${NC}                                                       ${CYAN}${BOLD}║${NC}"
echo -e "${CYAN}${BOLD}║${NC}  ${YELLOW}STATS:${NC} http://${PUBLIC_IP}:${HTTP_PORT}/stats"
echo -e "${CYAN}${BOLD}║${NC}                                                       ${CYAN}${BOLD}║${NC}"
echo -e "${CYAN}${BOLD}║${NC}  STREAM = any name (feed1, mycam, stream123...)       ${CYAN}${BOLD}║${NC}"
echo -e "${CYAN}${BOLD}║${NC}  Publish and Play must use the same STREAM name       ${CYAN}${BOLD}║${NC}"
echo -e "${CYAN}${BOLD}║${NC}                                                       ${CYAN}${BOLD}║${NC}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
systemctl is-active --quiet sls.service && echo -e "  SLS:   ${GREEN}RUNNING ✓${NC}" || echo -e "  SLS:   ${RED}STOPPED ✗${NC}"
systemctl is-active --quiet srtla.service && echo -e "  SRTLA: ${GREEN}RUNNING ✓${NC}" || echo -e "  SRTLA: ${RED}STOPPED ✗${NC}"
echo ""
echo -e "  Logs:    ${CYAN}sudo journalctl -u sls -u srtla -f${NC}"
echo -e "  Restart: ${CYAN}sudo systemctl restart sls srtla${NC}"
echo -e "  Status:  ${CYAN}sudo bash /opt/srtla-relay/status.sh${NC}"
echo ""

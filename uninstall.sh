#!/bin/bash
# SRTLA Relay Kit — Uninstaller
set -e
echo "Stopping services..."
sudo systemctl stop sls srtla 2>/dev/null || true
sudo systemctl disable sls srtla 2>/dev/null || true
echo "Removing files..."
sudo rm -f /etc/systemd/system/sls.service
sudo rm -f /etc/systemd/system/srtla.service
sudo rm -rf /etc/sls
sudo rm -rf /opt/srtla-relay
sudo systemctl daemon-reload
echo "Removing firewall rules..."
sudo iptables -D INPUT -p udp --dport 30000 -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -p udp --dport 30001 -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -p tcp --dport 8181 -j ACCEPT 2>/dev/null || true
echo "✓ Uninstalled. libSRT remains in /usr/local/lib."

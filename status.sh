#!/bin/bash
# SRTLA Relay Kit — Status
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "?.?.?.?")

echo -e "${CYAN}══════ SRTLA Relay Kit — Status ══════${NC}"
echo ""

systemctl is-active --quiet sls.service && \
  echo -e "  SLS:   ${GREEN}RUNNING ✓${NC}" || echo -e "  SLS:   ${RED}STOPPED ✗${NC}"
systemctl is-active --quiet srtla.service && \
  echo -e "  SRTLA: ${GREEN}RUNNING ✓${NC}" || echo -e "  SRTLA: ${RED}STOPPED ✗${NC}"

echo ""
echo "Open ports:"
ss -ulnp 2>/dev/null | grep -E "30000|30001" | awk '{print "  " $5}'
ss -tlnp 2>/dev/null | grep "8181" | awk '{print "  " $4}'

echo ""
echo "Active streams:"
STATS=$(curl -s http://localhost:8181/stats 2>/dev/null)
if [ -n "$STATS" ] && [ "$STATS" != "" ]; then
  echo "$STATS" | python3 -m json.tool 2>/dev/null || echo "  (no data)"
else
  echo "  (no active streams)"
fi

echo ""
echo -e "${CYAN}Publish:${NC} srtla://${PUBLIC_IP}:30001?streamid=publish/live/STREAM"
echo -e "${CYAN}Play:${NC}    srt://${PUBLIC_IP}:30000?streamid=play/live/STREAM"
echo -e "${CYAN}Stats:${NC}   http://${PUBLIC_IP}:8181/stats"

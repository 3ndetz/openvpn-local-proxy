#!/bin/bash
set -euo pipefail
repo=$1
profile=$2
credentials=$3
port=$4
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y openvpn iptables socat python3
mkdir -p /opt/openvpn-local-proxy /etc/openvpn-local-proxy
cp "$repo/run.sh" "$repo/proxy.py" /opt/openvpn-local-proxy/
cp "$repo/openvpn-local-proxy.service" /etc/systemd/system/
python3 - "$profile" "$credentials" "$port" <<'PY'
import pathlib,shlex,sys
s='PROFILE='+shlex.quote(sys.argv[1])+'\nCREDS='+shlex.quote(sys.argv[2])+'\nPORT='+shlex.quote(sys.argv[3])+'\n'
p=pathlib.Path('/etc/openvpn-local-proxy/settings'); p.write_text(s); p.chmod(0o600)
PY
systemctl daemon-reload
systemctl enable --now openvpn-local-proxy.service

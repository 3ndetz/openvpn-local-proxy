#!/bin/bash
set -euo pipefail
source /etc/openvpn-local-proxy/settings
NS=localovpn
NET=10.249.208
DIR=/run/openvpn-local-proxy
mkdir -p "$DIR" /etc/netns/$NS
chmod 700 "$DIR"
cleanup() {
  kill "${RELAY_PID:-}" "${PROXY_PID:-}" "${VPN_PID:-}" 2>/dev/null || true
  iptables -D FORWARD -i ovpnh -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -o ovpnh -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
  iptables -t nat -D POSTROUTING -s "$NET.0/30" ! -o ovpnh -j MASQUERADE 2>/dev/null || true
  ip link del ovpnh 2>/dev/null || true
  ip netns del "$NS" 2>/dev/null || true
  rm -f "$DIR/auth" "$DIR/keypass"
}
cleanup
trap cleanup EXIT
python3 - "$CREDS" "$DIR" <<'PY'
import pathlib,sys
values={}
for line in pathlib.Path(sys.argv[1]).read_text(encoding='utf-8-sig').splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k,v=line.split('=',1); values[k.strip().lower()]=v.strip().strip('"\'')
if not values.get('login') or not values.get('password'):
    raise SystemExit('Credentials must include login and password')
pathlib.Path(sys.argv[2]+'/auth').write_text(values['login']+'\n'+values['password']+'\n')
pathlib.Path(sys.argv[2]+'/keypass').write_text(values.get('private_key','')+'\n')
PY
chmod 600 "$DIR/auth" "$DIR/keypass"
ip netns add "$NS"
ip link add ovpnh type veth peer name ovpnn
ip link set ovpnn netns "$NS"
ip addr add "$NET.1/30" dev ovpnh
ip link set ovpnh up
ip -n "$NS" link set lo up
ip -n "$NS" addr add "$NET.2/30" dev ovpnn
ip -n "$NS" link set ovpnn up
ip -n "$NS" route add default via "$NET.1"
printf 'nameserver 1.1.1.1\n' > /etc/netns/$NS/resolv.conf
sysctl -w net.ipv4.ip_forward=1 >/dev/null
iptables -t nat -A POSTROUTING -s "$NET.0/30" ! -o ovpnh -j MASQUERADE
iptables -I FORWARD 1 -i ovpnh -j ACCEPT
iptables -I FORWARD 1 -o ovpnh -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip netns exec "$NS" openvpn --config "$PROFILE" --auth-user-pass "$DIR/auth" --askpass "$DIR/keypass" --redirect-gateway def1 --script-security 2 > "$DIR/vpn.log" 2>&1 &
VPN_PID=$!
# The profile configures the tunnel normally; retain OpenVPN's route handling.
for i in $(seq 1 90); do
  kill -0 "$VPN_PID" 2>/dev/null || { cat "$DIR/vpn.log"; exit 1; }
  grep -q 'Initialization Sequence Completed' "$DIR/vpn.log" && break
  sleep 1
done
grep -q 'Initialization Sequence Completed' "$DIR/vpn.log" || exit 1
ip -n "$NS" link set tun0 mtu 900
ip netns exec "$NS" iptables -A OUTPUT -o lo -j ACCEPT
ip netns exec "$NS" iptables -A OUTPUT -o tun+ -j ACCEPT
ip netns exec "$NS" iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip netns exec "$NS" iptables -A OUTPUT -j REJECT
ip netns exec "$NS" python3 /opt/openvpn-local-proxy/proxy.py & PROXY_PID=$!
socat "TCP-LISTEN:$PORT,bind=0.0.0.0,reuseaddr,fork" "TCP:$NET.2:2079" & RELAY_PID=$!
while kill -0 "$VPN_PID" 2>/dev/null && kill -0 "$PROXY_PID" 2>/dev/null && kill -0 "$RELAY_PID" 2>/dev/null; do sleep 5; done
exit 1


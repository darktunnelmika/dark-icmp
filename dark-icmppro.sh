#!/usr/bin/env bash
# ==============================================================================
#  DARK VPN  ·  ICMP PRO
#  Tunnel manager for pingtunnel (github.com/esrrhs/pingtunnel)
#  Support: @mikakhadm
#
#  ROLES:
#    KHAREJ = pingtunnel server (public ICMP endpoint, panel/service lives here)
#    IRAN   = pingtunnel client (exposes local user ports through ICMP)
#
#  DARKVPN-ICMPPRO-SCRIPT
# ==============================================================================

SCRIPT_VER="2.8.0"
DEV_ID="@mikakhadm"
GH_REPO="esrrhs/pingtunnel"
BASE_DIR="/etc/dark-icmppro"
TUN_DIR="$BASE_DIR/tunnels"
LOCAL_CORE_DIR="/root/pingtunnel"
BIN_PATH="/usr/local/bin/pingtunnel"
RUNNER="/usr/local/bin/darkicmp-runner"
FW_HELPER="/usr/local/bin/darkicmp-fw"
UNIT_FILE="/etc/systemd/system/darkicmp@.service"
RS_UNIT="/etc/systemd/system/darkicmp-restart@.service"
RS_TIMER="/etc/systemd/system/darkicmp-restart@.timer"
CORE_VER_FILE="$BASE_DIR/core.version"
UPDATE_URL_FILE="$BASE_DIR/update.url"
SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")"

DEFAULT_ENCRYPT="aes128"
DEFAULT_TIMEOUT="60"
DEFAULT_TCP_BS="1048576"
DEFAULT_TCP_MW="20000"
DEFAULT_TCP_RST="400"
DEFAULT_TCP_GZ="0"
DEFAULT_RESTART="off"
DEFAULT_BIND="0.0.0.0"
DEFAULT_PROFILE="balanced"

# ================================================================== UI ======
R=$'\e[38;5;203m'; G=$'\e[38;5;114m'; Y=$'\e[38;5;221m'
C=$'\e[38;5;81m';  M=$'\e[38;5;177m'; W=$'\e[1;97m'
D=$'\e[38;5;244m'; N=$'\e[0m';        BD=$'\e[1m'
L1=$'\e[38;5;33m'; L2=$'\e[38;5;39m'; L3=$'\e[38;5;45m'
L4=$'\e[38;5;51m'; L5=$'\e[38;5;87m'; L6=$'\e[38;5;123m'
BG_OK=$'\e[48;5;22m'; BG_ERR=$'\e[48;5;52m'; BG_WARN=$'\e[48;5;58m'
UIW=62

shopt -s extglob 2>/dev/null
if ! locale charmap 2>/dev/null | grep -qi 'utf-\?8'; then
  for _L in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if locale -a 2>/dev/null | grep -qix "${_L//./\\.}"; then export LC_ALL="$_L"; break; fi
  done
fi
_probe='é'; [ ${#_probe} -eq 1 ] && UTF_OK=1 || UTF_OK=0

vislen() {
  local s="${1//$'\e['*([0-9;])m/}"
  if [ "$UTF_OK" = 1 ]; then printf '%s' "${#s}"; return; fi
  local b c
  b="$(LC_ALL=C; printf '%s' "$s" | wc -c)"
  c="$(printf '%s' "$s" | LC_ALL=C grep -o $'[\x80-\xbf]' 2>/dev/null | wc -l)"
  printf '%s' $(( b - c ))
}
rep() { local ch="$1" n="$2"; [ "${n:-0}" -gt 0 ] 2>/dev/null || return 0; printf "${ch}%.0s" $(seq 1 "$n"); }
top()   { printf '  %s╭%s╮%s\n' "$C" "$(rep '─' $((UIW+2)))" "$N"; }
mid()   { printf '  %s├%s┤%s\n' "$C" "$(rep '─' $((UIW+2)))" "$N"; }
bot()   { printf '  %s╰%s╯%s\n' "$C" "$(rep '─' $((UIW+2)))" "$N"; }
row()   { local t="$1" l p; l=$(vislen "$t"); p=$((UIW-l)); ((p<0))&&p=0; printf '  %s│%s %s%*s %s│%s\n' "$C" "$N" "$t" "$p" "" "$C" "$N"; }
blank() { row ""; }
item()  { row "$(printf '%s%s%s  %s%-24s%s %s%s%s' "$Y" "[$1]" "$N" "$W" "$2" "$N" "$D" "${3:-}" "$N")"; }
kv()    { row "$(printf '%s%-13s%s %s' "$D" "$1" "$N" "$2")"; }
sect()  { row "$(printf '%s%s%s' "$M$BD" "$1" "$N")"; }
badge() { printf '%s %s %s' "$2$BD" "$1" "$N"; }
ok()    { printf '  %s+%s %s\n' "$G" "$N" "$*"; }
bad()   { printf '  %sx%s %s\n' "$R" "$N" "$*"; }
warn()  { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
info()  { printf '  %s>%s %s\n' "$C" "$N" "$*"; }
dim()   { printf '    %s%s%s\n' "$D" "$*" "$N"; }
dot()   { case "$1" in active) printf '%s*%s' "$G" "$N" ;; failed) printf '%s*%s' "$R" "$N" ;; *) printf '%s*%s' "$D" "$N" ;; esac; }

ask() {
  local p="$1" d="${2:-}" v
  if [ -n "$d" ]; then read -r -p "$(printf '  %s>%s %s %s[%s]%s: ' "$C" "$N" "$p" "$D" "$d" "$N")" v
  else read -r -p "$(printf '  %s>%s %s: ' "$C" "$N" "$p")" v; fi
  ANS="${v:-$d}"
}
yesno() {
  local p="$1" d="$2" v
  read -r -p "$(printf '  %s>%s %s %s[%s]%s: ' "$C" "$N" "$p" "$D" "$([ "$d" = y ] && echo 'Y/n' || echo 'y/N')" "$N")" v
  v="${v:-$d}"; [[ "$v" =~ ^[Yy]$ ]]
}
getkey() { local k; printf '  %s>%s Select: ' "$C" "$N"; read -rsn1 k; [ -z "$k" ] && k="_"; printf '%s\n\n' "$k"; KEYSEL="$k"; }
pause()  { printf '\n  %spress any key%s' "$D" "$N"; read -rsn1 _; echo; }

human_bytes() {
  local b="${1:-0}"
  if   [ "$b" -ge 1099511627776 ] 2>/dev/null; then printf '%d.%01dT' $((b/1099511627776)) $(((b%1099511627776)*10/1099511627776))
  elif [ "$b" -ge 1073741824 ] 2>/dev/null; then printf '%d.%01dG' $((b/1073741824)) $(((b%1073741824)*10/1073741824))
  elif [ "$b" -ge 1048576 ] 2>/dev/null; then printf '%d.%01dM' $((b/1048576)) $(((b%1048576)*10/1048576))
  elif [ "$b" -ge 1024 ] 2>/dev/null; then printf '%dK' $((b/1024))
  else printf '%sB' "$b"; fi
}

core_badge() { if [ -x "$BIN_PATH" ]; then badge "READY" "$BG_OK$W"; else badge "NO CORE" "$BG_ERR$W"; fi; }
core_version_full() { [ -s "$CORE_VER_FILE" ] && cat "$CORE_VER_FILE" || { [ -x "$BIN_PATH" ] && echo installed || echo 'not installed'; }; }
core_version_short() {
  local v; v="$(core_version_full)"
  if [[ "$v" == master-* ]] && [ "${#v}" -gt 15 ]; then printf '%s' "${v:0:15}"
  elif [ "${#v}" -gt 18 ]; then printf '%s' "${v:0:18}"
  else printf '%s' "$v"; fi
}
header() {
  clear
  top
  row "$(printf '%s██████╗  %s█████╗ %s██████╗ %s██╗  ██╗%s' "$L1" "$L2" "$L3" "$L4" "$N")"
  row "$(printf '%s██╔══██╗%s██╔══██╗%s██╔══██╗%s██║ ██╔╝%s' "$L1" "$L2" "$L3" "$L4" "$N")"
  row "$(printf '%s██║  ██║%s███████║%s██████╔╝%s█████╔╝ %s' "$L2" "$L3" "$L4" "$L5" "$N")"
  row "$(printf '%s██║  ██║%s██╔══██║%s██╔══██╗%s██╔═██╗ %s' "$L2" "$L3" "$L4" "$L5" "$N")"
  row "$(printf '%s██████╔╝%s██║  ██║%s██║  ██║%s██║  ██╗%s' "$L3" "$L4" "$L5" "$L6" "$N")"
  row "$(printf '%s╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝%s' "$D" "$N")"
  row "$(printf '%sI%s C%s M%s P%s   P R O%s   %sTCP/UDP over ICMP%s' "$L2" "$L3" "$L4" "$L5" "$W$BD" "$N" "$D" "$N")"
  mid
  row "$(printf '%s  %score%s %s%s%s   %sscript v%s%s   %s%s%s' "$(core_badge)" "$D" "$N" "$W" "$(core_version_short)" "$N" "$D" "$SCRIPT_VER" "$N" "$M" "$DEV_ID" "$N")"
  bot
  [ -n "${1:-}" ] && { echo; printf '  %s>%s %s%s%s\n' "$L4" "$N" "$W$BD" "$1" "$N"; }
  echo
}

# ============================================================== HELPERS ====
need_root() { [ "$(id -u)" -eq 0 ] || { bad "run as root"; exit 1; }; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
valid_name() { [[ "$1" =~ ^[a-zA-Z0-9_-]{1,24}$ ]]; }
valid_ip4()  { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
valid_bind() { valid_ip4 "$1"; }
valid_host() { valid_ip4 "$1" || [[ "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; }
valid_auth_key() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 0 ] && [ "$1" -le 2147483647 ]; }
valid_encrypt() { case "$1" in none|aes128|aes256|chacha20) return 0;; *) return 1;; esac; }
valid_restart() { case "$1" in off|1h|3h|6h|12h|24h) return 0;; *) return 1;; esac; }
valid_profile() { case "$1" in stable|balanced|lowping|turbo|custom) return 0;; *) return 1;; esac; }
b64enc() { base64 -w0 2>/dev/null || base64 | tr -d '\n'; }
b64dec() { base64 -d 2>/dev/null; }
q() { printf '%q' "$1"; }

pkg_mgr() {
  command -v apt-get >/dev/null 2>&1 && { echo apt; return; }
  command -v dnf >/dev/null 2>&1 && { echo dnf; return; }
  command -v yum >/dev/null 2>&1 && { echo yum; return; }
  command -v apk >/dev/null 2>&1 && { echo apk; return; }
  echo none
}
install_deps() {
  local need=0 c
  for c in curl unzip ip ss awk sed grep openssl ping iptables; do command -v "$c" >/dev/null 2>&1 || need=1; done
  [ "$need" -eq 0 ] && return 0
  info "installing dependencies"
  case "$(pkg_mgr)" in
    apt) apt-get update -qq >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl unzip iproute2 iputils-ping iptables openssl ca-certificates procps lsof >/dev/null 2>&1 ;;
    dnf) dnf install -y curl unzip iproute iputils iptables openssl ca-certificates procps-ng lsof >/dev/null 2>&1 ;;
    yum) yum install -y curl unzip iproute iputils iptables openssl ca-certificates procps-ng lsof >/dev/null 2>&1 ;;
    apk) apk add --no-cache bash curl unzip iproute2 iputils iptables openssl ca-certificates procps lsof >/dev/null 2>&1 ;;
    *) warn "unknown package manager - install curl unzip iproute ping iptables openssl manually" ;;
  esac
}
arch_tag() {
  case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; armv7l|armhf) echo arm;; i386|i686) echo 386;; *) echo unsupported;; esac
}
gen_auth_key() {
  local n
  n="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' ')"
  [[ "$n" =~ ^[0-9]+$ ]] || n="$(date +%s)"
  echo $(( n % 2147483646 + 1 ))
}
gen_enc_key() { openssl rand -base64 48 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 32; }
# The address users actually reach is the one configured on this box, not
# whatever an outbound lookup reports. On an Iranian server the lookup is
# often filtered, and the old fallback (hostname -I) returns whichever address
# happens to be first - frequently a private one.
local_ipv4s() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show scope global 2>/dev/null \
      | awk '{split($4,a,"/"); print $2" "a[1]}' | grep -v '^lo '
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | awk '/^[a-z0-9]/{d=$1; sub(":","",d)} /inet /{print d" "$2}' | grep -v '^lo '
  else
    hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | awk '{print "host "$1}'
  fi
}
primary_ipv4() {
  local dev addr
  if command -v ip >/dev/null 2>&1; then
    dev="$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')"
    if [ -n "$dev" ]; then
      addr="$(ip -4 -o addr show dev "$dev" scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}')"
      [ -n "$addr" ] && { echo "$addr"; return; }
    fi
  fi
  local_ipv4s | awk '{print $2; exit}'
}
ip_is_local() { local_ipv4s | awk -v t="$1" '$2==t{f=1} END{exit !f}'; }

# Returns "<address> <source>" so the caller can tell the operator where it
# came from instead of silently presenting a guess as fact.
detect_server_addr() {
  local pub loc
  loc="$(primary_ipv4)"
  pub="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null | tr -d '[:space:]')"
  valid_ip4 "$pub" || pub="$(curl -fsS4 --max-time 5 https://ipv4.icanhazip.com 2>/dev/null | tr -d '[:space:]')"
  if valid_ip4 "$loc"; then
    if valid_ip4 "$pub" && [ "$pub" != "$loc" ] && ! ip_is_local "$pub"; then
      # outbound traffic leaves via a different address than the one bound
      # here; users almost always reach the bound one, so lead with it
      echo "$loc nat:$pub"
    else
      echo "$loc interface"
    fi
  elif valid_ip4 "$pub"; then
    echo "$pub outbound"
  else
    echo " none"
  fi
}

public_ip() {
  local ip u
  for u in https://api.ipify.org https://ifconfig.me/ip https://ipv4.icanhazip.com; do
    ip="$(curl -fsS4 --max-time 6 "$u" 2>/dev/null | tr -d '[:space:]')"
    valid_ip4 "$ip" && { echo "$ip"; return; }
  done
  hostname -I 2>/dev/null | awk '{print $1}'
}
core_supports_encrypt() { [ -x "$BIN_PATH" ] && "$BIN_PATH" -h 2>&1 | grep -q -- '-encrypt'; }

# =========================================================== CORE INSTALL ==
gh_latest_json() { curl -fsSL --max-time 20 "https://api.github.com/repos/$GH_REPO/releases/latest" 2>/dev/null; }
gh_latest_tag() { gh_latest_json | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'; }
gh_asset_url() {
  local arch="$1" json urls pick
  json="$(gh_latest_json)"; [ -n "$json" ] || return 1
  urls="$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' <<<"$json" | sed -E 's/.*"(https[^"]+)"$/\1/')"
  pick="$(grep -Ei "/pingtunnel_linux_${arch}\.zip$" <<<"$urls" | head -n1)"
  if [ -z "$pick" ] && [ "$arch" = amd64 ]; then pick="$(grep -Ei '/pingtunnel_linux64\.zip$' <<<"$urls" | head -n1)"; fi
  [ -z "$pick" ] && pick="$(grep -Ei "/pingtunnel.*linux.*${arch}.*\.zip$" <<<"$urls" | grep -vi 'pack\.zip' | head -n1)"
  printf '%s\n' "$pick"
}
place_core() {
  local src="$1" tmp bin had=0
  tmp="$(mktemp -d)"
  case "$src" in
    *.zip) unzip -oq "$src" -d "$tmp" 2>/dev/null || { rm -rf "$tmp"; bad "extract failed"; return 1; } ;;
    *) cp "$src" "$tmp/pingtunnel" ;;
  esac
  bin="$(find "$tmp" -type f -name 'pingtunnel' 2>/dev/null | head -n1)"
  [ -z "$bin" ] && bin="$(find "$tmp" -type f -iname 'pingtunnel*' -size +1M 2>/dev/null | head -n1)"
  [ -n "$bin" ] || { rm -rf "$tmp"; bad "no pingtunnel binary in package"; return 1; }
  chmod +x "$bin"
  timeout 5 "$bin" -h >/dev/null 2>&1 || { rm -rf "$tmp"; bad "binary will not run on this server"; return 1; }
  [ -x "$BIN_PATH" ] && { cp -f "$BIN_PATH" "$BIN_PATH.bak"; had=1; }
  install -m 0755 "$bin" "$BIN_PATH"
  if ! timeout 5 "$BIN_PATH" -h >/dev/null 2>&1; then
    bad "verification failed - rolling back"; [ "$had" -eq 1 ] && mv -f "$BIN_PATH.bak" "$BIN_PATH"; rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"; return 0
}
restart_all_prompt() {
  local l n; l="$(tunnel_names)"; [ -z "$l" ] && return
  yesno "restart all tunnels now?" y || return
  while read -r n; do [ -n "$n" ] && systemctl restart "darkicmp@$n" 2>/dev/null && ok "$n" || true; done <<<"$l"
}
screen_core() {
  header "CORE"
  local arch tag url
  arch="$(arch_tag)"; [ "$arch" = unsupported ] && { bad "unsupported cpu: $(uname -m)"; pause; return; }
  mkdir -p "$LOCAL_CORE_DIR"
  top; kv "installed" "$W$(core_version_short)$N"; [ "$(core_version_full)" != "$(core_version_short)" ] && kv "build" "$D${CORE_BUILD_DISPLAY:-$(core_version_full | cut -c1-44)}$N"; kv "arch" "$W linux_$arch$N"; kv "encryption" "$([ -x "$BIN_PATH" ] && core_supports_encrypt && printf '%ssupported%s' "$G" "$N" || printf '%sunknown/old core%s' "$Y" "$N")"; mid
  item 1 "From GitHub" "latest release"; item 2 "From $LOCAL_CORE_DIR" "offline"; item 3 "From custom URL" ""; item 0 "Back" ""; bot; echo; getkey
  case "$KEYSEL" in
    1) info "querying github"; tag="$(gh_latest_tag)"; url="$(gh_asset_url "$arch")"
       [ -n "$url" ] || { bad "matching linux asset not found"; pause; return; }
       dim "release: ${tag:-?}"; dim "asset: ${url##*/}"
       local pkg="/tmp/${url##*/}"
       curl -fL --retry 3 --max-time 240 -o "$pkg" "$url" || { bad "download failed"; pause; return; }
       cp -f "$pkg" "$LOCAL_CORE_DIR/${url##*/}" 2>/dev/null
       if place_core "$pkg"; then echo "${tag:-latest}" > "$CORE_VER_FILE"; ensure_units; ok "installed: $(core_version_short)"; core_supports_encrypt || warn "this build has no -encrypt flag; install a newer master build for encryption"; restart_all_prompt; fi
       rm -f "$pkg" ;;
    2) local files=() f i=1
       while IFS= read -r f; do files+=("$f"); done < <(find "$LOCAL_CORE_DIR" -maxdepth 1 -type f \( -name '*.zip' -o -name 'pingtunnel*' \) 2>/dev/null | sort)
       [ ${#files[@]} -gt 0 ] || { bad "nothing in $LOCAL_CORE_DIR"; pause; return; }
       echo; top; sect "LOCAL FILES"; blank; for f in "${files[@]}"; do row "$(printf '%s[%d]%s %s' "$Y" "$i" "$N" "$(basename "$f")")"; i=$((i+1)); done; bot; echo; getkey
       [[ "$KEYSEL" =~ ^[0-9]+$ ]] && [ "$KEYSEL" -ge 1 ] && [ "$KEYSEL" -le ${#files[@]} ] || return
       if place_core "${files[$((KEYSEL-1))]}"; then echo local > "$CORE_VER_FILE"; ensure_units; ok "installed"; restart_all_prompt; fi ;;
    3) ask "direct url"; [ -n "$ANS" ] || return; local tmp="/tmp/icmp-$(basename "${ANS%%\?*}")"; curl -fL --retry 3 --max-time 240 -o "$tmp" "$ANS" || { bad "download failed"; pause; return; }; if place_core "$tmp"; then echo custom > "$CORE_VER_FILE"; ensure_units; ok "installed"; restart_all_prompt; fi; rm -f "$tmp" ;;
    *) return ;;
  esac
  pause
}

# ================================================================ SYSTEMD ==
ensure_dirs() { mkdir -p "$BASE_DIR" "$TUN_DIR" "$LOCAL_CORE_DIR"; chmod 700 "$BASE_DIR"; }
write_runner() {
  cat > "$RUNNER" <<'RUN'
#!/usr/bin/env bash
set -u
BASE_DIR="/etc/dark-icmppro"
TUN_DIR="$BASE_DIR/tunnels"
BIN="/usr/local/bin/pingtunnel"
name="${1:-}"
dir="$TUN_DIR/$name"
[ -n "$name" ] && [ -f "$dir/meta.conf" ] || { echo "missing tunnel metadata" >&2; exit 2; }
# shellcheck disable=SC1090
source "$dir/meta.conf"
enc_args=()
if [ "${ENCRYPT:-none}" != none ]; then enc_args=(-encrypt "$ENCRYPT" -encrypt-key "$ENC_KEY"); fi
common=(-key "$AUTH_KEY" -icmp_l "${ICMP_LISTEN:-0.0.0.0}" -nolog 1 -noprint 0 -loglevel "${LOGLEVEL:-warn}")
if [ "$ROLE" = server ]; then
  exec "$BIN" -type server "${common[@]}" "${enc_args[@]}" -maxconn "${MAXCONN:-0}" -maxprt "${MAXPRT:-100}" -maxprb "${MAXPRB:-1000}" -conntt "${CONNTT:-1000}"
fi
pids=()
cleanup(){ local p; for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; wait 2>/dev/null || true; }
trap cleanup INT TERM EXIT
while IFS=$'\t' read -r proto lport target; do
  [ -n "${proto:-}" ] && [ -n "${lport:-}" ] && [ -n "${target:-}" ] || continue
  args=("$BIN" -type client -l "${LOCAL_BIND:-0.0.0.0}:$lport" -s "$PEER_IP" -t "$target" -timeout "${TIMEOUT:-60}" "${common[@]}" "${enc_args[@]}" -maxconn "${MAXCONN:-0}")
  if [ "$proto" = tcp ]; then
    args+=( -tcp 1 -tcp_bs "${TCP_BS:-1048576}" -tcp_mw "${TCP_MW:-20000}" -tcp_rst "${TCP_RST:-400}" -tcp_gz "${TCP_GZ:-0}" -tcp_stat "${TCP_STAT:-0}" )
  fi
  "${args[@]}" & pids+=("$!")
done < "$dir/ports.list"
[ ${#pids[@]} -gt 0 ] || { echo "no forward ports configured" >&2; exit 3; }
while :; do
  sleep 2
  for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null || { echo "forward worker $p exited" >&2; exit 1; }; done
done
RUN
  chmod 0755 "$RUNNER"
}
write_fw_helper() {
  cat > "$FW_HELPER" <<'FWR'
#!/usr/bin/env bash
set -u
BASE=/etc/dark-icmppro/tunnels
act="${1:-}"; name="${2:-}"; dir="$BASE/$name"; tag="darkicmp-$name"
command -v iptables >/dev/null 2>&1 || exit 0
clear_chain(){
  local chain="$1" nums n
  nums="$(iptables -w 5 -L "$chain" -n --line-numbers 2>/dev/null | awk -v t="$tag" '$0~t{print $1}' | sort -rn)"
  for n in $nums; do iptables -w 5 -D "$chain" "$n" 2>/dev/null || true; done
}
clear_rules(){ clear_chain INPUT; clear_chain OUTPUT; }
add_rule(){ local chain="$1"; shift; iptables -w 5 -C "$chain" "$@" -m comment --comment "$tag" -j ACCEPT 2>/dev/null || iptables -w 5 -I "$chain" 1 "$@" -m comment --comment "$tag" -j ACCEPT; }
case "$act" in
 clear) clear_rules ;;
 apply)
   [ -f "$dir/meta.conf" ] || exit 1
   # shellcheck disable=SC1090
   source "$dir/meta.conf"; clear_rules
   if [ "$ROLE" = server ]; then
     add_rule INPUT -p icmp --icmp-type echo-request
     add_rule OUTPUT -p icmp --icmp-type echo-reply
     add_rule INPUT -p icmp --icmp-type echo-reply
     add_rule OUTPUT -p icmp --icmp-type echo-request
   else
     while IFS=$'\t' read -r proto p target; do
       [ "$proto" = tcp ] || [ "$proto" = udp ] || continue
       add_rule INPUT -p "$proto" --dport "$p"
       add_rule OUTPUT -p "$proto" --sport "$p"
     done < "$dir/ports.list"
   fi ;;
 *) exit 2 ;;
esac
FWR
  chmod 0755 "$FW_HELPER"
}

ensure_units() {
  write_runner; write_fw_helper
  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=DARK VPN ICMP Pro Tunnel (%i)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStartPre=$FW_HELPER apply %i
ExecStart=$RUNNER %i
ExecStopPost=$FW_HELPER clear %i
Restart=always
RestartSec=4
KillMode=control-group
TimeoutStopSec=8
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=darkicmp-%i

[Install]
WantedBy=multi-user.target
EOF
  cat > "$RS_UNIT" <<EOF
[Unit]
Description=DARK VPN ICMP Pro scheduled restart (%i)
[Service]
Type=oneshot
ExecStart=/bin/systemctl restart darkicmp@%i.service
EOF
  cat > "$RS_TIMER" <<'EOF'
[Unit]
Description=DARK VPN ICMP Pro scheduled restart timer (%i)
[Timer]
OnUnitActiveSec=1h
OnBootSec=1h
AccuracySec=1min
Unit=darkicmp-restart@%i.service
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload 2>/dev/null
}
set_restart_timer() {
  local name="$1" every="$2" dir; dir="/etc/systemd/system/darkicmp-restart@$name.timer.d"
  if [ "$every" = off ]; then systemctl disable --now "darkicmp-restart@$name.timer" >/dev/null 2>&1; rm -rf "$dir"; systemctl daemon-reload 2>/dev/null; return; fi
  mkdir -p "$dir"; printf '[Timer]\nOnUnitActiveSec=\nOnUnitActiveSec=%s\nOnBootSec=\nOnBootSec=%s\n' "$every" "$every" > "$dir/interval.conf"
  systemctl daemon-reload 2>/dev/null; systemctl enable --now "darkicmp-restart@$name.timer" >/dev/null 2>&1
}


# ======================================================= PERFORMANCE PROFILES ==
# These are DARK manager presets built only from pingtunnel's real TCP-mode
# knobs. "balanced" is the upstream/default-style baseline used by this script.
icmp_profile_for_values() {
  if [ "$TCP_BS" = 524288 ] && [ "$TCP_MW" = 10000 ] && [ "$TCP_RST" = 600 ] && [ "$TCP_GZ" = 0 ]; then echo stable
  elif [ "$TCP_BS" = "$DEFAULT_TCP_BS" ] && [ "$TCP_MW" = "$DEFAULT_TCP_MW" ] && [ "$TCP_RST" = "$DEFAULT_TCP_RST" ] && [ "$TCP_GZ" = "$DEFAULT_TCP_GZ" ]; then echo balanced
  elif [ "$TCP_BS" = 524288 ] && [ "$TCP_MW" = 12000 ] && [ "$TCP_RST" = 200 ] && [ "$TCP_GZ" = 0 ]; then echo lowping
  elif [ "$TCP_BS" = 2097152 ] && [ "$TCP_MW" = 40000 ] && [ "$TCP_RST" = 300 ] && [ "$TCP_GZ" = 0 ]; then echo turbo
  else echo custom
  fi
}
apply_icmp_profile() {
  PROFILE="$1"
  case "$PROFILE" in
    stable)   TCP_BS=524288;  TCP_MW=10000; TCP_RST=600; TCP_GZ=0 ;;
    balanced) TCP_BS="$DEFAULT_TCP_BS"; TCP_MW="$DEFAULT_TCP_MW"; TCP_RST="$DEFAULT_TCP_RST"; TCP_GZ="$DEFAULT_TCP_GZ" ;;
    lowping)  TCP_BS=524288;  TCP_MW=12000; TCP_RST=200; TCP_GZ=0 ;;
    turbo)    TCP_BS=2097152; TCP_MW=40000; TCP_RST=300; TCP_GZ=0 ;;
    custom)   : ;;
    *) PROFILE="$DEFAULT_PROFILE"; apply_icmp_profile "$DEFAULT_PROFILE" ;;
  esac
}
pick_icmp_profile() {
  { echo; top; sect "PERFORMANCE PROFILE"; blank
    row "$(printf '%ssets real pingtunnel TCP buffer / window / resend knobs%s' "$D" "$N")"; blank
    item 1 "Stable"   "lossy / filtered paths"
    item 2 "Balanced" "recommended"
    item 3 "Low Ping" "faster retransmit"
    item 4 "Turbo"    "larger window / throughput"
    item 5 "Custom"   "manual TCP tuning"
    bot; echo; } >&2
  local k; printf '  %s>%s Profile [2]: ' "$C" "$N" >&2; read -rsn1 k; printf '%s\n' "$k" >&2
  case "$k" in 1) echo stable;; 3) echo lowping;; 4) echo turbo;; 5) echo custom;; *) echo balanced;; esac
}
prompt_icmp_custom() {
  PROFILE=custom
  ask "buffer bytes" "$TCP_BS"; [[ "$ANS" =~ ^[0-9]+$ ]] && [ "$ANS" -ge 65536 ] && TCP_BS="$ANS"
  ask "max window" "$TCP_MW"; [[ "$ANS" =~ ^[0-9]+$ ]] && [ "$ANS" -ge 1000 ] && [ "$ANS" -le 100000 ] && TCP_MW="$ANS"
  ask "resend ms" "$TCP_RST"; [[ "$ANS" =~ ^[0-9]+$ ]] && [ "$ANS" -ge 50 ] && [ "$ANS" -le 5000 ] && TCP_RST="$ANS"
  ask "compress threshold (0 off)" "$TCP_GZ"; [[ "$ANS" =~ ^[0-9]+$ ]] && TCP_GZ="$ANS"
}

# ================================================================ STORAGE ==
write_meta() {
  local dir="$1"
  {
    printf 'NAME=%q\n' "$NAME"; printf 'ROLE=%q\n' "$ROLE"; printf 'PUB_IP=%q\n' "${PUB_IP:-}"; printf 'PEER_IP=%q\n' "${PEER_IP:-}"
    printf 'AUTH_KEY=%q\n' "$AUTH_KEY"; printf 'ENCRYPT=%q\n' "$ENCRYPT"; printf 'ENC_KEY=%q\n' "$ENC_KEY"
    printf 'TIMEOUT=%q\n' "$TIMEOUT"; printf 'LOCAL_BIND=%q\n' "${LOCAL_BIND:-$DEFAULT_BIND}"; printf 'ICMP_LISTEN=%q\n' "${ICMP_LISTEN:-0.0.0.0}"
    printf 'PROFILE=%q\n' "${PROFILE:-custom}"
    printf 'TCP_BS=%q\n' "$TCP_BS"; printf 'TCP_MW=%q\n' "$TCP_MW"; printf 'TCP_RST=%q\n' "$TCP_RST"; printf 'TCP_GZ=%q\n' "$TCP_GZ"; printf 'TCP_STAT=%q\n' "${TCP_STAT:-0}"
    printf 'MAXCONN=%q\n' "${MAXCONN:-0}"; printf 'MAXPRT=%q\n' "${MAXPRT:-100}"; printf 'MAXPRB=%q\n' "${MAXPRB:-1000}"; printf 'CONNTT=%q\n' "${CONNTT:-1000}"
    printf 'RESTART_EVERY=%q\n' "$RESTART_EVERY"; printf 'LOGLEVEL=%q\n' "${LOGLEVEL:-info}"
  } > "$dir/meta.conf"
  chmod 600 "$dir/meta.conf"
}
load_meta() {
  local name="$1" f="$TUN_DIR/$1/meta.conf"
  [ -f "$f" ] || return 1
  NAME="" ROLE="" PUB_IP="" PEER_IP="" AUTH_KEY="0" ENCRYPT="none" ENC_KEY="" TIMEOUT="$DEFAULT_TIMEOUT" LOCAL_BIND="$DEFAULT_BIND" ICMP_LISTEN="0.0.0.0"
  PROFILE="$DEFAULT_PROFILE" TCP_BS="$DEFAULT_TCP_BS" TCP_MW="$DEFAULT_TCP_MW" TCP_RST="$DEFAULT_TCP_RST" TCP_GZ="$DEFAULT_TCP_GZ" TCP_STAT=0 MAXCONN=0 MAXPRT=100 MAXPRB=1000 CONNTT=1000 RESTART_EVERY=off LOGLEVEL=warn
  # shellcheck disable=SC1090
  source "$f"
  if ! grep -q '^PROFILE=' "$f" 2>/dev/null; then PROFILE="$(icmp_profile_for_values)"; fi
  valid_profile "$PROFILE" || PROFILE="$(icmp_profile_for_values)"
  # "info" floods the journal with a stats line every second; keep it at warn
  # unless the operator explicitly chose debug via the toggle.
  [ "$LOGLEVEL" = info ] && LOGLEVEL=warn
  return 0
}

tunnel_names() { find "$TUN_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort; }
tunnel_count() { tunnel_names | grep -c '[^[:space:]]'; }

# ================================================================= PORTS ===
ports_csv() {
  local dir="$1" out="" proto p target prefix
  [ -f "$dir/ports.list" ] || { echo; return; }
  while IFS=$'\t' read -r proto p target; do
    [ -n "$p" ] || continue; [ "$proto" = udp ] && prefix=u || prefix=t
    out="${out:+$out,}${prefix}${p}>${target}"
  done < "$dir/ports.list"
  echo "$out"
}
pretty_ports() {
  local csv="$1" x out=""; [ -n "$csv" ] || { echo none; return; }
  IFS=',' read -r -a _pc <<<"$csv"
  for x in "${_pc[@]}"; do
    case "$x" in t*) out="$out tcp:${x#t}";; u*) out="$out udp:${x#u}";; esac
  done
  echo "${out# }" | sed 's/>/→/g'
}
expand_ports_csv() {
  local csv="$1" out="$2" x proto rest p target n=0
  : > "$out"; IFS=',' read -r -a _pc <<<"$csv"
  for x in "${_pc[@]}"; do
    case "$x" in t*) proto=tcp; rest="${x#t}";; u*) proto=udp; rest="${x#u}";; *) continue;; esac
    p="${rest%%>*}"; target="${rest#*>}"; [ "$target" = "$rest" ] && target="127.0.0.1:$p"
    valid_port "$p" || continue; [[ "$target" =~ ^[^[:space:]|,]+:[0-9]+$ ]] || continue
    printf '%s\t%s\t%s\n' "$proto" "$p" "$target" >> "$out"; n=$((n+1))
  done; echo "$n"
}
# Is anything already listening on this port?
port_in_use_tcp() {
  command -v ss >/dev/null 2>&1 || return 1
  ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | grep -Eq "[:.]$1$"
}
port_in_use_udp() {
  command -v ss >/dev/null 2>&1 || return 1
  ss -lun 2>/dev/null | awk 'NR>1{print $4}' | grep -Eq "[:.]$1$"
}

port_owner() { # <proto> <bind> <port> <exclude-tunnel>
  local proto="$1" bind="$2" port="$3" skip="${4:-}" other orole obind
  while read -r other; do
    [ -n "$other" ] || continue
    [ "$other" = "$skip" ] && continue
    [ -f "$TUN_DIR/$other/meta.conf" ] || continue
    orole="$(read_meta_field "$TUN_DIR/$other/meta.conf" ROLE)"
    [ "$orole" = client ] || continue
    obind="$(read_meta_field "$TUN_DIR/$other/meta.conf" LOCAL_BIND)"; obind="${obind:-0.0.0.0}"
    bind_overlap "$bind" "$obind" || continue
    awk -F'\t' -v pr="$proto" -v lp="$port" '$1==pr && $2==lp{f=1} END{exit !f}' \
        "$TUN_DIR/$other/ports.list" 2>/dev/null && { echo "used:$other"; return; }
  done <<<"$(tunnel_names)"
  if [ "$proto" = tcp ]; then port_in_use_tcp "$port" && { echo "busy:system"; return; }
  else port_in_use_udp "$port" && { echo "busy:system"; return; }; fi
  echo ""
}

# Renders the map. Returns 1 when at least one IRAN listen port is taken.
render_forward_map() { # <ports.list> <role> <bind> [exclude-tunnel]
  local file="$1" role="$2" bind="${3:-0.0.0.0}" skip="${4:-}"
  local proto port target owner i=1 clash=0 listen st
  top; sect "FORWARD MAP"
  if [ "$role" = server ]; then
    row "$(printf '%stemplate only - this side runs no forwards%s' "$D" "$N")"
    row "$(printf '%sit travels in the Pair Code and IRAN builds the real map%s' "$D" "$N")"
  else
    row "$(printf '%suser -> IRAN listen  ==icmp==>  KHAREJ service%s' "$D" "$N")"
  fi
  blank
  row "$(printf '%s%2s  %-5s %-18s %-18s %-12s%s' "$D" "#" "PROTO" \
        "$([ "$role" = server ] && echo "IRAN WILL LISTEN" || echo "IRAN LISTEN")" \
        "KHAREJ SERVICE" "$([ "$role" = server ] && echo "" || echo "STATUS")" "$N")"
  while IFS=$'\t' read -r proto port target; do
    [ -n "$proto" ] && [ -n "$port" ] || continue
    if [ "$role" = server ]; then listen="(any):$port"; st=""
    else
      listen="$bind:$port"
      owner="$(port_owner "$proto" "$bind" "$port" "$skip")"
      if [ -n "$owner" ]; then st="$R$(printf '%-12s' "${owner:0:12}")$N"; clash=1
      else st="$G$(printf '%-12s' free)$N"; fi
    fi
    row "$(printf '%s%2s%s  %s%-5s%s %-18s %-18s %s' "$Y" "$i" "$N" "$C" "$proto" "$N" \
          "${listen:0:18}" "${target:0:18}" "$st")"
    i=$((i+1))
  done < "$file"
  [ "$i" -eq 1 ] && row "$(printf '%s(no forwards yet)%s' "$D" "$N")"
  bot
  return $clash
}

# Walks only the rows whose IRAN listen port is taken and asks for a free one.
# The KHAREJ service is never touched - that is the part that must not change.
resolve_port_clashes() { # <ports.list> <bind> <tunnel-name>
  local file="$1" bind="$2" name="$3" tmp proto port target owner np
  tmp="$file.tmp"; : > "$tmp"
  echo; top; sect "FREE UP THE IRAN PORTS"
  row "$(printf '%sonly the IRAN listen port changes%s' "$D" "$N")"
  row "$(printf '%sthe KHAREJ service stays exactly as it is%s' "$D" "$N")"
  bot; echo
  while IFS=$'\t' read -r proto port target; do
    [ -n "$proto" ] && [ -n "$port" ] || continue
    owner="$(port_owner "$proto" "$bind" "$port" "$name")"
    if [ -z "$owner" ] && ! awk -F'\t' -v pr="$proto" -v lp="$port" '$1==pr && $2==lp{f=1} END{exit !f}' "$tmp" 2>/dev/null; then
      printf '%s\t%s\t%s\n' "$proto" "$port" "$target" >> "$tmp"; continue
    fi
    while :; do
      [ -n "$owner" ] && warn "${proto^^} $bind:$port taken by $owner"
      ask "new IRAN ${proto^^} port for -> $target" "$port"; np="$ANS"
      valid_port "$np" || { bad "invalid port"; continue; }
      if awk -F'\t' -v pr="$proto" -v lp="$np" '$1==pr && $2==lp{f=1} END{exit !f}' "$tmp" 2>/dev/null; then
        bad "already used by another row in this tunnel"; continue
      fi
      owner="$(port_owner "$proto" "$bind" "$np" "$name")"
      [ -n "$owner" ] && { bad "$np is taken by $owner"; port="$np"; continue; }
      printf '%s\t%s\t%s\n' "$proto" "$np" "$target" >> "$tmp"; break
    done
  done < "$file"
  mv -f "$tmp" "$file"
}

# Asks for the services that live on the KHAREJ box.
read_services_into() { # <ports.list>
  local out="$1" p n=0 want_udp
  : > "$out"
  echo; top; sect "SERVICES ON THIS KHAREJ SERVER"
  row "$(printf '%swhich local services should IRAN publish?%s' "$D" "$N")"
  row "$(printf '%senter the ports your panel already listens on here%s' "$D" "$N")"
  row "$(printf '%sexample:  8000,443%s' "$D" "$N")"
  bot; echo
  while :; do
    ask "service ports (comma separated)"
    n=0; : > "$out"
    IFS=', ' read -r -a _pa <<<"$ANS"
    for p in "${_pa[@]}"; do
      valid_port "$p" || continue
      awk -F'\t' -v lp="$p" '$1=="tcp" && $2==lp{f=1} END{exit !f}' "$out" 2>/dev/null && continue
      printf 'tcp\t%s\t127.0.0.1:%s\n' "$p" "$p" >> "$out"; n=$((n+1))
    done
    [ "$n" -gt 0 ] && break
    bad "enter at least one valid port"
  done
  if yesno "these services also need UDP?" n; then
    for p in "${_pa[@]}"; do
      valid_port "$p" || continue
      awk -F'\t' -v lp="$p" '$1=="udp" && $2==lp{f=1} END{exit !f}' "$out" 2>/dev/null && continue
      printf 'udp\t%s\t127.0.0.1:%s\n' "$p" "$p" >> "$out"
    done
  fi
}

read_meta_field() { # <meta-file> <var>
  local f="$1" k="$2"
  ( set +u; source "$f" 2>/dev/null || exit 1; printf '%s' "${!k-}" )
}

bind_overlap() { # wildcard bind conflicts with every bind on the same port
  [ "$1" = "0.0.0.0" ] || [ "$2" = "0.0.0.0" ] || [ "$1" = "$2" ]
}

pick_local_bind() {
  local addrs=() line i=1
  while read -r line; do [ -n "$line" ] && addrs+=("$line"); done <<<"$(local_ipv4s)"
  { echo; top; sect "LOCAL BIND - IRAN"; blank
    row "$(printf '%sthis is the address that OPENS the forward ports on IRAN%s' "$D" "$N")"
    blank
    item 1 "0.0.0.0" "all IPv4 - recommended"
    item 2 "127.0.0.1" "localhost only"
    if [ "${#addrs[@]}" -gt 0 ]; then
      row "$(printf '%sthis server has:%s' "$D" "$N")"
      for line in "${addrs[@]}"; do
        row "$(printf '   %s%-8s %s%s' "$D" "${line%% *}" "${line##* }" "$N")"
      done
    fi
    item 3 "Custom IPv4" "bind one interface"
    bot; echo; } >&2
  local k v
  printf '  %s>%s Local bind [1]: ' "$C" "$N" >&2; read -rsn1 k; printf '%s\n' "$k" >&2
  case "$k" in
    2) echo 127.0.0.1 ;;
    3) printf '  %s>%s Custom local IPv4: ' "$C" "$N" >&2; read -r v
       if ! valid_bind "$v"; then echo INVALID; return; fi
       if ! ip_is_local "$v"; then
         printf '  %s!%s %s is not configured on this server - binding will fail\n' "$Y" "$N" "$v" >&2
         echo INVALID; return
       fi
       echo "$v" ;;
    *) echo 0.0.0.0 ;;
  esac
}

# =============================================================== PAIR CODE ==
enc_idx() { case "$1" in aes256) echo 2;; chacha20) echo 3;; none) echo 0;; *) echo 1;; esac; }
idx_enc() { case "$1" in 2) echo aes256;; 3) echo chacha20;; 0) echo none;; *) echo aes128;; esac; }
make_pair_code() {
  local dir="$1" p
  p="2|$PUB_IP|$AUTH_KEY|$(enc_idx "$ENCRYPT")|$ENC_KEY|$TIMEOUT|$RESTART_EVERY|${PROFILE:-custom}|$TCP_BS|$TCP_MW|$TCP_RST|$TCP_GZ|$(ports_csv "$dir")"
  printf 'DICMP-%s' "$(printf '%s' "$p" | b64enc)"
}
parse_pair_code() {
  local code="$1" raw ver ei
  code="${code#DICMP-}"; code="$(tr -d '[:space:]' <<<"$code")"; raw="$(printf '%s' "$code" | b64dec)" || return 1
  PC_IP="" PC_AUTH="" PC_ENCRYPT="" PC_ENC_KEY="" PC_TIMEOUT="$DEFAULT_TIMEOUT" PC_RESTART=off PC_PROFILE="$DEFAULT_PROFILE" PC_BS="$DEFAULT_TCP_BS" PC_MW="$DEFAULT_TCP_MW" PC_RST="$DEFAULT_TCP_RST" PC_GZ="$DEFAULT_TCP_GZ" PC_PORTS=""
  if [[ "$raw" == 2\|* ]]; then
    IFS='|' read -r ver PC_IP PC_AUTH ei PC_ENC_KEY PC_TIMEOUT PC_RESTART PC_PROFILE PC_BS PC_MW PC_RST PC_GZ PC_PORTS <<<"$raw"
  elif [[ "$raw" == 1\|* ]]; then
    IFS='|' read -r ver PC_IP PC_AUTH ei PC_ENC_KEY PC_TIMEOUT PC_RESTART PC_BS PC_MW PC_RST PC_GZ PC_PORTS <<<"$raw"
    TCP_BS="$PC_BS"; TCP_MW="$PC_MW"; TCP_RST="$PC_RST"; TCP_GZ="$PC_GZ"; PC_PROFILE="$(icmp_profile_for_values)"
  else return 1
  fi
  PC_ENCRYPT="$(idx_enc "$ei")"; valid_host "$PC_IP" && valid_auth_key "$PC_AUTH" && valid_encrypt "$PC_ENCRYPT" && valid_restart "$PC_RESTART" || return 1
  [[ "$PC_TIMEOUT" =~ ^[0-9]+$ ]] || PC_TIMEOUT="$DEFAULT_TIMEOUT"; [[ "$PC_BS" =~ ^[0-9]+$ ]] || PC_BS="$DEFAULT_TCP_BS"; [[ "$PC_MW" =~ ^[0-9]+$ ]] || PC_MW="$DEFAULT_TCP_MW"; [[ "$PC_RST" =~ ^[0-9]+$ ]] || PC_RST="$DEFAULT_TCP_RST"; [[ "$PC_GZ" =~ ^[0-9]+$ ]] || PC_GZ="$DEFAULT_TCP_GZ"
  valid_profile "$PC_PROFILE" || { TCP_BS="$PC_BS"; TCP_MW="$PC_MW"; TCP_RST="$PC_RST"; TCP_GZ="$PC_GZ"; PC_PROFILE="$(icmp_profile_for_values)"; }
  [ "$PC_ENCRYPT" = none ] || [ -n "$PC_ENC_KEY" ]
}
show_pair_code() {
  local name="$1" code; load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "inspect or delete this tunnel from the manage screen"; pause; return; }; [ "$ROLE" = server ] || { info "pair code is generated on the KHAREJ server"; return; }
  code="$(make_pair_code "$TUN_DIR/$name")"; printf '%s\n' "$code" > "$TUN_DIR/$name/pair.code"; chmod 600 "$TUN_DIR/$name/pair.code"
  echo; top; sect "PAIR CODE"; row "$(printf '%spaste this on the IRAN server%s' "$D" "$N")"; blank; bot; echo; printf '%s%s%s\n' "$W" "$code" "$N"; echo
}

# ======================================================= NOC PAIR CODE N1 ==
# DICMP-N1-<BASE64URL> — generated by DARK NOC Hub, consumed on KHAREJ.
# Carries everything needed to build the server side without user questions.
# Fields (pipe-separated inside the JSON-like flat structure):
#   tunnel_name | pub_ip | auth_key | encrypt_idx | enc_key | timeout
#   | restart | profile | tcp_bs | tcp_mw | tcp_rst | tcp_gz
#   | icmp_listen | pairing_id | created_epoch | ports_csv
#
# Base64URL alphabet (RFC 4648 §5): + → - and / → _ , no padding
# All secrets are validated character-by-character; no eval/source ever.

_b64url_enc() {
  # stdin → stdout, URL-safe base64, no newlines, no padding
  base64 -w0 2>/dev/null | tr '+/' '-_' | tr -d '='
}
_b64url_dec() {
  # stdin → stdout; re-add padding before decoding
  local s; read -r s
  local pad=$(( (4 - ${#s} % 4) % 4 ))
  local p=""; while [ "$pad" -gt 0 ]; do p="${p}="; pad=$((pad-1)); done
  printf '%s%s' "$s" "$p" | tr '-_' '+/' | base64 -d 2>/dev/null
}

# Validate a pairing_id: 16 hex chars, no control chars
_valid_pairing_id() { [[ "$1" =~ ^[0-9a-fA-F]{16}$ ]]; }

# Validate enc_key from N1 code: printable ASCII, no pipe/whitespace, max 128
_valid_enc_key_n1() {
  local k="$1"
  [ "${#k}" -le 128 ] || return 1
  [[ "$k" =~ ^[[:print:]]+$ ]] || return 1
  [[ "$k" == *'|'* ]] && return 1
  return 0
}

# Parse a DICMP-N1-<BASE64URL> code.  Sets NC_* globals; returns 1 on error.
# NEVER uses eval/source. Every field is validated before assignment.
parse_noc_pair_code() {
  local code="$1" raw
  # strip prefix, whitespace
  code="${code#DICMP-N1-}"
  code="$(tr -d '[:space:]' <<<"$code")"
  [ -n "$code" ] || return 1

  # decode
  raw="$(printf '%s' "$code" | _b64url_dec)" || return 1
  [ -n "$raw" ] || return 1

  # must start with N1|
  [[ "$raw" == N1\|* ]] || return 1

  # split on | into positional variables — IFS read, NO eval
  local _ver _name _ip _auth _ei _ekey _timeout _restart _profile \
        _bs _mw _rst _gz _icmp _pid _ts _ports
  IFS='|' read -r _ver _name _ip _auth _ei _ekey _timeout _restart \
                   _profile _bs _mw _rst _gz _icmp _pid _ts _ports \
     <<<"$raw"

  # version gate
  [ "$_ver" = "N1" ] || return 1

  # --- field-by-field validation (untrusted input) ---
  valid_name "$_name"           || { bad "N1: invalid tunnel name '$_name'";    return 1; }
  valid_host "$_ip"             || { bad "N1: invalid KHAREJ IP '$_ip'";        return 1; }
  valid_auth_key "$_auth"       || { bad "N1: invalid auth key";                return 1; }
  [[ "$_ei" =~ ^[0-3]$ ]]      || { bad "N1: invalid encryption index";        return 1; }
  local _enc; _enc="$(idx_enc "$_ei")"
  valid_encrypt "$_enc"         || { bad "N1: unknown encryption '$_enc'";      return 1; }
  if [ "$_enc" != none ]; then
    _valid_enc_key_n1 "$_ekey" || { bad "N1: enc_key contains illegal chars";  return 1; }
    [ -n "$_ekey" ]            || { bad "N1: enc_key missing for $_enc";        return 1; }
  fi
  [[ "$_timeout" =~ ^[0-9]+$ ]] && [ "$_timeout" -ge 5 ] && [ "$_timeout" -le 300 ] \
                                || { bad "N1: timeout out of range";            return 1; }
  valid_restart "$_restart"     || { bad "N1: invalid restart '$_restart'";     return 1; }
  valid_profile "$_profile"     || _profile=balanced
  [[ "$_bs"  =~ ^[0-9]+$ ]]   || { bad "N1: tcp_bs not numeric";              return 1; }
  [[ "$_mw"  =~ ^[0-9]+$ ]]   || { bad "N1: tcp_mw not numeric";              return 1; }
  [[ "$_rst" =~ ^[0-9]+$ ]]   || { bad "N1: tcp_rst not numeric";             return 1; }
  [[ "$_gz"  =~ ^[0-9]+$ ]]   || { bad "N1: tcp_gz not numeric";              return 1; }
  # icmp listen: 0.0.0.0 allowed, or a valid IP
  valid_ip4 "$_icmp" || [ "$_icmp" = "0.0.0.0" ] \
                        || { bad "N1: invalid icmp_listen '$_icmp'";           return 1; }
  _valid_pairing_id "$_pid"     || { bad "N1: invalid pairing_id";             return 1; }
  [[ "$_ts" =~ ^[0-9]+$ ]]    || { bad "N1: invalid timestamp";               return 1; }
  # ports_csv: only safe chars — letters, digits, colon, comma, dot, angle brackets
  [[ "$_ports" =~ ^[a-zA-Z0-9:,\.\<\>]+$ ]] \
                                || { bad "N1: ports_csv contains illegal chars"; return 1; }
  [ -n "$_ports" ]             || { bad "N1: no port mappings";                return 1; }

  # --- safe assignment to NC_* globals ---
  NC_NAME="$_name"
  NC_IP="$_ip"
  NC_AUTH="$_auth"
  NC_ENCRYPT="$_enc"
  NC_ENC_KEY="$_ekey"
  NC_TIMEOUT="$_timeout"
  NC_RESTART="$_restart"
  NC_PROFILE="$_profile"
  NC_BS="$_bs"
  NC_MW="$_mw"
  NC_RST="$_rst"
  NC_GZ="$_gz"
  NC_ICMP="$_icmp"
  NC_PAIRING_ID="$_pid"
  NC_CREATED="$_ts"
  NC_PORTS="$_ports"
  return 0
}

# Expand NC_PORTS (same format as PC_PORTS) into a ports.list file.
# Returns number of rows written, or 0 on failure.
expand_noc_ports() {
  local csv="$1" out="$2"
  expand_ports_csv "$csv" "$out"
}

# Deploy KHAREJ/server side from a validated N1 code (NC_* globals set).
# Uses exactly the same helpers as screen_new_kharej.
_noc_deploy_kharej() {
  local name="$NC_NAME"

  # --- conflict checks ---
  if [ -d "$TUN_DIR/$name" ]; then
    bad "tunnel '$name' already exists on this server"
    dim "delete it first with Manage tunnels → Delete, then retry"
    return 1
  fi

  # auth key conflict
  local _ak_owner; _ak_owner="$(authkey_owner "$NC_AUTH" 2>/dev/null || true)"
  if [ -n "$_ak_owner" ]; then
    bad "auth key $NC_AUTH is already used by tunnel '$_ak_owner'"
    dim "the DARK NOC Hub must issue a different key for this server"
    return 1
  fi

  # icmp listen conflict (non-fatal: 0.0.0.0 sharing is fine, per existing logic)
  local _il_owner; _il_owner="$(icmp_listen_owner "$NC_ICMP" "" 2>/dev/null || true)"
  if [ -n "$_il_owner" ] && [ "$NC_ICMP" != "0.0.0.0" ]; then
    warn "ICMP listen $NC_ICMP already used by '$_il_owner'"
    warn "two servers sharing the same bind address — different keys keep them apart"
  fi

  # core check
  [ -x "$BIN_PATH" ] || { bad "pingtunnel core not installed — run Core install first"; return 1; }
  if [ "$NC_ENCRYPT" != none ] && ! core_supports_encrypt; then
    bad "installed core does not support encryption; requested: $NC_ENCRYPT"
    return 1
  fi

  # --- build tunnel ---
  mkdir -p "$TUN_DIR/$name"
  PARTIAL_TUNNEL="$name"

  # write ports.list
  local _n; _n="$(expand_noc_ports "$NC_PORTS" "$TUN_DIR/$name/ports.list")"
  [ "${_n:-0}" -gt 0 ] || {
    rm -rf "$TUN_DIR/$name"; PARTIAL_TUNNEL=""
    bad "N1 code contains no usable port mappings"; return 1
  }

  # set globals that write_meta / ensure_units consume
  NAME="$name"; ROLE=server; PUB_IP="$(public_ip)"; PEER_IP=""
  AUTH_KEY="$NC_AUTH"; ENCRYPT="$NC_ENCRYPT"; ENC_KEY="$NC_ENC_KEY"
  TIMEOUT="$NC_TIMEOUT"; LOCAL_BIND="$DEFAULT_BIND"; ICMP_LISTEN="$NC_ICMP"
  PROFILE="$NC_PROFILE"
  TCP_BS="$NC_BS"; TCP_MW="$NC_MW"; TCP_RST="$NC_RST"; TCP_GZ="$NC_GZ"
  TCP_STAT=0; MAXCONN=0; MAXPRT=100; MAXPRB=1000; CONNTT=1000
  RESTART_EVERY="$NC_RESTART"; LOGLEVEL=warn

  write_meta "$TUN_DIR/$name"
  PARTIAL_TUNNEL=""
  ensure_units

  # pair.code — store NOC code reference (do NOT log enc key)
  printf 'NOC-N1-pairing:%s\n' "$NC_PAIRING_ID" > "$TUN_DIR/$name/pair.code"
  chmod 600 "$TUN_DIR/$name/pair.code"

  # start
  start_tunnel "$name" || {
    bad "service failed to start — rolling back"
    "$FW_HELPER" clear "$name" >/dev/null 2>&1 || true
    systemctl disable "darkicmp@$name" >/dev/null 2>&1
    rm -rf "$TUN_DIR/$name"
    return 1
  }
  set_restart_timer "$name" "$NC_RESTART"
  return 0
}

# Interactive screen: KHAREJ receives a DARK NOC N1 Pair Code
screen_noc_kharej() {
  header "DARK NOC — CONNECT KHAREJ"
  top; sect "NOC PAIR CODE SETUP"; blank
  row "$(printf '%sThe DARK NOC Hub built the Iran side already.%s' "$D" "$N")"
  row "$(printf '%sPaste the DICMP-N1-... code here to build the KHAREJ/server side.%s' "$D" "$N")"
  row "$(printf '%sNo extra questions — settings come from the code.%s' "$D" "$N")"
  bot; echo

  [ -x "$BIN_PATH" ] || { bad "core not installed — main menu [1]"; pause; return; }

  info "paste the DARK NOC Pair Code from the Hub"
  ask "NOC pair code"
  local _raw_code="$ANS"

  if ! parse_noc_pair_code "$_raw_code"; then
    bad "invalid or unsupported NOC pair code"
    dim "make sure you copied the full DICMP-N1-... code from DARK NOC"
    pause; return
  fi

  # --- show summary, ask for single confirmation ---
  echo
  top; sect "DEPLOYMENT SUMMARY"; blank
  kv "tunnel name"  "$W$NC_NAME$N"
  kv "role"         "${W}KHAREJ / server$N"
  kv "ICMP listen"  "$W$NC_ICMP$N"
  kv "auth key"     "$W$NC_AUTH$N"
  kv "encryption"   "$W$NC_ENCRYPT$N"
  kv "profile"      "$W$NC_PROFILE$N"
  kv "restart"      "$W$NC_RESTART$N"
  kv "ports"        "$W$(pretty_ports "$NC_PORTS")$N"
  kv "pairing ID"   "$D$NC_PAIRING_ID$N"
  blank
  row "$(printf '%senc key and secrets are not displayed here%s' "$D" "$N")"
  bot; echo

  yesno "Deploy?" y || { info "cancelled"; pause; return; }
  echo

  _noc_deploy_kharej || { pause; return; }

  echo
  top; sect "DEPLOYED — $NC_NAME"; blank
  kv "role"       "${W}KHAREJ / server$N"
  kv "service"    "$W$(svc_raw "$NC_NAME")$N"
  kv "ports"      "$W$(pretty_ports "$(ports_csv "$TUN_DIR/$NC_NAME")")$N"
  kv "encryption" "$W$NC_ENCRYPT$N"
  kv "profile"    "$W$NC_PROFILE$N"
  blank
  row "$(printf '%sIran client is already configured by DARK NOC.%s' "$G" "$N")"
  row "$(printf '%sCheck tunnel health from the NOC dashboard.%s' "$D" "$N")"
  bot
  warn "ensure ICMP is open in your provider firewall / security-group"
  pause
}

# ============================================================ SERVICE INFO ==
svc_raw() { systemctl is-active "darkicmp@$1" 2>/dev/null; }
# Why is this unit not running? systemd knows the exit status and the journal
# holds the last words of the process - showing both beats sending the operator
# off to run journalctl by hand.
svc_fail_reason() { # <tunnel> -> one short line, or empty
  local n="$1" res code last
  res="$(systemctl show "darkicmp@$n" -p Result --value 2>/dev/null)"
  code="$(systemctl show "darkicmp@$n" -p ExecMainStatus --value 2>/dev/null)"
  last="$(journalctl -u "darkicmp@$n" -n 30 --no-pager -o cat 2>/dev/null \
        | grep -viE '^\s*$' \
        | grep -iE 'error|fail|invalid|cannot|denied|refused|no such|permission|flag provided' \
        | tail -n1)"
  [ -n "$last" ] && { echo "${last:0:56}"; return; }
  case "$res" in
    exit-code) echo "exited with status ${code:-?}" ;;
    signal)    echo "killed by a signal" ;;
    timeout)   echo "start timed out" ;;
    success)   echo "stopped cleanly - was it ever started?" ;;
    *)         echo "${res:-not running}" ;;
  esac
}

svc_uptime() {
  # 0 means the unit has never entered the active state - without this guard
  # the arithmetic below reports the machine's uptime as the tunnel's.
  [ "$(svc_raw "$1")" = active ] || { echo '-'; return; }
  local ts now; ts="$(systemctl show "darkicmp@$1" -p ActiveEnterTimestampMonotonic --value 2>/dev/null)"
  [[ "$ts" =~ ^[0-9]+$ ]] && [ "$ts" -gt 0 ] || { echo '-'; return; }
  now="$(awk '{printf "%.0f", $1*1000000}' /proc/uptime 2>/dev/null)"; [[ "$now" =~ ^[0-9]+$ ]] || { echo '-'; return; }
  local s=$(( (now-ts)/1000000 )); [ "$s" -lt 0 ] && s=0; printf '%dd %02dh %02dm' $((s/86400)) $(((s%86400)/3600)) $(((s%3600)/60))
}
svc_uptime_short() { local u; u="$(svc_uptime "$1")"; echo "$u" | awk '{if($1!="0d")print $1; else print $2}' | sed 's/^0//'; }
events_since() { journalctl -u "darkicmp@$1" --since "$2" --no-pager -o cat 2>/dev/null | grep -Eci 'Run ERROR|ERROR:|panic|forward worker .* exited|Failed|exited with'; }
# Which local address the raw ICMP socket binds to. Raw sockets do not clash
# the way TCP does, so several tunnels can share 0.0.0.0 - but when the box has
# more than one address, giving each tunnel its own keeps them cleanly apart.
icmp_listen_owner() { # <addr> <exclude-tunnel> -> tunnel already using it
  local a="$1" skip="$2" n cur
  while read -r n; do
    [ -n "$n" ] || continue
    [ "$n" = "$skip" ] && continue
    [ -f "$TUN_DIR/$n/meta.conf" ] || continue
    cur="$(read_meta_field "$TUN_DIR/$n/meta.conf" ICMP_LISTEN)"; cur="${cur:-0.0.0.0}"
    [ "$cur" = "$a" ] && { echo "$n"; return 0; }
  done <<<"$(tunnel_names)"
  return 1
}
pick_icmp_listen() { # [exclude-tunnel]
  local skip="${1:-}" addrs=() line i owner
  while read -r line; do [ -n "$line" ] && addrs+=("$line"); done <<<"$(local_ipv4s)"
  { echo; top; sect "ICMP BIND ADDRESS"
    row "$(printf '%swhich local address handles the raw ICMP packets%s' "$D" "$N")"
    row "$(printf '%s0.0.0.0 works for several tunnels, but a dedicated%s' "$D" "$N")"
    row "$(printf '%saddress per tunnel is cleaner when you have more than one%s' "$D" "$N")"
    blank
    owner="$(icmp_listen_owner 0.0.0.0 "$skip" 2>/dev/null || true)"
    row "$(printf '%s[1]%s %-18s %s' "$Y" "$N" "0.0.0.0" \
          "$([ -n "$owner" ] && printf '%salso used by %s%s' "$Y" "$owner" "$N" || printf '%sall addresses%s' "$D" "$N")")"
    i=2
    for line in "${addrs[@]}"; do
      owner="$(icmp_listen_owner "${line##* }" "$skip" 2>/dev/null || true)"
      row "$(printf '%s[%d]%s %-18s %s' "$Y" "$i" "$N" "${line##* }" \
            "$([ -n "$owner" ] && printf '%staken by %s%s' "$R" "$owner" "$N" || printf '%s%s%s' "$D" "${line%% *}" "$N")")"
      i=$((i+1))
    done
    bot; echo; } >&2
  local k; printf '  %s>%s Bind [1]: ' "$C" "$N" >&2; read -rsn1 k; printf '%s\n' "$k" >&2
  if [[ "$k" =~ ^[0-9]+$ ]] && [ "$k" -ge 2 ] && [ "$k" -le $(( ${#addrs[@]} + 1 )) ]; then
    line="${addrs[$((k-2))]}"; echo "${line##* }"
  else echo "0.0.0.0"; fi
}

# --------------------------------------------------------------- AUTH KEYS -
# The key is what actually separates several pingtunnel instances sharing one
# host: every packet carries it, and an instance ignores anything that does not
# match. pingtunnel takes it as an integer, 0 - 2147483647.
# The bind address cannot do this job: ICMP echo arrives addressed to the
# server's public IP, so a socket bound to some other address never sees it.
AUTHKEY_BASE=10010

authkey_owner() { # <key> [exclude] -> tunnel already using it
  local k="$1" skip="${2:-}" n cur
  while read -r n; do
    [ -n "$n" ] || continue
    [ "$n" = "$skip" ] && continue
    [ -f "$TUN_DIR/$n/meta.conf" ] || continue
    cur="$(read_meta_field "$TUN_DIR/$n/meta.conf" AUTH_KEY)"
    [ "$cur" = "$k" ] && { echo "$n"; return 0; }
  done <<<"$(tunnel_names)"
  return 1
}
next_auth_key() { # one past the highest key in use, or the base
  local n cur max=0
  while read -r n; do
    [ -n "$n" ] || continue
    [ -f "$TUN_DIR/$n/meta.conf" ] || continue
    cur="$(read_meta_field "$TUN_DIR/$n/meta.conf" AUTH_KEY)"
    [[ "$cur" =~ ^[0-9]+$ ]] || continue
    [ "$cur" -gt "$max" ] && max="$cur"
  done <<<"$(tunnel_names)"
  [ "$max" -lt "$AUTHKEY_BASE" ] && { echo "$AUTHKEY_BASE"; return; }
  echo $(( max + 1 ))
}
valid_auth_key() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 0 ] && [ "$1" -le 2147483647 ]; }

# Asks for the key, defaulting to the next free number in the sequence.
pick_auth_key() { # [exclude-tunnel]
  local skip="${1:-}" sug owner v
  sug="$(next_auth_key)"
  { echo; top; sect "TUNNEL KEY"
    row "$(printf '%severy ICMP tunnel on a host needs its own number%s' "$D" "$N")"
    row "$(printf '%sthis is what keeps 5 or 6 of them apart, not the bind%s' "$D" "$N")"
    row "$(printf '%srange 0 - 2147483647, and both servers must match%s' "$D" "$N")"
    blank
    local n cur
    while read -r n; do
      [ -n "$n" ] || continue
      [ -f "$TUN_DIR/$n/meta.conf" ] || continue
      cur="$(read_meta_field "$TUN_DIR/$n/meta.conf" AUTH_KEY)"
      row "$(printf '%s%-14s %s%s%s' "$D" "${n:0:14}" "$W" "$cur" "$N")"
    done <<<"$(tunnel_names)"
    [ -z "$(tunnel_names)" ] && row "$(printf '%sno tunnels yet%s' "$D" "$N")"
    bot; echo; } >&2
  while :; do
    printf '  %s>%s Key %s[%s]%s: ' "$C" "$N" "$D" "$sug" "$N" >&2
    read -r v; v="${v:-$sug}"
    if ! valid_auth_key "$v"; then
      printf '  %sx%s must be a number between 0 and 2147483647\n' "$R" "$N" >&2; continue
    fi
    owner="$(authkey_owner "$v" "$skip" 2>/dev/null || true)"
    if [ -n "$owner" ]; then
      printf '  %s!%s %s already uses key %s\n' "$Y" "$N" "$owner" "$v" >&2
      printf '  %s>%s use it anyway? [y/N]: ' "$C" "$N" >&2
      local a; read -r a; [[ "$a" =~ ^[Yy]$ ]] || continue
    fi
    echo "$v"; return 0
  done
}

active_server_other() {
  local except="$1" n; while read -r n; do [ -n "$n" ] || continue; [ "$n" = "$except" ] && continue; load_meta "$n" || continue; [ "$ROLE" = server ] && [ "$(svc_raw "$n")" = active ] && { echo "$n"; return 0; }; done <<<"$(tunnel_names)"; return 1
}
start_tunnel() {
  local name="$1" other; load_meta "$name" || return 1
  if [ "$ROLE" = server ]; then
    # Several servers can share the host: the raw ICMP socket is not exclusive
    # and each instance ignores packets whose key is not its own. Warn when
    # anything they must not share is actually shared, then carry on.
    other="$(active_server_other "$name" 2>/dev/null || true)"
    if [ -n "$other" ]; then
      local okey obind mine_bind
      okey="$(read_meta_field "$TUN_DIR/$other/meta.conf" AUTH_KEY)"
      obind="$(read_meta_field "$TUN_DIR/$other/meta.conf" ICMP_LISTEN)"; obind="${obind:-0.0.0.0}"
      mine_bind="${ICMP_LISTEN:-0.0.0.0}"
      if [ "$okey" = "$AUTH_KEY" ]; then
        bad "'$other' is already running with the same key ($AUTH_KEY)"
        dim "two servers cannot share a key - change it in Security first"
        return 1
      fi
      warn "'$other' also serves ICMP here (key $okey, bind $obind)"
      [ "$obind" = "$mine_bind" ] && dim "same bind, different keys - that is fine for pingtunnel"
    fi
  else
    if ! render_forward_map "$TUN_DIR/$name/ports.list" client "${LOCAL_BIND:-0.0.0.0}" "$name" >/dev/null; then
      warn "local bind conflict detected - another IRAN tunnel already owns one of these ports"
      dim "Manage tunnels > Ports lets you change only the IRAN local port without changing the KHAREJ target"
      return 1
    fi
  fi
  ensure_units; "$FW_HELPER" apply "$name" >/dev/null 2>&1 || true
  systemctl enable --now "darkicmp@$name" >/dev/null 2>&1; sleep 2
  if [ "$(svc_raw "$name")" = active ]; then ok "tunnel is running"; return 0; fi
  bad "service did not come up"; journalctl -u "darkicmp@$name" -n 12 --no-pager -o cat 2>/dev/null | sed 's/^/    /'; return 1
}
_ipt_comment_bytes() { local chain="$1" name="$2"; iptables -w 5 -L "$chain" -v -n -x 2>/dev/null | awk -v m="darkicmp-$name" '$0~m{s+=$2} END{print s+0}'; }
tunnel_traffic() {
  local name="$1" dir="$TUN_DIR/$1" inb=0 outb=0 proto p target a; load_meta "$name" >/dev/null 2>&1 || { echo '0 0'; return; }
  if [ "$ROLE" = server ]; then echo "$(_ipt_comment_bytes INPUT "$name") $(_ipt_comment_bytes OUTPUT "$name")"; return; fi
  while IFS=$'\t' read -r proto p target; do
    a="$(iptables -w 5 -L INPUT -v -n -x 2>/dev/null | awk -v m="darkicmp-$name" -v pt="dpt:$p" '$0~m && $0~pt{s+=$2} END{print s+0}')"; inb=$((inb+${a:-0}))
    a="$(iptables -w 5 -L OUTPUT -v -n -x 2>/dev/null | awk -v m="darkicmp-$name" -v pt="spt:$p" '$0~m && $0~pt{s+=$2} END{print s+0}')"; outb=$((outb+${a:-0}))
  done < "$dir/ports.list"; echo "$inb $outb"
}

# ============================================================= PICKERS =====
pick_encrypt() {
  { echo; top; sect "ENCRYPTION"; row "$(printf '%score-supported end-to-end encryption%s' "$D" "$N")"; blank; item 1 "AES-128" "recommended"; item 2 "AES-256" "stronger / more CPU"; item 3 "ChaCha20" "fast on low-end CPUs"; item 4 "None" "authentication only"; bot; echo; } >&2
  local k; printf '  %s>%s Encryption [1]: ' "$C" "$N" >&2; read -rsn1 k; printf '%s\n' "$k" >&2
  case "$k" in 2) echo aes256;; 3) echo chacha20;; 4) echo none;; *) echo aes128;; esac
}
pick_restart() {
  { echo; top; sect "SCHEDULED RESTART"; row "$(printf '%soptional recovery timer%s' "$D" "$N")"; blank; item 1 "off" "recommended first"; item 2 "1h" ""; item 3 "3h" ""; item 4 "6h" ""; item 5 "12h" ""; item 6 "24h" ""; bot; echo; } >&2
  local k; printf '  %s>%s Restart every [1]: ' "$C" "$N" >&2; read -rsn1 k; printf '%s\n' "$k" >&2
  case "$k" in 2) echo 1h;; 3) echo 3h;; 4) echo 6h;; 5) echo 12h;; 6) echo 24h;; *) echo off;; esac
}

# =========================================================== CREATE KHAREJ =
screen_new_kharej() {
  header "NEW TUNNEL - KHAREJ (server)"; [ -x "$BIN_PATH" ] || { bad "core not installed - main menu [1]"; pause; return; }
  top; sect "KHAREJ SETUP MODE"; blank
  row "$(printf '%s[1]  Standard setup%s   %screate tunnel + Pair Code for IRAN%s'    "$Y" "$N" "$D" "$N")"
  row "$(printf '%s[2]  DARK NOC%s         %spaste Hub-generated NOC Pair Code%s'      "$Y" "$N" "$D" "$N")"
  item 0 "Back" ""
  bot; echo; getkey
  case "$KEYSEL" in
    2|n|N) screen_noc_kharej; return ;;
    0|_)   return ;;
  esac
  top; sect "STEP 1 / 2"; blank
  row "$(printf '%screate ICMP server here, then copy Pair Code to IRAN%s' "$D" "$N")"
  bot; echo
  local other; other="$(active_server_other "" 2>/dev/null || true)"
  if [ -n "$other" ]; then
    echo; top; sect "ANOTHER ICMP SERVER IS RUNNING"
    row "$(printf '%s%s is already serving ICMP on this host%s' "$W" "$other" "$N")"
    blank
    row "$(printf '%sa second one works, but only if it differs:%s' "$D" "$N")"
    row "$(printf '%s  - its own auth key (generated automatically)%s' "$D" "$N")"
    row "$(printf '%s  - its own ICMP bind address, if this box has more%s' "$D" "$N")"
    blank
    row "$(printf '%sotherwise just add the extra ports to %s instead%s' "$Y" "$other" "$N")"
    bot; echo
    yesno "create a second ICMP server anyway?" n || return
  fi
  local name
  while :; do ask "tunnel name"; name="$ANS"; valid_name "$name" || { bad "letters, digits, - and _ only"; continue; }; [ -d "$TUN_DIR/$name" ] && { bad "name already exists"; continue; }; break; done
  info "detecting public ip"; PUB_IP="$(public_ip)"; ask "public ip / domain of this KHAREJ server" "$PUB_IP"; PUB_IP="$ANS"; valid_host "$PUB_IP" || { bad "invalid address"; pause; return; }
  mkdir -p "$TUN_DIR/$name"; PARTIAL_TUNNEL="$name"
  read_services_into "$TUN_DIR/$name/ports.list"
  echo; render_forward_map "$TUN_DIR/$name/ports.list" server; echo
  AUTH_KEY="$(pick_auth_key)"; ENCRYPT="$DEFAULT_ENCRYPT"; if core_supports_encrypt; then ENCRYPT="$(pick_encrypt)"; else warn "installed core has no encryption flag - using authentication only"; ENCRYPT=none; fi
  ENC_KEY=""; [ "$ENCRYPT" = none ] || ENC_KEY="$(gen_enc_key)"
  TIMEOUT="$DEFAULT_TIMEOUT"; PROFILE="$DEFAULT_PROFILE"; TCP_BS="$DEFAULT_TCP_BS"; TCP_MW="$DEFAULT_TCP_MW"; TCP_RST="$DEFAULT_TCP_RST"; TCP_GZ="$DEFAULT_TCP_GZ"; TCP_STAT=0
  local _prof; _prof="$(pick_icmp_profile)"; apply_icmp_profile "$_prof"; [ "$PROFILE" = custom ] && prompt_icmp_custom
  MAXCONN=0; MAXPRT=100; MAXPRB=1000; CONNTT=1000; LOCAL_BIND="$DEFAULT_BIND"; ICMP_LISTEN="$(pick_icmp_listen)"; RESTART_EVERY="$(pick_restart)"; LOGLEVEL=warn; PEER_IP=""; NAME="$name"; ROLE=server
  write_meta "$TUN_DIR/$name"; PARTIAL_TUNNEL=""; ensure_units; make_pair_code "$TUN_DIR/$name" > "$TUN_DIR/$name/pair.code"; chmod 600 "$TUN_DIR/$name/pair.code"
  echo; top; sect "CREATED - $name"; blank; kv "role" "$W KHAREJ / server$N"; kv "icmp" "$W$PUB_IP$N"; kv "panel ports" "$W$(pretty_ports "$(ports_csv "$TUN_DIR/$name")")$N"; kv "security" "$W$ENCRYPT$N $D+ numeric auth key$N"; kv "profile" "$W$PROFILE$N"; kv "restart" "$W$RESTART_EVERY$N"; bot; echo
  start_tunnel "$name" || { pause; return; }; set_restart_timer "$name" "$RESTART_EVERY"; show_pair_code "$name"; warn "provider firewall/security-group must allow ICMP to this server"; pause
}

# ============================================================= CREATE IRAN ==
screen_new_iran() {
  header "NEW TUNNEL - IRAN (client)"; [ -x "$BIN_PATH" ] || { bad "core not installed - main menu [1]"; pause; return; }
  top; sect "STEP 2 / 2 - IRAN"; blank
  row "$(printf '%s1) Pair Code  ->  2) Local Bind  ->  3) IRAN local ports%s' "$D" "$N")"
  row "$(printf '%sfirst tunnel: defaults are usually correct%s' "$D" "$N")"
  row "$(printf '%ssecond/next tunnel: remap only a conflicting IRAN port%s' "$Y" "$N")"
  bot; echo
  local name
  while :; do ask "tunnel name"; name="$ANS"; valid_name "$name" || { bad "letters, digits, - and _ only"; continue; }; [ -d "$TUN_DIR/$name" ] && { bad "name already exists"; continue; }; break; done
  echo; info "paste the pair code from the KHAREJ server"; ask "pair code"
  if ! parse_pair_code "$ANS"; then bad "invalid or unsupported pair code"; pause; return; fi
  echo; top; sect "PAIRED WITH"; blank; kv "kharej" "$W$PC_IP$N"; kv "security" "$W$PC_ENCRYPT$N"; kv "forward ports" "$W$(pretty_ports "$PC_PORTS")$N"; kv "profile" "$W$PC_PROFILE$N"; kv "restart" "$W$PC_RESTART$N"; bot; echo

  LOCAL_BIND="$(pick_local_bind)"
  [ "$LOCAL_BIND" != INVALID ] || { bad "invalid custom local IPv4"; pause; return; }

  mkdir -p "$TUN_DIR/$name"; PARTIAL_TUNNEL="$name"
  local n; n="$(expand_ports_csv "$PC_PORTS" "$TUN_DIR/$name/ports.list")"
  [ "${n:-0}" -gt 0 ] || { bad "pair code contains no usable ports"; rm -rf "$TUN_DIR/$name"; pause; return; }

  echo
  while :; do
    if render_forward_map "$TUN_DIR/$name/ports.list" client "$LOCAL_BIND" "$name"; then
      echo; ok "every IRAN listen port is free"
      break
    fi
    echo; warn "some IRAN listen ports are already taken"
    if ! yesno "pick different IRAN ports now?" y; then
      discard_partial; info "creation cancelled - nothing was changed"; pause; return
    fi
    resolve_port_clashes "$TUN_DIR/$name/ports.list" "$LOCAL_BIND" "$name"
    echo
  done
  echo

  NAME="$name"; ROLE=client; PUB_IP=""; PEER_IP="$PC_IP"; AUTH_KEY="$PC_AUTH"; ENCRYPT="$PC_ENCRYPT"; ENC_KEY="$PC_ENC_KEY"; TIMEOUT="$PC_TIMEOUT"; RESTART_EVERY="$PC_RESTART"
  PROFILE="$PC_PROFILE"; TCP_BS="$PC_BS"; TCP_MW="$PC_MW"; TCP_RST="$PC_RST"; TCP_GZ="$PC_GZ"; TCP_STAT=0; ICMP_LISTEN="$(pick_icmp_listen)"; MAXCONN=0; MAXPRT=100; MAXPRB=1000; CONNTT=1000; LOGLEVEL=warn
  write_meta "$TUN_DIR/$name"; PARTIAL_TUNNEL=""; ensure_units
  echo; top; sect "CREATED - $name"; blank; kv "role" "$W IRAN / client$N"; kv "peer" "$W$PEER_IP$N"; kv "local bind" "$W$LOCAL_BIND$N"; kv "security" "$W$ENCRYPT$N"; kv "profile" "$W$PROFILE$N"; bot; echo
  render_forward_map "$TUN_DIR/$name/ports.list" client "$LOCAL_BIND" "$name"; echo
  start_tunnel "$name" || { pause; return; }; set_restart_timer "$name" "$RESTART_EVERY"
  echo
  if [ "$LOCAL_BIND" = 0.0.0.0 ]; then
    local _a _src; read -r _a _src <<<"$(detect_server_addr)"
    if [ -n "$_a" ]; then
      info "users connect to  $W$_a:<IRAN local port>$N"
      case "$_src" in
        nat:*) dim "outbound traffic leaves via ${_src#nat:} - use that instead if your users reach it there" ;;
        outbound) warn "no address found on this machine; ${_a} came from an outbound lookup" ;;
      esac
    else
      warn "could not determine this server's address - use the IP your users connect to"
    fi
  else
    info "apps connect to  $W$LOCAL_BIND:<IRAN local port>$N"
  fi
  dim "KHAREJ target ports stay exactly as shown in the Forward Map"
  dim "run Diagnostics > ICMP quality to verify the path"; pause
}

# =============================================================== MANAGE =====
# ---------------------------------------------------------- PARTIAL STATE --
# The tunnel folder is created before its metadata is written, so a Ctrl+C part
# way through setup used to leave a directory that no screen could open and
# nothing could delete. Track the in-progress name and clear it on interrupt.
PARTIAL_TUNNEL=""

tunnel_complete() { [ -s "$TUN_DIR/$1/meta.conf" ]; }

discard_partial() {
  [ -n "$PARTIAL_TUNNEL" ] || return 0
  local p="$PARTIAL_TUNNEL"; PARTIAL_TUNNEL=""
  [ -d "$TUN_DIR/$p" ] || return 0
  tunnel_complete "$p" && return 0
  rm -rf "${TUN_DIR:?}/$p"
  return 0
}

on_interrupt() {
  trap - INT TERM
  echo
  if [ -n "$PARTIAL_TUNNEL" ]; then
    discard_partial
    printf '  %s!%s cancelled - the half-created tunnel was removed\n' "$Y" "$N"
  else
    printf '  %s!%s cancelled\n' "$Y" "$N"
  fi
  exit 130
}

# A stuck unit sits in "deactivating" and every systemctl call blocks behind it,
# which from the menu looks exactly like a freeze. Bound the stop and force it.
stop_tunnel_hard() {
  local n="$1"
  systemctl disable "darkicmp@$n" >/dev/null 2>&1
  if ! timeout 15 systemctl stop "darkicmp@$n" >/dev/null 2>&1; then
    warn "service did not stop in time - forcing it"
    systemctl kill -s SIGKILL "darkicmp@$n" >/dev/null 2>&1
    sleep 1
  fi
  systemctl reset-failed "darkicmp@$n" >/dev/null 2>&1
  return 0
}

purge_tunnel() {
  local n="$1"
  stop_tunnel_hard "$n"
  set_restart_timer "$n" off 2>/dev/null
  [ -x "$FW_HELPER" ] && "$FW_HELPER" clear "$n" >/dev/null 2>&1
  rm -rf "${TUN_DIR:?}/$n"
}

# Catches leftovers from a hard kill, a dropped ssh session or an older build.
sweep_partials() {
  local n broken=()
  while read -r n; do
    [ -n "$n" ] || continue
    tunnel_complete "$n" || broken+=("$n")
  done <<<"$(tunnel_names)"
  [ ${#broken[@]} -eq 0 ] && return 0
  echo
  top; sect "INCOMPLETE TUNNELS"
  row "$(printf '%sthese were never finished and cannot be started%s' "$D" "$N")"
  blank
  for n in "${broken[@]}"; do row "$(printf '%s%s%s' "$R" "$n" "$N")"; done
  bot; echo
  if yesno "remove them?" y; then
    for n in "${broken[@]}"; do purge_tunnel "$n"; ok "removed $n"; done
    pause
  fi
  return 0
}

pick_tunnel() {
  local names=() n i=1; [ -n "$(tunnel_names)" ] || { bad "no tunnels yet"; return 1; }
  echo; top; sect "TUNNELS"; blank
  while read -r n; do [ -n "$n" ] || continue; names+=("$n"); if ! tunnel_complete "$n"; then row "$(printf '%s[%d]%s %sx %-13s INCOMPLETE%s' "$Y" "$i" "$N" "$R" "$n" "$N")"; i=$((i+1)); continue; fi; load_meta "$n"; row "$(printf '%s[%d]%s %s %-13s %s%-6s%s %s%s%s' "$Y" "$i" "$N" "$(dot "$(svc_raw "$n")")" "$n" "$D" "$ROLE" "$N" "$D" "$([ "$ROLE" = client ] && echo "-> $PEER_IP" || echo "icmp $PUB_IP")" "$N")"; i=$((i+1)); done <<<"$(tunnel_names)"
  blank; item 0 "Back" ""; bot; echo; getkey; [[ "$KEYSEL" =~ ^[0-9]+$ ]] || return 1; [ "$KEYSEL" -ge 1 ] && [ "$KEYSEL" -le ${#names[@]} ] || return 1; SELECTED="${names[$((KEYSEL-1))]}"; return 0
}
regen_pair_if_server() { local name="$1"; load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "inspect or delete this tunnel from the manage screen"; pause; return; }; [ "$ROLE" = server ] || return 0; make_pair_code "$TUN_DIR/$name" > "$TUN_DIR/$name/pair.code"; chmod 600 "$TUN_DIR/$name/pair.code"; }
screen_ports() {
  local name="$1" dir="$TUN_DIR/$1"
  while :; do
    load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "use Diagnostics to inspect it, or delete the tunnel"; pause; return; }
    header "FORWARD PORTS - $name"
    render_forward_map "$dir/ports.list" "$ROLE" "${LOCAL_BIND:-0.0.0.0}" "$name" || true
    echo
    top; sect "HOW IT WORKS"; blank
    if [ "$ROLE" = server ]; then
      row "$(printf '%sPair Code maps IRAN local port  ->  KHAREJ panel target%s' "$D" "$N")"
      row "$(printf '%sedits rebuild Pair Code; re-pair IRAN after changes%s' "$Y" "$N")"
    else
      row "$(printf '%sIRAN local port  ->  ICMP tunnel  ->  KHAREJ panel target%s' "$D" "$N")"
      row "$(printf '%sfor tunnel #2/#3, change LEFT local port if it conflicts%s' "$Y" "$N")"
    fi
    mid; item 1 "Add forward" "listen -> Kharej service"; item 2 "Remove forward" "by row number"; item 3 "Change IRAN listen ports" "$([ "$ROLE" = client ] && echo 'safe remap' || echo 'client side only')"; item 5 "Change KHAREJ service" "where the far end dials"; item 4 "Apply + restart" ""; item 0 "Back" ""; bot; echo; getkey
    case "$KEYSEL" in
      1)
        echo; top; sect "ADD FORWARDS"
        row "$(printf '%sone port, or several separated by commas%s' "$D" "$N")"
        row "$(printf '%sexample:  8000,2087,443%s' "$D" "$N")"
        row "$(printf '%seach becomes  IRAN <port>  ->  127.0.0.1:<port>%s' "$D" "$N")"
        bot; echo
        ask "protocol tcp/udp/both" "tcp"; local proto="${ANS,,}"
        case "$proto" in tcp|udp|both) ;; *) bad "tcp, udp or both"; pause; continue ;; esac
        ask "port(s)"
        local p added=0 skipped=0 _pa pr
        IFS=', ' read -r -a _pa <<<"$ANS"
        for p in "${_pa[@]}"; do
          valid_port "$p" || { skipped=$((skipped+1)); continue; }
          for pr in tcp udp; do
            [ "$proto" = both ] || [ "$proto" = "$pr" ] || continue
            if awk -F'\t' -v x="$pr" -v y="$p" '$1==x && $2==y{f=1} END{exit !f}' "$dir/ports.list" 2>/dev/null; then
              warn "${pr^^} $p already in this tunnel"; skipped=$((skipped+1)); continue
            fi
            printf '%s\t%s\t127.0.0.1:%s\n' "$pr" "$p" "$p" >> "$dir/ports.list"; added=$((added+1))
          done
        done
        if [ "$added" -gt 0 ]; then
          ok "$added forward(s) added - use [5] to retarget any of them, then apply"
        else bad "nothing added"; fi
        [ "$skipped" -gt 0 ] && dim "$skipped skipped"
        pause ;;
      2)
        ask "row number"; local rmidx="$ANS"; [[ "$rmidx" =~ ^[0-9]+$ ]] || { bad "invalid row"; pause; continue; }
        [ "$rmidx" -ge 1 ] 2>/dev/null && [ "$rmidx" -le "$(grep -c '[^[:space:]]' "$dir/ports.list" 2>/dev/null)" ] || { bad "row does not exist"; pause; continue; }
        awk -v r="$rmidx" 'NR!=r' "$dir/ports.list" > "$dir/ports.tmp" && mv "$dir/ports.tmp" "$dir/ports.list"; regen_pair_if_server "$name"; ok "forward removed"; [ "$ROLE" = server ] && warn "re-pair IRAN after changing KHAREJ forwards"; pause ;;
      3)
        [ "$ROLE" = client ] || { bad "local-port remap is only used on the IRAN/client side"; pause; continue; }
        local _cur_bind="${LOCAL_BIND:-0.0.0.0}"
        resolve_port_clashes "$dir/ports.list" "$_cur_bind" "$name"
        if render_forward_map "$dir/ports.list" client "$_cur_bind" "$name" >/dev/null; then ok "local ports updated"; else bad "a local-port conflict still exists - edit again before restart"; fi
        pause ;;
      5)
        ask "row number"; local rn="$ANS"
        [[ "$rn" =~ ^[0-9]+$ ]] || { bad "invalid row"; pause; continue; }
        local cur; cur="$(awk -F'\t' -v r="$rn" 'NR==r{print $3}' "$dir/ports.list")"
        [ -n "$cur" ] || { bad "no such row"; pause; continue; }
        top; sect "KHAREJ SERVICE"
        row "$(printf '%sthe address the KHAREJ box dials for this forward%s' "$D" "$N")"
        row "$(printf '%suse 127.0.0.1:PORT when the panel listens on localhost%s' "$D" "$N")"
        row "$(printf '%suse the KHAREJ LAN ip when the panel binds one address%s' "$D" "$N")"
        bot; echo
        ask "target host:port" "$cur"
        local nt="$ANS"
        [[ "$nt" =~ ^[^[:space:]|,]+:[0-9]+$ ]] || { bad "must be host:port"; pause; continue; }
        awk -F'\t' -v r="$rn" -v t="$nt" 'BEGIN{OFS="\t"} NR==r{$3=t} {print}' "$dir/ports.list" > "$dir/ports.tmp" \
          && mv -f "$dir/ports.tmp" "$dir/ports.list" && ok "row $rn now targets $nt - press [4] to apply" || bad "edit failed"
        pause ;;
      4)
        [ -s "$dir/ports.list" ] || { bad "at least one forward is required"; pause; continue; }
        if [ "$ROLE" = client ] && ! render_forward_map "$dir/ports.list" client "$LOCAL_BIND" "$name" >/dev/null; then warn "fix the conflicting IRAN local port first"; pause; continue; fi
        "$FW_HELPER" apply "$name" >/dev/null 2>&1 || true; systemctl restart "darkicmp@$name" 2>/dev/null; regen_pair_if_server "$name"; sleep 2; [ "$(svc_raw "$name")" = active ] && ok "running" || bad "service failed"; pause ;;
      0|_) return ;;
    esac
  done
}
screen_security() {
  local name="$1"; load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "inspect or delete this tunnel from the manage screen"; pause; return; }; header "SECURITY - $name"; top; kv "auth key" "$W$AUTH_KEY$N"; kv "encryption" "$W$ENCRYPT$N"; kv "enc key" "$W$([ "$ENCRYPT" = none ] && echo none || echo '******** (stored)')$N"; mid; item 1 "New auth key" ""; item 2 "Encryption" "AES128 / AES256 / ChaCha20"; item 3 "New encryption key" ""; item 0 "Back" ""; bot; echo; getkey
  case "$KEYSEL" in
    1) AUTH_KEY="$(pick_auth_key "$name")"; write_meta "$TUN_DIR/$name"; regen_pair_if_server "$name"; ok "new auth key generated"; warn "the other side must be re-paired" ;;
    2) core_supports_encrypt || { bad "installed core does not expose encryption flags"; pause; return; }; ENCRYPT="$(pick_encrypt)"; [ "$ENCRYPT" = none ] && ENC_KEY="" || [ -n "$ENC_KEY" ] || ENC_KEY="$(gen_enc_key)"; write_meta "$TUN_DIR/$name"; regen_pair_if_server "$name"; ok "encryption: $ENCRYPT"; warn "the other side must use the same setting" ;;
    3) [ "$ENCRYPT" != none ] || { bad "enable encryption first"; pause; return; }; ENC_KEY="$(gen_enc_key)"; write_meta "$TUN_DIR/$name"; regen_pair_if_server "$name"; ok "new encryption key generated"; warn "the other side must be re-paired" ;;
    *) return ;;
  esac
  if yesno "restart this side now?" y; then systemctl restart "darkicmp@$name" 2>/dev/null; fi; pause
}
screen_performance() {
  local name="$1" p
  load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "use Diagnostics to inspect it, or delete the tunnel"; pause; return; }
  while :; do
    header "PERFORMANCE - $name"
    top; sect "SPEED PROFILE"; blank
    kv "profile"    "$W$PROFILE$N"
    kv "buffer"     "$W$TCP_BS$N"
    kv "max window" "$W$TCP_MW$N"
    kv "resend"     "$W${TCP_RST} ms$N"
    kv "compress"   "$W$TCP_GZ$N $D(0 = off)$N"
    blank
    row "$(printf '%sBalanced keeps the normal pingtunnel baseline. Profiles only%s' "$D" "$N")"
    row "$(printf '%schange real TCP-mode knobs; UDP forwards are unaffected.%s' "$D" "$N")"
    mid
    item 1 "Stable"   "lossy / filtered path"
    item 2 "Balanced" "recommended"
    item 3 "Low Ping" "interactive / gaming"
    item 4 "Turbo"    "higher throughput"
    item 5 "Custom"   "manual values"
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEYSEL" in
      1) apply_icmp_profile stable ;;
      2) apply_icmp_profile balanced ;;
      3) apply_icmp_profile lowping ;;
      4) apply_icmp_profile turbo ;;
      5) prompt_icmp_custom ;;
      0|_) return ;;
    esac
    write_meta "$TUN_DIR/$name"
    regen_pair_if_server "$name"
    systemctl restart "darkicmp@$name" 2>/dev/null
    sleep 2
    [ "$(svc_raw "$name")" = active ] && ok "profile applied: $PROFILE" || warn "profile saved; service is not active"
    [ "$ROLE" = server ] && warn "Pair Code changed - re-pair IRAN to apply this profile there"
    pause
    load_meta "$name"
  done
}

screen_endpoint() {
  local name="$1"; load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "inspect or delete this tunnel from the manage screen"; pause; return; }; header "ENDPOINT - $name"
  if [ "$ROLE" = server ]; then
    top; kv "public ip" "$W$PUB_IP$N"; blank; row "$(printf '%sthis address is stored in the Pair Code for the IRAN side%s' "$D" "$N")"; bot; echo
    ask "new public ip / domain" "$PUB_IP"; valid_host "$ANS" || { bad "invalid address"; pause; return; }; PUB_IP="$ANS"; write_meta "$TUN_DIR/$name"; regen_pair_if_server "$name"; ok "pair endpoint updated"; warn "re-pair the Iran side"
  else
    top; kv "kharej peer" "$W$PEER_IP$N"; kv "local bind" "$W$LOCAL_BIND$N"; blank
    row "$(printf '%sLocal Bind is the address that opens IRAN forward ports%s' "$D" "$N")"; bot; echo
    ask "new kharej ip / domain" "$PEER_IP"; valid_host "$ANS" || { bad "invalid address"; pause; return; }; local newpeer="$ANS"
    local newbind; newbind="$(pick_local_bind)"; [ "$newbind" != INVALID ] || { bad "invalid custom local IPv4"; pause; return; }
    if ! render_forward_map "$TUN_DIR/$name/ports.list" client "$newbind" "$name" >/dev/null; then warn "that bind would conflict with another IRAN tunnel"; dim "change local ports first from Manage > Forward Ports"; pause; return; fi
    PEER_IP="$newpeer"; LOCAL_BIND="$newbind"; write_meta "$TUN_DIR/$name"; systemctl restart "darkicmp@$name" 2>/dev/null; sleep 2; [ "$(svc_raw "$name")" = active ] && ok "updated and running" || bad "updated but service failed - check Diagnostics"
  fi
  pause
}
screen_repair() {
  local name="$1"; load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "inspect or delete this tunnel from the manage screen"; pause; return; }; header "REPAIR - $name"
  [ -x "$BIN_PATH" ] || { bad "core binary missing - install it from Core first"; pause; return; }
  info "rebuilding runner, systemd units and firewall rules"
  ensure_units
  "$FW_HELPER" clear "$name" >/dev/null 2>&1 || true
  "$FW_HELPER" apply "$name" >/dev/null 2>&1 || true
  systemctl enable "darkicmp@$name" >/dev/null 2>&1 || true
  systemctl restart "darkicmp@$name" 2>/dev/null
  sleep 2
  if [ "$(svc_raw "$name")" = active ]; then ok "service repaired and running"; else bad "repair completed but service is still not active"; journalctl -u "darkicmp@$name" -n 15 --no-pager -o cat 2>/dev/null | sed 's/^/    /'; fi
  pause
}

screen_manage_one() {
  local name="$1"; while :; do if ! tunnel_complete "$name"; then header "TUNNEL - $name"; top; sect "INCOMPLETE"; row "$(printf '%sthis tunnel was never finished - no usable config%s' "$D" "$N")"; blank; item d "Delete it" ""; item 0 "Back" ""; bot; echo; getkey; case "${KEYSEL:-$KEY}" in d|D) purge_tunnel "$name"; ok "removed"; pause; return ;; *) return ;; esac; fi; load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "inspect or delete this tunnel from the manage screen"; pause; return; }; header "TUNNEL - $name"; local st ti to; st="$(svc_raw "$name")"; read -r ti to <<<"$(tunnel_traffic "$name")"
    top; sect "STATUS"; blank; kv "state" "$(case "$st" in active) badge ACTIVE "$BG_OK$W";; failed) badge FAILED "$BG_ERR$W";; *) badge "${st:-IDLE}" "$BG_WARN$W";; esac)  $D uptime $(svc_uptime "$name")$N"; kv "role" "$W$ROLE$N"; [ "$ROLE" = client ] && { kv "peer" "$W$PEER_IP$N"; kv "local bind" "$W$LOCAL_BIND$N"; } || kv "public" "$W$PUB_IP$N"; kv "security" "$W$ENCRYPT$N"; kv "profile" "$W$PROFILE$N"; kv "traffic" "$L4$(human_bytes "$ti") in$N  $L6$(human_bytes "$to") out$N"; if [ "$st" != active ]; then _w="$(svc_fail_reason "$name")"; [ -n "$_w" ] && kv "why" "$R$_w$N"; fi; kv "events/1h" "$W$(events_since "$name" '1 hour ago')$N"; kv "restart" "$W$RESTART_EVERY$N"
    mid; sect "CONTROL"; item 1 "Start" ""; item 2 "Stop" ""; item 3 "Restart" ""; mid; sect "CONFIGURE"; item 4 "Forward ports" "IRAN listen -> KHAREJ target"; item 5 "Security" "auth + encryption"; item 6 "Endpoint + bind" "peer / local bind"; item 7 "Performance" "speed profile"; item s "Speed test" "latency + throughput"
    item 8 "Scheduled restart" ""; item r "Repair" "systemd + firewall"; mid; sect "INSPECT"; item 9 "Show config" "redacted"; item p "Pair code" "server only"; item e "Edit meta by hand" "advanced"; item d "Delete tunnel" ""; item 0 "Back" ""; bot; echo; getkey
    case "$KEYSEL" in
      1) start_tunnel "$name"; pause;; 2) systemctl stop "darkicmp@$name" 2>/dev/null; ok "stopped"; pause;; 3) systemctl restart "darkicmp@$name" 2>/dev/null; sleep 2; [ "$(svc_raw "$name")" = active ] && ok "running" || bad "failed"; pause;; 4) screen_ports "$name";; 5) screen_security "$name";; 6) screen_endpoint "$name";; 7) screen_performance "$name";; r|R) screen_repair "$name";;
      s|S) speed_screen "$name" ;;
      8) RESTART_EVERY="$(pick_restart)"; write_meta "$TUN_DIR/$name"; set_restart_timer "$name" "$RESTART_EVERY"; regen_pair_if_server "$name"; ok "scheduled restart: $RESTART_EVERY"; pause;;
      9) header "CONFIG - $name"; top; kv "name" "$W$NAME$N"; kv "role" "$W$ROLE$N"; [ "$ROLE" = server ] && kv "endpoint" "$W$PUB_IP$N" || kv "endpoint" "$W$PEER_IP$N"; kv "auth key" "$W$AUTH_KEY$N"; kv "encryption" "$W$ENCRYPT$N"; kv "enc key" "$W$([ "$ENCRYPT" = none ] && echo none || echo '********')$N"; kv "timeout" "$W$TIMEOUT$N"; kv "profile" "$W$PROFILE$N"; kv "forwards" "$W$(pretty_ports "$(ports_csv "$TUN_DIR/$name")")$N"; kv "tcp" "$W bs=$TCP_BS mw=$TCP_MW rst=$TCP_RST gz=$TCP_GZ$N"; bot; pause;;
      p|P) show_pair_code "$name"; pause;;
      e|E) local ed=nano; command -v nano >/dev/null 2>&1 || ed=vi; "$ed" "$TUN_DIR/$name/meta.conf"; if yesno "restart to apply?" y; then systemctl restart "darkicmp@$name" 2>/dev/null; fi; warn "invalid hand edits can break the tunnel"; pause;;
      d|D) ask "type tunnel name to confirm"; if [ "$ANS" = "$name" ]; then stop_tunnel_hard "$name"; set_restart_timer "$name" off; "$FW_HELPER" clear "$name" >/dev/null 2>&1 || true; rm -rf "${TUN_DIR:?}/$name"; ok "deleted"; pause; return; else bad "name mismatch"; pause; fi;;
      0|_) return;;
    esac
  done
}
screen_manage() { pick_tunnel || return; screen_manage_one "$SELECTED"; }

# ============================================================= DASHBOARD ===
screen_dashboard() {
  [ -n "$(tunnel_names)" ] || { header "DASHBOARD"; bad "no tunnels yet"; pause; return; }
  while :; do header "LIVE DASHBOARD"; top; sect "TUNNELS"; row "$(printf '%s%-10s %-3s %-18s %-7s %-3s %-6s %-6s%s' "$D" name rol endpoint uptime evt in out "$N")"; blank
    local n st ev ep ti to; while read -r n; do [ -n "$n" ] || continue; load_meta "$n"; st="$(svc_raw "$n")"; ev="$(events_since "$n" '1 hour ago')"; [ "$ROLE" = client ] && ep="$PEER_IP" || ep="$PUB_IP"; read -r ti to <<<"$(tunnel_traffic "$n")"; row "$(printf '%s %-10s %s%-3s%s %-18s %-7s %s%-3s%s %s%-6s%s %s%-6s%s' "$(dot "$st")" "${n:0:10}" "$D" "$([ "$ROLE" = client ] && echo cli || echo srv)" "$N" "${ep:0:18}" "$(svc_uptime_short "$n")" "$([ "${ev:-0}" -gt 2 ] && echo "$R" || echo "$G")" "${ev:-0}" "$N" "$L4" "$(human_bytes "$ti")" "$N" "$L6" "$(human_bytes "$to")" "$N")"; done <<<"$(tunnel_names)"
    mid; row "$(printf '%sload%s %-22s %sconnections%s %s' "$D" "$N" "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)" "$D" "$N" "$(ss -tn state established 2>/dev/null | tail -n +2 | wc -l)")"; bot; printf '\n  %s2s refresh  ·  any key to exit%s' "$D" "$N"; read -rsn1 -t 2 _ && { echo; return; }
  done
}


# ============================================================ SPEED TESTS ===
# Latency: open a TCP connection to an IRAN listen port. It travels the whole
# tunnel to the service on KHAREJ and back, so the time is the real end-to-end
# round trip - nothing extra to install, no traffic generated.
tcp_probe_ms() {
  local h="$1" p="$2" t0 t1
  t0="$(date +%s%N)"
  if timeout 4 bash -c "exec 3<>/dev/tcp/$h/$p" 2>/dev/null; then
    t1="$(date +%s%N)"; echo $(( (t1 - t0) / 1000000 ))
  else echo -1; fi
}
rep_bar() { local v="$1" max="$2" w="$3" f
  [ "${max:-0}" -le 0 ] && max=1
  f=$(( v * w / max )); [ "$f" -gt "$w" ] && f="$w"; [ "$f" -lt 0 ] && f=0
  printf '%s%s%s%s' "$L4" "$(rep '#' "$f")" "$D" "$(rep '.' $((w-f)))"
}

# ---- KHAREJ side: a throwaway data source ----------------------------------
speed_responder() {
  local port secs
  header "SPEED RESPONDER - KHAREJ"
  top; sect "WHAT THIS DOES"
  row "$(printf '%sopens a temporary port on THIS kharej server that just%s' "$D" "$N")"
  row "$(printf '%ssends zeros. IRAN pulls from it through the tunnel and%s' "$D" "$N")"
  row "$(printf '%smeasures the real throughput.%s' "$D" "$N")"
  blank
  row "$(printf '%snothing here needs re-pairing - IRAN owns the map%s' "$D" "$N")"
  bot; echo
  command -v python3 >/dev/null 2>&1 || { bad "python3 is required for the responder"; pause; return; }
  ask "responder port" "19999"; port="$ANS"
  valid_port "$port" || { bad "invalid port"; pause; return; }
  port_in_use_tcp "$port" && { bad "port $port is already in use"; pause; return; }
  ask "keep it open for how many seconds" "120"; secs="${ANS:-120}"
  [[ "$secs" =~ ^[0-9]+$ ]] || secs=120
  echo
  info "listening on 127.0.0.1:$port for ${secs}s - ctrl+c to stop early"
  dim "on IRAN: Speed test > active, and give it port $port"
  echo
  timeout "$secs" python3 - "$port" <<'PYSRV'
import socket, sys, threading
port = int(sys.argv[1])
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", port)); srv.listen(16)
chunk = b"\0" * 262144
def serve(c):
    try:
        with c:
            while True: c.sendall(chunk)
    except Exception: pass
while True:
    try:
        c, _ = srv.accept()
        threading.Thread(target=serve, args=(c,), daemon=True).start()
    except Exception: break
PYSRV
  echo; ok "responder closed"
  pause
}

speed_screen() {
  local name="$1"
  load_meta "$name"
  while :; do
    header "SPEED - $name"
    top; sect "OPTIONS"
    row "$(printf '%spassive reads the counters and disturbs nothing%s' "$D" "$N")"
    row "$(printf '%sactive pulls real data through the tunnel%s' "$D" "$N")"
    bot
    top
    item 1 "Latency" "round trip through the tunnel"
    item 2 "Passive throughput" "live user traffic"
    item 3 "Active throughput" "the ceiling - restarts it"
    item 0 "Back" ""
    bot; echo; getkey
    case "${KEYSEL:-$KEY}" in
      1) speed_latency "$name" ;;
      2) speed_passive "$name" ;;
      3) speed_active  "$name" ;;
      0|_) return ;;
      *) bad "invalid choice"; pause ;;
    esac
  done
}

speed_latency() {
  local name="$1" port ms i ok_n=0 sum=0 min=999999 max=0 prev=-1 jit=0 jn=0 d
  load_meta "$name"
  [ "$ROLE" = client ] || { bad "run this on the IRAN side"; pause; return; }
  port="$(awk -F'\t' '$1=="tcp"{print $2; exit}' "$TUN_DIR/$name/ports.list" 2>/dev/null)"
  valid_port "$port" || { bad "no tcp listen port to probe"; pause; return; }
  header "LATENCY - $name"
  info "probing ${LOCAL_BIND:-127.0.0.1}:$port through the tunnel"
  echo
  for ((i=1;i<=10;i++)); do
    ms="$(tcp_probe_ms 127.0.0.1 "$port")"
    if [ "$ms" -ge 0 ]; then
      ok_n=$((ok_n+1)); sum=$((sum+ms))
      [ "$ms" -lt "$min" ] && min="$ms"; [ "$ms" -gt "$max" ] && max="$ms"
      if [ "$prev" -ge 0 ]; then d=$((ms-prev)); [ "$d" -lt 0 ] && d=$((-d)); jit=$((jit+d)); jn=$((jn+1)); fi
      prev="$ms"
      printf '\r  probe %2d/10   %s%s ms%s      ' "$i" "$G" "$ms" "$N"
    else printf '\r  probe %2d/10   %sfailed%s      ' "$i" "$R" "$N"; fi
    sleep 0.3
  done
  echo; echo
  top; sect "RESULT"; blank
  if [ "$ok_n" -eq 0 ]; then
    row "$(printf '%severy probe failed - the tunnel is not passing data%s' "$R" "$N")"
  else
    kv "latency" "$W$((sum/ok_n)) ms$N  $D min $min  max $max$N"
    [ "$jn" -gt 0 ] && kv "jitter" "$W$((jit/jn)) ms$N"
    kv "loss"    "$(if [ "$ok_n" -eq 10 ]; then printf '%s0%%%s' "$G" "$N"; else printf '%s%d%%%s' "$R" $(( (10-ok_n)*10 )) "$N"; fi)"
    kv ""        "$(rep_bar "$((sum/ok_n))" 300 34)$N"
    blank
    row "$(printf '%sicmp is rate limited by routers - high jitter is normal%s' "$D" "$N")"
  fi
  bot; pause
}

speed_passive() {
  local name="$1" win i1 o1 i2 o2 din dout
  header "PASSIVE THROUGHPUT - $name"
  read -r i1 o1 <<<"$(tunnel_traffic "$name")"
  ask "sample for how many seconds" "10"; win="${ANS:-10}"
  [[ "$win" =~ ^[0-9]+$ ]] && [ "$win" -ge 2 ] || win=10
  info "sampling for ${win}s"
  sleep "$win"
  read -r i2 o2 <<<"$(tunnel_traffic "$name")"
  din=$(( (i2 - i1) / win )); dout=$(( (o2 - o1) / win ))
  [ "$din" -lt 0 ] && din=0; [ "$dout" -lt 0 ] && dout=0
  echo; top; sect "RESULT"; blank
  kv "down now"  "$W$(human_bytes "$din")/s$N   $D$(( din * 8 / 1000000 )) Mbps$N"
  kv "up now"    "$W$(human_bytes "$dout")/s$N   $D$(( dout * 8 / 1000000 )) Mbps$N"
  kv "total in"  "$W$(human_bytes "$i2")$N"
  kv "total out" "$W$(human_bytes "$o2")$N"
  blank
  row "$(printf '%sreal user traffic, not a benchmark%s' "$D" "$N")"
  row "$(printf '%scounters reset when the tunnel restarts%s' "$D" "$N")"
  bot; pause
}

speed_active() {
  local name="$1" dir="$TUN_DIR/$1" rport lport secs added=0 bytes rate
  load_meta "$name"
  [ "$ROLE" = client ] || { bad "run this on the IRAN side"; pause; return; }
  header "ACTIVE THROUGHPUT - $name"
  top; sect "BEFORE YOU START"
  row "$(printf '%s1. on KHAREJ run Diagnostics > Speed responder%s' "$Y" "$N")"
  row "$(printf '%s2. this adds a temporary forward and RESTARTS the tunnel%s' "$Y" "$N")"
  row "$(printf '%s   connected users drop for a moment%s' "$D" "$N")"
  bot; echo
  yesno "the responder is running on kharej and you accept the restart?" n || return
  ask "responder port on kharej" "19999"; rport="$ANS"
  valid_port "$rport" || { bad "invalid port"; pause; return; }
  ask "temporary IRAN listen port" "$rport"; lport="$ANS"
  valid_port "$lport" || { bad "invalid port"; pause; return; }
  port_in_use_tcp "$lport" && { bad "$lport is already in use on IRAN"; pause; return; }
  ask "measure for how many seconds" "10"; secs="${ANS:-10}"
  [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -ge 3 ] || secs=10

  # cleanup helper: remove the temporary port entry and restart the tunnel.
  # called both on normal exit and on interrupt so the temp forward is never
  # left behind by a Ctrl+C.
  _speed_active_cleanup() {
    [ "$added" -eq 1 ] || return 0
    added=0
    awk -F'\t' -v lp="$lport" '!($1=="tcp" && $2==lp)' \
        "$dir/ports.list" > "$dir/ports.tmp" 2>/dev/null \
      && mv -f "$dir/ports.tmp" "$dir/ports.list"
    systemctl restart "darkicmp@$name" 2>/dev/null; sleep 2
    dim "temporary forward removed and the tunnel restored"
  }
  trap '_speed_active_cleanup; trap - INT TERM' INT TERM

  printf 'tcp\t%s\t127.0.0.1:%s\n' "$lport" "$rport" >> "$dir/ports.list"; added=1
  systemctl restart "darkicmp@$name" 2>/dev/null; sleep 3
  ok "temporary forward $lport -> 127.0.0.1:$rport added"

  info "pulling data through the tunnel for ${secs}s"
  bytes="$(timeout $((secs+4)) bash -c '
      exec 3<>/dev/tcp/127.0.0.1/'"$lport"' || exit 1
      timeout '"$secs"' cat <&3 2>/dev/null | wc -c' 2>/dev/null)"
  bytes="${bytes:-0}"

  _speed_active_cleanup
  trap - INT TERM

  echo; top; sect "RESULT"; blank
  if [ "${bytes:-0}" -lt 1024 ]; then
    row "$(printf '%sno data came through%s' "$R" "$N")"; blank
    row "$(printf '%s  - is the responder still running on kharej?%s' "$D" "$N")"
    row "$(printf '%s  - does it listen on 127.0.0.1:%s there?%s' "$D" "$rport" "$N")"
  else
    rate=$(( bytes / secs ))
    kv "transferred" "$W$(human_bytes "$bytes")$N in ${secs}s"
    kv "throughput"  "$W$(human_bytes "$rate")/s$N   $D$(( rate * 8 / 1000000 )) Mbps$N"
    kv ""            "$(rep_bar $(( rate * 8 / 1000000 )) 100 34)$N"
    blank
    row "$(printf '%sicmp tunnels are slow by nature - tens of Mbps is normal%s' "$D" "$N")"
  fi
  bot; pause
}

# ============================================================ DIAGNOSTICS ==
first_tcp_port() {
  local name="$1" proto p target
  while IFS=$'\t' read -r proto p target; do [ "$proto" = tcp ] && { echo "$p"; return; }; done < "$TUN_DIR/$name/ports.list"
}
tcp_probe_ms_local() {
  local port="$1" t0 t1
  t0="$(date +%s%N)"
  if timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then t1="$(date +%s%N)"; echo $(( (t1-t0)/1000000 )); else echo -1; fi
}
ping_stats() {
  local host="$1" count="${2:-8}" out loss avg mdev
  out="$(ping -4 -n -c "$count" -W 2 "$host" 2>/dev/null)" || true
  loss="$(grep -oE '[0-9]+% packet loss' <<<"$out" | head -n1 | grep -oE '[0-9]+' || echo 100)"
  avg="$(awk -F'=' '/min\/avg\/max/{gsub(/ /,"",$2); split($2,a,"/"); print int(a[2]+0.5)}' <<<"$out")"; mdev="$(awk -F'=' '/min\/avg\/max/{gsub(/ /,"",$2); split($2,a,"/"); print int(a[4]+0.5)}' <<<"$out")"
  echo "${loss:-100} ${avg:--1} ${mdev:--1}"
}
icmp_quality() {
  local name="$1"; load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "inspect or delete this tunnel from the manage screen"; pause; return; }; header "ICMP QUALITY - $name"; [ "$ROLE" = client ] || { bad "run this on the IRAN/client side"; pause; return; }
  info "probing ICMP path to $PEER_IP"; local loss avg jit; read -r loss avg jit <<<"$(ping_stats "$PEER_IP" 10)"
  local tp tms tsum=0 tok=0 i; tp="$(first_tcp_port "$name")"
  if [ -n "$tp" ]; then
    info "probing real tunnel path through local TCP/$tp"
    for i in 1 2 3 4 5; do tms="$(tcp_probe_ms_local "$tp")"; [ "$tms" -ge 0 ] 2>/dev/null && { tsum=$((tsum+tms)); tok=$((tok+1)); }; sleep 0.2; done
  fi
  top; sect "LINK"; blank; kv "peer" "$W$PEER_IP$N"; kv "icmp latency" "$W$([ "$avg" -ge 0 ] 2>/dev/null && echo "$avg ms" || echo unavailable)$N"; kv "icmp jitter" "$W$([ "$jit" -ge 0 ] 2>/dev/null && echo "$jit ms" || echo n/a)$N"; kv "icmp loss" "$([ "$loss" -eq 0 ] && printf '%s0%%%s' "$G" "$N" || printf '%s%s%%%s' "$Y" "$loss" "$N")"
  [ -n "$tp" ] && kv "tunnel RTT" "$W$([ "$tok" -gt 0 ] && echo "$((tsum/tok)) ms  ($tok/5 ok)" || echo failed)$N"
  blank
  if [ "$tok" -gt 0 ]; then row "$(printf '%sreal TCP traffic is passing through the ICMP tunnel%s' "$G" "$N")"; elif [ -n "$tp" ]; then row "$(printf '%stunnel worker is up but the TCP forward did not answer%s' "$R" "$N")"; elif [ "$loss" -lt 100 ]; then row "$(printf '%sICMP path is reachable; no TCP forward exists for end-to-end probe%s' "$Y" "$N")"; else row "$(printf '%sregular ping failed; kernel ping replies may also be disabled%s' "$Y" "$N")"; fi; bot; echo
  top; sect "PATH PAYLOAD PROBE"; row "$(printf '%sregular ICMP probes; useful for spotting fragmentation limits%s' "$D" "$N")"; blank; local sz; for sz in 64 256 512 800; do if ping -4 -n -M do -s "$sz" -c 2 -W 2 "$PEER_IP" >/dev/null 2>&1; then row "$(printf '%s%4s bytes%s  %sPASS%s' "$W" "$sz" "$N" "$G" "$N")"; else row "$(printf '%s%4s bytes%s  %sFAIL%s' "$W" "$sz" "$N" "$R" "$N")"; fi; done; bot; pause
}

link_test() {
  local name="$1"; load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "inspect or delete this tunnel from the manage screen"; pause; return; }; header "LINK TEST - $name"; [ "$ROLE" = client ] || { bad "run this on the IRAN/client side"; pause; return; }; ask "watch seconds" "180"; local dur="$ANS"; [[ "$dur" =~ ^[0-9]+$ ]] || dur=180
  local tp; tp="$(first_tcp_port "$name")"
  info "restarting and watching service + $([ -n "$tp" ] && echo "real TCP/$tp tunnel probes" || echo "ICMP reachability")"; systemctl restart "darkicmp@$name" 2>/dev/null; local start now el fail=0 down=0 ms; start="$(date +%s)"; echo
  while :; do now="$(date +%s)"; el=$((now-start)); [ "$el" -ge "$dur" ] && break; [ "$(svc_raw "$name")" = active ] || down=$((down+1)); if [ -n "$tp" ]; then ms="$(tcp_probe_ms_local "$tp")"; [ "$ms" -ge 0 ] 2>/dev/null || fail=$((fail+1)); else ping -4 -n -c1 -W1 "$PEER_IP" >/dev/null 2>&1 || fail=$((fail+1)); fi; printf '\r  %sservice-down%s %-3d  %sprobe-fail%s %-3d  %02d:%02d   ' "$D" "$N" "$down" "$D" "$N" "$fail" $((el/60)) $((el%60)); read -rsn1 -t 2 _ && { echo; info "stopped early"; break; }; done
  echo; echo; top; sect "RESULT"; blank; kv "watched" "$W${el}s$N"; kv "service down" "$W$down samples$N"; kv "path failures" "$W$fail samples$N"; blank; if [ "$down" -eq 0 ] && [ "$fail" -eq 0 ]; then row "$(printf '%sclean during the test window%s' "$G" "$N")"; elif [ "$down" -gt 0 ]; then row "$(printf '%sthe pingtunnel client/service restarted or died%s' "$R" "$N")"; else row "$(printf '%sservice stayed up but end-to-end forwarding was unstable%s' "$Y" "$N")"; fi; bot; pause
}

screen_speed() {
  local name="$1"; load_meta "$name" || { bad "cannot read $TUN_DIR/$name/meta.conf"; dim "inspect or delete this tunnel from the manage screen"; pause; return; }; header "SPEED + LATENCY - $name"; [ "$(svc_raw "$name")" = active ] || { bad "tunnel is not running"; pause; return; }
  local tp="" i ms okn=0 sum=0 min=999999 max=0 prev=-1 jit=0 jn=0 d
  [ "$ROLE" = client ] && tp="$(first_tcp_port "$name")"
  if [ -n "$tp" ]; then
    info "measuring real end-to-end RTT through TCP/$tp"
    for i in 1 2 3 4 5 6; do ms="$(tcp_probe_ms_local "$tp")"; if [ "$ms" -ge 0 ] 2>/dev/null; then okn=$((okn+1)); sum=$((sum+ms)); [ "$ms" -lt "$min" ] && min="$ms"; [ "$ms" -gt "$max" ] && max="$ms"; if [ "$prev" -ge 0 ]; then d=$((ms-prev)); [ "$d" -lt 0 ] && d=$((-d)); jit=$((jit+d)); jn=$((jn+1)); fi; prev="$ms"; fi; sleep 0.2; done
  fi
  info "sampling live traffic for 8 seconds"; local i1 o1 i2 o2 din dout; read -r i1 o1 <<<"$(tunnel_traffic "$name")"; sleep 8; read -r i2 o2 <<<"$(tunnel_traffic "$name")"; din=$(( (i2-i1)/8 )); dout=$(( (o2-o1)/8 )); [ "$din" -lt 0 ] && din=0; [ "$dout" -lt 0 ] && dout=0
  top; sect "RESULT"; blank; if [ "$okn" -gt 0 ]; then kv "tunnel RTT" "$W$((sum/okn)) ms$N  $D min $min / max $max$N"; [ "$jn" -gt 0 ] && kv "jitter" "$W$((jit/jn)) ms$N"; kv "probe loss" "$W$(( (6-okn)*100/6 ))%$N"; elif [ "$ROLE" = client ]; then kv "tunnel RTT" "$R unavailable$N"; fi; kv "down now" "$W$(human_bytes "$din")/s$N  $D$((din*8/1000000)) Mbps$N"; kv "up now" "$W$(human_bytes "$dout")/s$N  $D$((dout*8/1000000)) Mbps$N"; blank; row "$(printf '%sthroughput is live user traffic, not a generated benchmark%s' "$D" "$N")"; bot; pause
}

fingerprint_line() {
  local name="$1" ah eh; load_meta "$name" >/dev/null 2>&1 || return 1; ah="$(printf '%s' "$AUTH_KEY" | sha256sum | cut -c1-10)"; eh="$(printf '%s' "$ENC_KEY" | sha256sum | cut -c1-10)"; printf 'enc=%s auth=%s ekey=%s timeout=%s core=%s' "$ENCRYPT" "$ah" "$eh" "$TIMEOUT" "$(core_version_short)"
}
screen_fingerprint() {
  header "CONFIG FINGERPRINT"; top; sect "MUST MATCH END TO END"; row "$(printf '%sauth + encryption settings must match on both servers%s' "$D" "$N")"; row "$(printf '%ssecrets are hashed; raw keys are not printed%s' "$D" "$N")"; bot; echo; local n; while read -r n; do [ -n "$n" ] || continue; load_meta "$n"; printf '  %s%-12s%s %s(%s)%s\n' "$W" "$n" "$N" "$D" "$ROLE" "$N"; printf '  %s%s%s\n\n' "$C" "$(fingerprint_line "$n")" "$N"; done <<<"$(tunnel_names)"; pause
}
health_check() {
  header "HEALTH CHECK"; [ -x "$BIN_PATH" ] && ok "core installed: $(core_version_short)" || bad "core missing"; core_supports_encrypt && ok "encryption-capable core" || warn "core does not advertise encryption"; [ -f "$UNIT_FILE" ] && ok "systemd template" || bad "systemd template missing"; command -v ping >/dev/null 2>&1 && ok "ping utility" || bad "ping missing"; command -v iptables >/dev/null 2>&1 && ok "iptables" || bad "iptables missing"
  local n proto p target miss; while read -r n; do [ -n "$n" ] || continue; echo; printf '  %s%s%s\n' "$D" "$(rep '─' $((UIW+2)))" "$N"; load_meta "$n"; printf '  %s%s%s %s(%s)%s\n' "$W" "$n" "$N" "$D" "$ROLE" "$N"; [ "$(svc_raw "$n")" = active ] && ok "service active" || bad "service not active"; systemctl is-enabled --quiet "darkicmp@$n" 2>/dev/null && ok "enabled on boot" || warn "not enabled on boot"; if [ "$ROLE" = client ]; then ping -4 -n -c1 -W2 "$PEER_IP" >/dev/null 2>&1 && ok "kharej answers regular ICMP" || warn "regular ping unavailable (may be intentionally disabled)"; miss=0; while IFS=$'\t' read -r proto p target; do if [ "$proto" = tcp ]; then ss -tln 2>/dev/null | grep -qE "[:.]$p\\b" || { bad "tcp $p not listening"; miss=1; }; else ss -uln 2>/dev/null | grep -qE "[:.]$p\\b" || { bad "udp $p not listening"; miss=1; }; fi; done < "$TUN_DIR/$n/ports.list"; [ "$miss" -eq 0 ] && ok "all forward ports listening"; local hp hm; hp="$(first_tcp_port "$n")"; if [ -n "$hp" ]; then hm="$(tcp_probe_ms_local "$hp")"; [ "$hm" -ge 0 ] 2>/dev/null && ok "real tunnel TCP probe: ${hm}ms" || bad "real tunnel TCP probe failed"; fi; else ok "kharej ICMP server profile"; fi; local ev; ev="$(events_since "$n" '1 hour ago')"; [ "${ev:-0}" -eq 0 ] && ok "no error events in last hour" || warn "$ev error event(s) in last hour"; done <<<"$(tunnel_names)"; echo
}
screen_firewall() {
  header "FIREWALL"; local n; while read -r n; do [ -n "$n" ] || continue; printf '  %s%s%s\n' "$W" "$n" "$N"; iptables -w 5 -L INPUT -v -n --line-numbers 2>/dev/null | grep "darkicmp-$n" | sed 's/^/    IN  /'; iptables -w 5 -L OUTPUT -v -n --line-numbers 2>/dev/null | grep "darkicmp-$n" | sed 's/^/    OUT /'; done <<<"$(tunnel_names)"; pause
}
screen_diag() {
  while :; do header "DIAGNOSTICS"; top; sect "LOGS"; blank; item 1 "Live log" ""; item 2 "Last 60 lines" ""; mid; sect "TESTS"; item 3 "Health check" "all tunnels"; item 4 "ICMP quality" "latency / jitter / loss / payload"; item 5 "Link test" "stability window"; item s "Speed + latency" "live traffic"; item 6 "Config fingerprint" "compare both servers"; mid; sect "SYSTEM"; item f "Firewall rules" ""; item r "Speed responder" "run on kharej"
    item l "Toggle debug logs" ""; item 0 "Back" ""; bot; echo; getkey
    case "$KEYSEL" in
      1) pick_tunnel && { clear; info "ctrl+c to exit"; journalctl -u "darkicmp@$SELECTED" -f -n 30 --no-pager; }; pause;;
      2) pick_tunnel && { header "LOG - $SELECTED"; journalctl -u "darkicmp@$SELECTED" -n 60 --no-pager -o cat | sed 's/^/    /'; }; pause;;
      3) health_check; pause;; 4) pick_tunnel && icmp_quality "$SELECTED";; 5) pick_tunnel && link_test "$SELECTED";; s|S) pick_tunnel && screen_speed "$SELECTED";; 6) screen_fingerprint;; f|F) screen_firewall;;
      r|R) speed_responder ;;
      l|L) pick_tunnel || continue; load_meta "$SELECTED"; [ "$LOGLEVEL" = debug ] && LOGLEVEL=warn || LOGLEVEL=debug; write_meta "$TUN_DIR/$SELECTED"; systemctl restart "darkicmp@$SELECTED" 2>/dev/null; ok "log level: $LOGLEVEL"; pause;;
      0|_) return;;
    esac
  done
}

# ================================================================= UPDATE ==
update_script() {
  local url tmp nv; url="$(cat "$UPDATE_URL_FILE" 2>/dev/null)"; [ -n "$url" ] || { bad "no source url set"; return; }; tmp="$(mktemp)"; info "downloading"; curl -fsSL --retry 3 --max-time 60 -o "$tmp" "$url" || { bad "download failed"; rm -f "$tmp"; return; }; grep -q 'DARKVPN-ICMPPRO-SCRIPT' "$tmp" || { bad "not a Dark ICMP Pro script - aborted"; rm -f "$tmp"; return; }; bash -n "$tmp" 2>/dev/null || { bad "syntax errors - aborted"; rm -f "$tmp"; return; }; nv="$(grep -m1 '^SCRIPT_VER=' "$tmp" | cut -d'"' -f2)"; cp -f "$SELF_PATH" "$SELF_PATH.bak" 2>/dev/null; install -m 0755 "$tmp" "$SELF_PATH"; rm -f "$tmp"; ok "updated to v${nv:-?} - backup at $SELF_PATH.bak"; sleep 1; exec bash "$SELF_PATH"
}
screen_update() {
  while :; do header "UPDATE"; top; sect "VERSIONS"; blank; kv "core" "$W$(core_version_short)$N"; kv "script" "$W v$SCRIPT_VER$N"; kv "source" "$D$(cat "$UPDATE_URL_FILE" 2>/dev/null || echo 'not set')$N"; mid; item 1 "Core" "install / update pingtunnel"; item 2 "Update script" "from source url"; item 3 "Set source url" ""; item 4 "Install as command" "run: icmppro"; item 0 "Back" ""; bot; echo; getkey; case "$KEYSEL" in 1) screen_core;; 2) update_script; pause;; 3) ask "raw url"; [ -n "$ANS" ] && { echo "$ANS" > "$UPDATE_URL_FILE"; ok "saved"; }; pause;; 4) install -m 0755 "$SELF_PATH" /usr/local/bin/icmppro && ok "run: icmppro" || bad "failed"; pause;; 0|_) return;; esac; done
}
screen_uninstall() {
  header "UNINSTALL"; warn "removes every DARK ICMP tunnel, service, firewall rule and core binary"; echo; ask "type UNINSTALL to confirm"; [ "$ANS" = UNINSTALL ] || { info "cancelled"; pause; return; }; local n; while read -r n; do [ -n "$n" ] || continue; stop_tunnel_hard "$n"; set_restart_timer "$n" off; "$FW_HELPER" clear "$n" >/dev/null 2>&1 || true; done <<<"$(tunnel_names)"; rm -f "$UNIT_FILE" "$RS_UNIT" "$RS_TIMER" "$RUNNER" "$FW_HELPER"; systemctl daemon-reload 2>/dev/null; rm -f "$BIN_PATH" "$BIN_PATH.bak"; rm -rf "$BASE_DIR"; ok "uninstalled"; pause; exit 0
}

# =============================================================== MAIN MENU ==
main_menu() {
  while :; do header; local tot run tin=0 tout=0 n a b; tot="$(tunnel_count)"; run="$(systemctl list-units 'darkicmp@*' --state=running --no-legend 2>/dev/null | grep -c .)"; while read -r n; do [ -n "$n" ] || continue; read -r a b <<<"$(tunnel_traffic "$n")"; tin=$((tin+${a:-0})); tout=$((tout+${b:-0})); done <<<"$(tunnel_names)"
    top; row "$(printf '%s%s%s tunnels   %s%s%s running   %s%s in%s / %s%s out%s' "$W$BD" "$tot" "$N" "$G$BD" "$run" "$N" "$L4" "$(human_bytes "$tin")" "$N" "$L6" "$(human_bytes "$tout")" "$N")"; mid; sect "SETUP"; item 1 "Core" "install / update pingtunnel"; item 2 "New tunnel - KHAREJ" "STEP 1 - make Pair Code"; item 3 "New tunnel - IRAN" "STEP 2 - paste Pair Code"; mid; sect "OPERATE"; item 4 "Manage tunnels" "ports, security, endpoint"; item 5 "Dashboard" ""; item 6 "Diagnostics" "logs and tests"; mid; sect "MAINTENANCE"; item 7 "Update" ""; item 8 "Uninstall" ""; item 0 "Exit" ""; bot; echo; getkey
    case "$KEYSEL" in 1) screen_core;; 2) screen_new_kharej;; 3) screen_new_iran;; 4) screen_manage;; 5) screen_dashboard;; 6) screen_diag;; 7) screen_update;; 8) screen_uninstall;; 0|q|Q) clear; printf '  %sDARK VPN - ICMP Pro%s  %s%s%s\n\n' "$C" "$N" "$D" "$DEV_ID" "$N"; exit 0;; esac
  done
}

need_root
trap on_interrupt INT TERM

install_deps
ensure_dirs
ensure_units
[ -x "$RUNNER" ] || write_runner
[ -x "$FW_HELPER" ] || write_fw_helper
sweep_partials
main_menu

#!/usr/bin/env bash
# Xray + VLESS + REALITY server deploy script for Debian/Ubuntu.
#
# Usage:
#   sudo bash setup.sh
#   sudo SERVER_NAME=your.domain.com REALITY_TARGET=www.microsoft.com:443 bash setup.sh
#
# Important variables:
#   SERVER_NAME     Public hostname/IP clients connect to. Auto-detected if empty.
#   PORT            Xray listen port. Default: 443
#   UUID            VLESS user UUID. Auto-generated if empty.
#   REALITY_TARGET  REALITY camouflage target, host:port. Default: www.microsoft.com:443
#   REALITY_SNI     Client SNI / serverNames entry. Default: host part of REALITY_TARGET
#   SHORT_ID        REALITY shortId, even hex up to 16 chars. Auto-generated if empty.

set -Eeuo pipefail

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG="${XRAY_CONFIG_DIR}/config.json"
XRAY_SERVICE="xray"

PORT="${PORT:-443}"
REALITY_TARGET="${REALITY_TARGET:-www.microsoft.com:443}"
REALITY_SNI="${REALITY_SNI:-${REALITY_TARGET%%:*}}"
FLOW="${FLOW:-xtls-rprx-vision}"
FINGERPRINT="${FINGERPRINT:-chrome}"
SPIDER_X="${SPIDER_X:-/}"

log() {
  printf '[xray-reality] %s\n' "$*"
}

fail() {
  printf '[xray-reality] ERROR: %s\n' "$*" >&2
  exit 1
}

need_root() {
  if [ "${EUID}" -ne 0 ]; then
    fail "please run as root, for example: sudo bash setup.sh"
  fi
}

detect_os() {
  if ! command -v apt-get >/dev/null 2>&1; then
    fail "this script currently supports Debian/Ubuntu systems with apt-get"
  fi
}

validate_inputs() {
  case "${PORT}" in
    ''|*[!0-9]*)
      fail "PORT must be a number"
      ;;
  esac
  if [ "${PORT}" -lt 1 ] || [ "${PORT}" -gt 65535 ]; then
    fail "PORT must be between 1 and 65535"
  fi
  if ! printf '%s' "${REALITY_TARGET}" | grep -Eq '^[^:]+:[0-9]+$'; then
    fail "REALITY_TARGET must use host:port format, for example www.microsoft.com:443"
  fi
  if [ -z "${REALITY_SNI}" ]; then
    fail "REALITY_SNI cannot be empty"
  fi
}

install_packages() {
  log "installing dependencies"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    openssl \
    procps \
    uuid-runtime
}

install_xray() {
  log "installing/upgrading Xray with the official XTLS installer"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  [ -x "${XRAY_BIN}" ] || fail "xray binary not found at ${XRAY_BIN}"
}

detect_server_name() {
  if [ -n "${SERVER_NAME:-}" ]; then
    printf '%s' "${SERVER_NAME}"
    return
  fi

  local ip
  ip="$(curl -fsS4 --max-time 8 https://api.ipify.org || true)"
  if [ -z "${ip}" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  [ -n "${ip}" ] || fail "could not detect SERVER_NAME; rerun with SERVER_NAME=your.domain.com"
  printf '%s' "${ip}"
}

generate_uuid() {
  if [ -n "${UUID:-}" ]; then
    printf '%s' "${UUID}"
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    "${XRAY_BIN}" uuid
  fi
}

generate_short_id() {
  if [ -n "${SHORT_ID:-}" ]; then
    case "${SHORT_ID}" in
      *[!0-9a-fA-F]*)
        fail "SHORT_ID must be hex"
        ;;
    esac
    if [ $(( ${#SHORT_ID} % 2 )) -ne 0 ] || [ "${#SHORT_ID}" -gt 16 ]; then
      fail "SHORT_ID length must be even and no longer than 16 hex chars"
    fi
    printf '%s' "${SHORT_ID}"
  else
    openssl rand -hex 8
  fi
}

generate_reality_keys() {
  local key_output
  key_output="$("${XRAY_BIN}" x25519)"
  PRIVATE_KEY="$(printf '%s\n' "${key_output}" | awk -F': ' '/Private key/ {print $2}')"
  PUBLIC_KEY="$(printf '%s\n' "${key_output}" | awk -F': ' '/Public key/ {print $2}')"
  [ -n "${PRIVATE_KEY}" ] && [ -n "${PUBLIC_KEY}" ] || fail "failed to generate REALITY x25519 keys"
}

backup_existing_config() {
  if [ -f "${XRAY_CONFIG}" ]; then
    local backup
    backup="${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    log "backing up existing config to ${backup}"
    cp "${XRAY_CONFIG}" "${backup}"
  fi
}

write_config() {
  log "writing ${XRAY_CONFIG}"
  mkdir -p "${XRAY_CONFIG_DIR}" /var/log/xray

  tee "${XRAY_CONFIG}" >/dev/null <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID_VALUE}",
            "flow": "${FLOW}",
            "email": "vless-reality"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${REALITY_TARGET}",
          "xver": 0,
          "serverNames": [
            "${REALITY_SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID_VALUE}"
          ],
          "fingerprint": "${FINGERPRINT}"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
}

enable_bbr() {
  log "enabling BBR when supported"
  tee /etc/sysctl.d/99-xray-bbr.conf >/dev/null <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  sysctl --system >/dev/null || true
}

restart_xray() {
  log "testing Xray config"
  "${XRAY_BIN}" run -test -config "${XRAY_CONFIG}"

  log "starting Xray service"
  systemctl daemon-reload
  systemctl enable --now "${XRAY_SERVICE}"
  systemctl restart "${XRAY_SERVICE}"
  systemctl --no-pager --full status "${XRAY_SERVICE}" >/dev/null
}

print_result() {
  local encoded_spider
  encoded_spider="${SPIDER_X//\//%2F}"

  cat <<EOF

Done.

Server:
  Address: ${SERVER_NAME_VALUE}
  Port:    ${PORT}

Client parameters:
  Protocol:     vless
  UUID:         ${UUID_VALUE}
  Flow:         ${FLOW}
  Security:     reality
  Network:      tcp/raw
  SNI:          ${REALITY_SNI}
  Public key:   ${PUBLIC_KEY}
  Short ID:     ${SHORT_ID_VALUE}
  Fingerprint:  ${FINGERPRINT}
  SpiderX:      ${SPIDER_X}

VLESS URI:
vless://${UUID_VALUE}@${SERVER_NAME_VALUE}:${PORT}?encryption=none&security=reality&sni=${REALITY_SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID_VALUE}&type=tcp&flow=${FLOW}&spx=${encoded_spider}#xray-reality

If the server has a firewall or cloud security group, allow TCP ${PORT}.
EOF
}

main() {
  need_root
  detect_os
  validate_inputs
  install_packages
  install_xray

  SERVER_NAME_VALUE="$(detect_server_name)"
  UUID_VALUE="$(generate_uuid)"
  SHORT_ID_VALUE="$(generate_short_id)"
  generate_reality_keys

  backup_existing_config
  write_config
  enable_bbr
  restart_xray
  print_result
}

main "$@"

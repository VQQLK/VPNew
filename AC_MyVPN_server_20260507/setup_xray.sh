#!/bin/bash
# ============================================================
# Xray VLESS + XTLS-Reality Server Setup (Совершенная версия)
# OS: Ubuntu 20.04 / 22.04 / Debian 11+
# Run as root: sudo bash setup_xray.sh
#
# Поддерживает:
# - Транспорт: TCP или gRPC (HTTP/2) для маскировки
# - Роль сервера: конечный или промежуточный (relay)
# - Onering-подобную защиту: fallback с проверкой SNI
# - Защиту iptables, cron-мониторинг, автоопределение IP
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[ "$EUID" -ne 0 ] && err "Запустите скрипт от root: sudo bash $0"

# ── Внешний IP ─────────────────────────────────────────────
SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null)
[ -z "$SERVER_IP" ] && read -rp "Введите внешний IP сервера вручную: " SERVER_IP

# ── Базовые настройки Reality ──────────────────────────────
XRAY_PORT=443
REALITY_DEST="www.microsoft.com:443"
REALITY_SNI="www.microsoft.com"
REALITY_FINGERPRINT="chrome"
XRAY_CONFIG_DIR="/etc/xray"
OUTPUT_DIR="/etc/xray/clients"

log "Сервер: $SERVER_IP Порт: $XRAY_PORT"

# ── Выбор роли сервера ─────────────────────────────────────
echo ""
echo "========================================="
echo "  Выберите роль этого сервера:"
echo "========================================="
echo "  1) Конечный (Exit) — трафик напрямую в интернет"
echo "  2) Промежуточный (Entry/Relay) — проброс на другой сервер"
echo "========================================="
while true; do
    read -rp "Ваш выбор [1 или 2]: " ROLE_CHOICE
    case "$ROLE_CHOICE" in
        1) SERVER_ROLE="exit"; break;;
        2) SERVER_ROLE="relay"; break;;
        *) warn "Пожалуйста, введите 1 или 2";;
    esac
done

if [ "$SERVER_ROLE" = "relay" ]; then
    echo ""
    log "Настройка промежуточного сервера (Relay)..."
    read -rp "IP-адрес Exit-сервера: " EXIT_IP
    read -rp "Порт Exit-сервера [443]: " EXIT_PORT
    EXIT_PORT=${EXIT_PORT:-443}
    read -rp "UUID Exit-сервера: " EXIT_UUID
    read -rp "Публичный ключ Reality Exit-сервера: " EXIT_PUBKEY
    read -rp "Short ID Exit-сервера: " EXIT_SID
    read -rp "SNI домен Exit-сервера [$REALITY_SNI]: " EXIT_SNI
    EXIT_SNI=${EXIT_SNI:-$REALITY_SNI}
    read -rp "Fingerprint Exit-сервера [$REALITY_FINGERPRINT]: " EXIT_FP
    EXIT_FP=${EXIT_FP:-$REALITY_FINGERPRINT}
fi

# ── Выбор транспорта ───────────────────────────────────────
echo ""
echo "========================================="
echo "  Выберите тип транспорта:"
echo "========================================="
echo "  1) TCP (классический, совместимость)"
echo "  2) gRPC (HTTP/2) — маскировка под обычный веб, обходит DPI"
echo "========================================="
while true; do
    read -rp "Ваш выбор [1 или 2]: " TRANSPORT_CHOICE
    case "$TRANSPORT_CHOICE" in
        1) TRANSPORT="tcp"; break;;
        2) TRANSPORT="grpc"; break;;
        *) warn "Пожалуйста, введите 1 или 2";;
    esac
done

if [ "$TRANSPORT" = "grpc" ]; then
    read -rp "Service name для gRPC [default]: " GRPC_SERVICE
    GRPC_SERVICE=${GRPC_SERVICE:-default}
fi

# ── Настройка Onering-подобной защиты ──────────────────────
echo ""
echo "========================================="
echo "  Включить Onering-подобную защиту?"
echo "  (проверка специального SNI для обхода зондов)"
echo "========================================="
read -rp "Включить? [y/N]: " ONERING_ENABLE
if [[ "$ONERING_ENABLE" =~ ^[Yy]$ ]]; then
    ONERING_ACTIVE=true
    read -rp "Введите ваш основной домен (или любой уникальный идентификатор): " ONERING_DOMAIN
    read -rp "Введите домен-прикрытие (например, www.google.com): " ONERING_COVER
else
    ONERING_ACTIVE=false
fi

# ── 1. Установка Xray-core ─────────────────────────────────
log "Устанавливаем Xray-core..."
apt-get update -qq
apt-get install -y curl unzip uuid-runtime

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

XRAY_BIN="/usr/local/bin/xray"
[ -f "$XRAY_BIN" ] || err "Xray не установился."
log "Xray версия: $($XRAY_BIN version | head -1)"

# ── 2. Генерация ключей ────────────────────────────────────
log "Генерируем криптографические параметры..."
CLIENT_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
KEYPAIR=$($XRAY_BIN x25519)
PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/Private key:/ {print $3}')
PUBLIC_KEY=$(echo "$KEYPAIR" | awk '/Public key:/ {print $3}')
SHORT_ID=$(openssl rand -hex 4)

log "UUID: $CLIENT_UUID"
log "Public key: $PUBLIC_KEY"
log "Short ID: $SHORT_ID"

# ── 3. Формирование конфига Xray ───────────────────────────
log "Создаём конфиг..."
mkdir -p "$XRAY_CONFIG_DIR"

# Outbounds
if [ "$SERVER_ROLE" = "relay" ]; then
    cat > "$XRAY_CONFIG_DIR/outbounds.json" << OUTBOUNDS
[
  {
    "tag": "relay-to-exit",
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "$EXIT_IP",
        "port": $EXIT_PORT,
        "users": [{
          "id": "$EXIT_UUID",
          "flow": "xtls-rprx-vision",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "$TRANSPORT",
      "security": "reality",
      "realitySettings": {
        "serverName": "$EXIT_SNI",
        "fingerprint": "$EXIT_FP",
        "show": false,
        "publicKey": "$EXIT_PUBKEY",
        "shortId": "$EXIT_SID",
        "spiderX": "/"
      }
    }
  },
  { "tag": "block", "protocol": "blackhole", "settings": {} }
]
OUTBOUNDS
else
    cat > "$XRAY_CONFIG_DIR/outbounds.json" << OUTBOUNDS
[
  { "tag": "direct", "protocol": "freedom", "settings": {} },
  { "tag": "block",  "protocol": "blackhole", "settings": {} }
]
OUTBOUNDS
fi

# Inbound с поддержкой транспорта и Onering
if [ "$ONERING_ACTIVE" = true ]; then
    SERVER_NAMES='["'$ONERING_DOMAIN'", "'$ONERING_COVER'"]'
else
    SERVER_NAMES='["www.microsoft.com", "www.apple.com", "www.cloudflare.com"]'
fi

if [ "$TRANSPORT" = "grpc" ]; then
    STREAM_SETTINGS=$(cat <<SETTINGS
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DEST",
          "xver": 0,
          "serverNames": $SERVER_NAMES,
          "privateKey": "$PRIVATE_KEY",
          "minClientVer": "",
          "maxTimeDiff": 60000,
          "shortIds": ["$SHORT_ID"]
        },
        "grpcSettings": {
          "serviceName": "$GRPC_SERVICE"
        }
      }
SETTINGS
)
else
    STREAM_SETTINGS=$(cat <<SETTINGS
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DEST",
          "xver": 0,
          "serverNames": $SERVER_NAMES,
          "privateKey": "$PRIVATE_KEY",
          "minClientVer": "",
          "maxTimeDiff": 60000,
          "shortIds": ["$SHORT_ID"]
        }
      }
SETTINGS
)
fi

cat > "$XRAY_CONFIG_DIR/config.json" << CONF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [{
    "tag": "vless-reality-in",
    "port": $XRAY_PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "$CLIENT_UUID",
        "flow": "xtls-rprx-vision"
      }],
      "decryption": "none"
    },
    $STREAM_SETTINGS,
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls", "quic"]
    }
  }],
  "outbounds": $(cat "$XRAY_CONFIG_DIR/outbounds.json"),
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" }
    ]
  }
}
CONF

mkdir -p /var/log/xray

# ── 4. iptables (rate-limit) ────────────────────────────────
log "Настраиваем iptables..."
if ! command -v iptables &> /dev/null; then
    apt-get update -qq && apt-get install -y iptables-persistent
fi
RULE1='INPUT -p tcp --dport 443 -m state --state NEW -m recent --set'
RULE2='INPUT -p tcp --dport 443 -m state --state NEW -m recent --update --seconds 60 --hitcount 5 -j DROP'
iptables -C $RULE1 2>/dev/null || iptables -A $RULE1
iptables -C $RULE2 2>/dev/null || iptables -A $RULE2
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
log "iptables настроен"

# ── 5. Cron-мониторинг ─────────────────────────────────────
log "Настраиваем cron-мониторинг..."
cat > /root/check-xray.sh << 'SCRIPT'
#!/bin/bash
if ! pgrep -x xray > /dev/null; then
    systemctl restart xray
fi
SCRIPT
chmod +x /root/check-xray.sh
if ! crontab -l 2>/dev/null | grep -q "/root/check-xray.sh"; then
    (crontab -l 2>/dev/null; echo "*/5 * * * * /root/check-xray.sh") | crontab -
fi
log "Cron-мониторинг добавлен"

# ── 6. Запуск сервиса ──────────────────────────────────────
log "Запускаем Xray..."
systemctl enable --now xray
sleep 2
systemctl is-active xray && log "Xray запущен!" || warn "Xray не запустился. Проверьте: journalctl -u xray"

# ── 7. Клиентский JSON-конфиг ──────────────────────────────
log "Генерируем клиентский конфиг..."
mkdir -p "$OUTPUT_DIR"
if [ "$TRANSPORT" = "grpc" ]; then
    CLIENT_STREAM=$(cat <<STREAM
        "streamSettings": {
          "network": "grpc",
          "security": "reality",
          "realitySettings": {
            "serverName": "$REALITY_SNI",
            "fingerprint": "$REALITY_FINGERPRINT",
            "show": false,
            "publicKey": "$PUBLIC_KEY",
            "shortId": "$SHORT_ID",
            "spiderX": "/"
          },
          "grpcSettings": {
            "serviceName": "$GRPC_SERVICE"
          }
        }
STREAM
)
else
    CLIENT_STREAM=$(cat <<STREAM
        "streamSettings": {
          "network": "tcp",
          "security": "reality",
          "realitySettings": {
            "serverName": "$REALITY_SNI",
            "fingerprint": "$REALITY_FINGERPRINT",
            "show": false,
            "publicKey": "$PUBLIC_KEY",
            "shortId": "$SHORT_ID",
            "spiderX": "/"
          }
        }
STREAM
)
fi

if [ "$ONERING_ACTIVE" = true ]; then
    CLIENT_SNI="$ONERING_DOMAIN"
else
    CLIENT_SNI="$REALITY_SNI"
fi

cat > "$OUTPUT_DIR/client_config.json" << CLIENT
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    { "tag": "socks-in", "port": 10808, "listen": "127.0.0.1", "protocol": "socks", "settings": { "udp": true } },
    { "tag": "http-in", "port": 10809, "listen": "127.0.0.1", "protocol": "http" }
  ],
  "outbounds": [
    {
      "tag": "vless-out",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "$SERVER_IP",
          "port": $XRAY_PORT,
          "users": [{
            "id": "$CLIENT_UUID",
            "flow": "xtls-rprx-vision",
            "encryption": "none"
          }]
        }]
      },
      $CLIENT_STREAM
    },
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block" },
      { "type": "field", "domain": ["geosite:cn"], "outboundTag": "direct" },
      { "type": "field", "ip": ["geoip:cn", "geoip:private"], "outboundTag": "direct" }
    ]
  }
}
CLIENT

# VLESS-ссылка
VLESS_LINK="vless://${CLIENT_UUID}@${SERVER_IP}:${XRAY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${CLIENT_SNI}&fp=${REALITY_FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=${TRANSPORT}&headerType=none"
if [ "$TRANSPORT" = "grpc" ]; then
    VLESS_LINK="${VLESS_LINK}&serviceName=${GRPC_SERVICE}&mode=gun"
fi
VLESS_LINK="${VLESS_LINK}#MyVPN-Reality"

cat > "$OUTPUT_DIR/vless_link.txt" << LINK
$VLESS_LINK
LINK

# ── Итог ──────────────────────────────────────────────────
echo ""
log "================================================================"
log "Установка завершена! Роль: $SERVER_ROLE, Транспорт: $TRANSPORT"
if [ "$ONERING_ACTIVE" = true ]; then
    log "Onering-защита активна. Клиентский SNI: $CLIENT_SNI"
fi
log "Клиентский конфиг: $OUTPUT_DIR/client_config.json"
log "VLESS-ссылка: $OUTPUT_DIR/vless_link.txt"
log ""
log "Параметры для клиента:"
log "  Адрес: $SERVER_IP, Порт: $XRAY_PORT, UUID: $CLIENT_UUID"
log "  Flow: xtls-rprx-vision, Security: reality"
log "  SNI: $CLIENT_SNI"
log "  Public key: $PUBLIC_KEY, Short ID: $SHORT_ID"
if [ "$TRANSPORT" = "grpc" ]; then
    log "  gRPC serviceName: $GRPC_SERVICE"
fi
echo ""

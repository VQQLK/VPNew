#!/bin/bash
# ============================================================
#  Xray VLESS + XTLS-Reality Server Setup
#  OS: Ubuntu 20.04 / 22.04 / Debian 11+
#  Run as root: sudo bash setup_xray.sh
#
#  Что делает скрипт:
#  1. Устанавливает Xray-core (официальный установщик)
#  2. Генерирует UUID, X25519-ключи, ShortID
#  3. Настраивает VLESS+XTLS-Reality на порту 443
#  4. Создаёт клиентский JSON-конфиг и VLESS-ссылку
#
#  VLESS+XTLS-Reality:
#  - Маскируется под TLS 1.3 к реальному домену (www.microsoft.com)
#  - Не имеет сигнатуры — невозможно отличить от легитимного HTTPS
#  - X25519 — эллиптическая криптография для Reality handshake
#  - XTLS Vision flow — прямая передача TLS-inner-трафика без двойного шифрования
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[ "$EUID" -ne 0 ] && err "Запустите скрипт от root: sudo bash $0"

# ── Определяем внешний IP ──────────────────────────────────
SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null)
[ -z "$SERVER_IP" ] && read -rp "Введите внешний IP сервера вручную: " SERVER_IP

XRAY_PORT=443
# SNI-домен для маскировки. Должен быть реальным TLS-сервером на порту 443.
# www.microsoft.com — крупный CDN, надёжно работает как steal-dest.
REALITY_DEST="www.microsoft.com:443"
REALITY_SNI="www.microsoft.com"
REALITY_FINGERPRINT="chrome"     # эмулируем Chrome TLS fingerprint
XRAY_CONFIG_DIR="/etc/xray"
OUTPUT_DIR="/etc/xray/clients"

log "Сервер: $SERVER_IP  Порт: $XRAY_PORT"
log "Reality SNI: $REALITY_SNI  Dest: $REALITY_DEST"

# ── 1. Установка Xray-core ─────────────────────────────────
log "Устанавливаем Xray-core..."
apt-get update -qq
apt-get install -y curl unzip uuid-runtime iptables-persistent

# Официальный установщик от XTLS-team
# Источник: https://github.com/XTLS/Xray-install
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
XRAY_BIN="/usr/local/bin/xray"
[ -f "$XRAY_BIN" ] || err "Xray не установился. Проверьте интернет-соединение."
log "Xray версия: $($XRAY_BIN version | head -1)"

# ── Systemd override ───────────────────────────────────────
log "Настраиваем systemd override..."
mkdir -p /etc/systemd/system/xray.service.d
cat > /etc/systemd/system/xray.service.d/override.conf << EOF
[Service]
Restart=always
RestartSec=3
LimitNOFILE=1048576
EOF
systemctl daemon-reload
log "Systemd override применён (Restart=always, LimitNOFILE=1048576)"

# ── 2. Генерация криптографических параметров ──────────────
log "Генерируем криптографические параметры..."

# UUID для VLESS-пользователя
CLIENT_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')

# X25519 keypair для Reality
# xray x25519 генерирует пару ключей в формате base64url
KEYPAIR=$($XRAY_BIN x25519)
PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/Private key:/ {print $3}')
PUBLIC_KEY=$(echo  "$KEYPAIR" | awk '/Public key:/  {print $3}')

# ShortID — 4 байта случайных данных в hex-представлении = 8 hex-символов
SHORT_ID=$(openssl rand -hex 4)

log "UUID:        $CLIENT_UUID"
log "Public key:  $PUBLIC_KEY"
log "Short ID:    $SHORT_ID"

# ── 3. Серверный конфиг Xray ──────────────────────────────
log "Создаём серверный конфиг..."
mkdir -p "$XRAY_CONFIG_DIR"

cat > "$XRAY_CONFIG_DIR/config.json" << CONF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error":  "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag":      "vless-reality-in",
      "port":     $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id":   "$CLIENT_UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "reality",
        "realitySettings": {
          "show":        false,
          "dest":        "$REALITY_DEST",
          "xver":        0,
          "serverNames": [
            "www.microsoft.com",
            "www.apple.com",
            "www.cloudflare.com"
          ],
          "privateKey":  "$PRIVATE_KEY",
          "minClientVer": "",
          "maxTimeDiff":  60000,
          "shortIds":    ["$SHORT_ID"]
        }
      },
      "sniffing": {
        "enabled":      true,
        "destOverride": ["http","tls","quic"]
      }
    }
  ],
  "outbounds": [
    {
      "tag":      "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag":      "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type":        "field",
        "ip":          ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
CONF

mkdir -p /var/log/xray

# ── 4. Идемпотентные iptables-правила (rate-limit port 443) ───────
log "Настраиваем iptables..."

RULE1='INPUT -p tcp --dport 443 -m state --state NEW -m recent --set'
RULE2='INPUT -p tcp --dport 443 -m state --state NEW -m recent --update --seconds 60 --hitcount 5 -j DROP'

iptables -C $RULE1 2>/dev/null || iptables -A $RULE1
iptables -C $RULE2 2>/dev/null || iptables -A $RULE2

mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

# FIX: автовосстановление iptables после ребута
# /etc/network/if-pre-up.d/ выполняется до поднятия сетевых интерфейсов
cat > /etc/network/if-pre-up.d/iptables-restore-xray << 'IPRESTORE'
#!/bin/sh
if [ -f /etc/iptables/rules.v4 ]; then
    iptables-restore < /etc/iptables/rules.v4
fi
IPRESTORE
chmod +x /etc/network/if-pre-up.d/iptables-restore-xray
log "iptables настроен (rate-limit: 5 соединений/60 сек на порт 443)"
log "iptables-restore настроен для автовосстановления после ребута"

# ── 5. Cron-мониторинг Xray ────────────────────────────────
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
log "Cron-мониторинг добавлен (каждые 5 минут)"

# ── 6. Запуск сервиса ──────────────────────────────────────
log "Запускаем Xray..."
systemctl enable --now xray
sleep 2
systemctl is-active xray && log "Xray запущен успешно!" || err "Xray не запустился. Проверьте: journalctl -u xray"

# ── 7. Генерация клиентского JSON-конфига ─────────────────
log "Генерируем клиентский конфиг..."
mkdir -p "$OUTPUT_DIR"

cat > "$OUTPUT_DIR/client_config.json" << CLIENT
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag":      "socks-in",
      "port":     10808,
      "listen":   "127.0.0.1",
      "protocol": "socks",
      "settings": { "udp": true }
    },
    {
      "tag":      "http-in",
      "port":     10809,
      "listen":   "127.0.0.1",
      "protocol": "http"
    }
  ],
  "outbounds": [
    {
      "tag":      "vless-out",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_IP",
            "port":    $XRAY_PORT,
            "users": [
              {
                "id":         "$CLIENT_UUID",
                "flow":       "xtls-rprx-vision",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network":  "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName":  "$REALITY_SNI",
          "fingerprint": "$REALITY_FINGERPRINT",
          "show":        false,
          "publicKey":   "$PUBLIC_KEY",
          "shortId":     "$SHORT_ID",
          "spiderX":     "/"
        }
      }
    },
    {
      "tag":      "direct",
      "protocol": "freedom"
    },
    {
      "tag":      "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type":        "field",
        "domain":      ["geosite:category-ads-all"],
        "outboundTag": "block"
      },
      {
        "type":        "field",
        "domain":      ["geosite:cn"],
        "outboundTag": "direct"
      },
      {
        "type":        "field",
        "ip":          ["geoip:cn","geoip:private"],
        "outboundTag": "direct"
      }
    ]
  }
}
CLIENT

# ── 8. VLESS-ссылка для мобильных клиентов ────────────────
# Также сохраняем в /root/vpn-config/ (путь для пользователей согласно инструкциям)
mkdir -p /root/vpn-config
VLESS_LINK="vless://${CLIENT_UUID}@${SERVER_IP}:${XRAY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=${REALITY_FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#MyVPN-Reality"

cat > "$OUTPUT_DIR/vless_link.txt" << LINK
$VLESS_LINK
LINK

# Копируем конфиг и ссылку в /root/vpn-config/ для удобного доступа
cp "$OUTPUT_DIR/client_config.json" /root/vpn-config/client-config.json
cp "$OUTPUT_DIR/vless_link.txt"     /root/vpn-config/vless-link.txt
log "Файлы клиента сохранены в /root/vpn-config/"

# ── Итог ──────────────────────────────────────────────────
echo ""
log "================================================================"
log "Установка завершена!"
log ""
log "Клиентский JSON конфиг:"
log "  /root/vpn-config/client-config.json"
log "  (также: $OUTPUT_DIR/client_config.json)"
log ""
log "VLESS-ссылка (для v2rayNG / Nekoray / Hiddify):"
log "  /root/vpn-config/vless-link.txt"
log ""
log "Скачать конфиг на компьютер:"
log "  scp root@$SERVER_IP:/root/vpn-config/client-config.json ."
log ""
log "Параметры для ручной настройки:"
log "  Адрес:       $SERVER_IP"
log "  Порт:        $XRAY_PORT"
log "  UUID:        $CLIENT_UUID"
log "  Flow:        xtls-rprx-vision"
log "  Security:    reality"
log "  SNI:         $REALITY_SNI"
log "  Fingerprint: $REALITY_FINGERPRINT"
log "  Public key:  $PUBLIC_KEY"
log "  Short ID:    $SHORT_ID"
log "================================================================"

# Диагностика:
echo ""
warn "Порт 443 должен быть открыт в firewall:"
warn "  ufw allow 443/tcp && ufw allow 443/udp"
warn ""
warn "Логи: journalctl -u xray -f"
warn "Статус: systemctl status xray"

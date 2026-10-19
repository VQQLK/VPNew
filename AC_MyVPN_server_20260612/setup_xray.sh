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
# ============================================================

set -e
set -o pipefail
umask 077

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ── Trap для очистки при частичном провале ───────────────────
XRAY_INSTALLED=false
CONFIG_WRITTEN=false

cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        err "Скрипт завершился с ошибкой (код $exit_code). Частичная установка может потребовать ручной очистки."
    fi
}
trap cleanup_on_error EXIT

[ "$EUID" -ne 0 ] && err "Запустите скрипт от root: sudo bash $0"

# ── Определяем внешний IP ──────────────────────────────────
SERVER_IP=$(curl -s --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null \
        || curl -s --connect-timeout 5 --max-time 10 https://ifconfig.me 2>/dev/null)
[ -z "$SERVER_IP" ] && read -rp "Введите внешний IP сервера вручную: " SERVER_IP

XRAY_PORT=443
REALITY_DEST="www.microsoft.com:443"
REALITY_SNI="www.microsoft.com"
REALITY_FINGERPRINT="chrome"
XRAY_CONFIG_DIR="/etc/xray"
OUTPUT_DIR="/etc/xray/clients"

log "Сервер: $SERVER_IP  Порт: $XRAY_PORT"
log "Reality SNI: $REALITY_SNI  Dest: $REALITY_DEST"

# ── 1. Установка Xray-core ─────────────────────────────────
log "Устанавливаем Xray-core..."
apt-get update -qq
apt-get install -y curl unzip uuid-runtime

# Официальный установщик от XTLS-team
# Версия фиксируется скриптом установки XTLS-team
log "Устанавливаем Xray (последняя стабильная версия)..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
XRAY_BIN="/usr/local/bin/xray"
[ -f "$XRAY_BIN" ] || err "Xray не установился. Проверьте интернет-соединение."

# Верификация: проверяем что бинарник запускается и возвращает версию
XRAY_VER=$($XRAY_BIN version | head -1)
[ -z "$XRAY_VER" ] && err "Xray установлен, но не запускается"
log "Xray версия: $XRAY_VER"
XRAY_INSTALLED=true

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
log "Systemd override применён"

# ── 2. Генерация криптографических параметров ──────────────
log "Генерируем криптографические параметры..."

CLIENT_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')

KEYPAIR=$($XRAY_BIN x25519)
PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/Private key:/ {print $3}')
PUBLIC_KEY=$(echo  "$KEYPAIR" | awk '/Public key:/  {print $3}')

SHORT_ID=$(openssl rand -hex 4)

# Валидация сгенерированных ключей
[ -z "$PRIVATE_KEY" ] && err "Не удалось сгенерировать приватный ключ"
[ -z "$PUBLIC_KEY" ]  && err "Не удалось сгенерировать публичный ключ"
[ -z "$CLIENT_UUID" ] && err "Не удалось сгенерировать UUID"
[ -z "$SHORT_ID" ]    && err "Не удалось сгенерировать ShortID"

log "Криптографические параметры сгенерированы."
# НЕ логируем приватный ключ — он секретен

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

# Проверяем валидность JSON
if command -v jq &>/dev/null; then
    jq empty "$XRAY_CONFIG_DIR/config.json" || err "Серверный конфиг повреждён"
fi

chmod 600 "$XRAY_CONFIG_DIR/config.json"
mkdir -p /var/log/xray
CONFIG_WRITTEN=true

# ── 4. iptables-правила (rate-limit port 443) ──────────────
log "Настраиваем firewall..."
if command -v ufw &>/dev/null; then
    ufw allow 443/tcp 2>/dev/null || true
    ufw allow 443/udp 2>/dev/null || true
    log "UFW: разрешён порт 443/tcp и 443/udp"
fi

RULE1='INPUT -p tcp --dport 443 -m state --state NEW -m recent --set'
RULE2='INPUT -p tcp --dport 443 -m state --state NEW -m recent --update --seconds 60 --hitcount 5 -j DROP'

iptables -C $RULE1 2>/dev/null || iptables -A $RULE1
iptables -C $RULE2 2>/dev/null || iptables -A $RULE2

mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

# Автовосстановление iptables после ребута
# Совместимо и с if-pre-up.d, и с systemd-netfilter
if [ -d /etc/network/if-pre-up.d ]; then
    cat > /etc/network/if-pre-up.d/iptables-restore-xray << 'IPRESTORE'
#!/bin/sh
if [ -f /etc/iptables/rules.v4 ]; then
    iptables-restore < /etc/iptables/rules.v4
fi
IPRESTORE
    chmod +x /etc/network/if-pre-up.d/iptables-restore-xray
fi

if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save 2>/dev/null || true
    log "netfilter-persistent: правила сохранены"
fi

log "iptables настроен (rate-limit: 5 соединений/60 сек на порт 443)"

# ── 5. Logrotate ───────────────────────────────────────────
log "Настраиваем logrotate..."
cat > /etc/logrotate.d/xray << 'LOGROTATE'
/var/log/xray/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGROTATE
log "Logrotate настроен (ротация каждые 7 дней)"

# ── 6. Cron-мониторинг Xray ────────────────────────────────
log "Настраиваем cron-мониторинг..."
cat > /root/check-xray.sh << 'SCRIPT'
#!/bin/bash
if ! pgrep -x xray > /dev/null; then
    systemctl restart xray
fi
SCRIPT
chmod 700 /root/check-xray.sh
if ! crontab -l 2>/dev/null | grep -q "/root/check-xray.sh"; then
    (crontab -l 2>/dev/null; echo "*/5 * * * * /root/check-xray.sh") | crontab -
fi
log "Cron-мониторинг добавлен (каждые 5 минут)"

# ── 7. Запуск сервиса ──────────────────────────────────────
log "Запускаем Xray..."
systemctl enable --now xray
sleep 2
systemctl is-active xray && log "Xray запущен успешно!" || err "Xray не запустился. Проверьте: journalctl -u xray"

# ── 8. Генерация клиентского JSON-конфига ─────────────────
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

chmod 600 "$OUTPUT_DIR/client_config.json"

# ── 9. VLESS-ссылка для мобильных клиентов ────────────────
mkdir -p /root/vpn-config
VLESS_LINK="vless://${CLIENT_UUID}@${SERVER_IP}:${XRAY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=${REALITY_FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#MyVPN-Reality"

cat > "$OUTPUT_DIR/vless_link.txt" << LINK
$VLESS_LINK
LINK

chmod 600 "$OUTPUT_DIR/vless_link.txt"

cp "$OUTPUT_DIR/client_config.json" /root/vpn-config/client-config.json
cp "$OUTPUT_DIR/vless_link.txt"     /root/vpn-config/vless-link.txt
chmod 600 /root/vpn-config/client-config.json
chmod 600 /root/vpn-config/vless-link.txt
log "Файлы клиента сохранены в /root/vpn-config/ (chmod 600)"

# ── Итог ──────────────────────────────────────────────────
echo ""
log "================================================================"
log "Установка завершена!"
log ""
log "Клиентский JSON конфиг:"
log "  /root/vpn-config/client-config.json"
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

echo ""
warn "Логи: journalctl -u xray -f"
warn "Статус: systemctl status xray"
warn "Не забудьте проверить firewall: ufw status"

# ── 10. Скрипт ротации ключей ─────────────────────────────────
log "Создаём скрипт ротации ключей..."
cat > /root/rotate-keys.sh << 'ROTATE'
#!/bin/bash
# ============================================================
#  rotate-keys.sh — Ротация X25519 ключей для Reality
#  Запуск: sudo bash /root/rotate-keys.sh
# ============================================================
set -e

XRAY_BIN="/usr/local/bin/xray"
CONFIG="/etc/xray/config.json"
CLIENT_DIR="/etc/xray/clients"

echo "[+] Генерируем новую ключевую пару..."
KEYPAIR=$($XRAY_BIN x25519)
NEW_PRIVATE=$(echo "$KEYPAIR" | awk '/Private key:/ {print $3}')
NEW_PUBLIC=$(echo "$KEYPAIR" | awk '/Public key:/ {print $3}')
NEW_SHORT_ID=$(openssl rand -hex 4)

[ -z "$NEW_PRIVATE" ] && { echo "[-] Ошибка генерации ключей"; exit 1; }

echo "[+] Обновляем серверный конфиг..."
sed -i "s/\"privateKey\":\s*\"[^\"]*\"/\"privateKey\": \"$NEW_PRIVATE\"/" "$CONFIG"
sed -i "s/\"shortIds\":\s*\[[^\]]*\]/\"shortIds\": [\"$NEW_SHORT_ID\"]/" "$CONFIG"

echo "[+] Перезапускаем Xray..."
systemctl restart xray

echo "[+] Генерируем новый клиентский конфиг..."
SERVER_IP=$(curl -s --connect-timeout 5 https://api.ipify.org)
CLIENT_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')

cat > "$CLIENT_DIR/client_config.json" << CLIENT
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    { "tag": "socks-in", "port": 10808, "listen": "127.0.0.1", "protocol": "socks", "settings": { "udp": true } },
    { "tag": "http-in", "port": 10809, "listen": "127.0.0.1", "protocol": "http" }
  ],
  "outbounds": [{
    "tag": "vless-out", "protocol": "vless",
    "settings": { "vnext": [{ "address": "$SERVER_IP", "port": 443, "users": [{ "id": "$CLIENT_UUID", "flow": "xtls-rprx-vision", "encryption": "none" }] }] },
    "streamSettings": { "network": "tcp", "security": "reality", "realitySettings": { "serverName": "www.microsoft.com", "fingerprint": "chrome", "publicKey": "$NEW_PUBLIC", "shortId": "$NEW_SHORT_ID", "spiderX": "/" } }
  }],
  "routing": { "domainStrategy": "IPIfNonMatch", "rules": [
    { "type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block" },
    { "type": "field", "domain": ["geosite:cn"], "outboundTag": "direct" },
    { "type": "field", "ip": ["geoip:cn","geoip:private"], "outboundTag": "direct" }
  ]}
}
CLIENT

VLESS_LINK="vless://${CLIENT_UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${NEW_PUBLIC}&sid=${NEW_SHORT_ID}&type=tcp&headerType=none#MyVPN-Reality"
echo "$VLESS_LINK" > "$CLIENT_DIR/vless_link.txt"

cp "$CLIENT_DIR/client_config.json" /root/vpn-config/client-config.json
cp "$CLIENT_DIR/vless_link.txt" /root/vpn-config/vless-link.txt
chmod 600 /root/vpn-config/client-config.json /root/vpn-config/vless-link.txt

echo ""
echo "[+] Ротация ключей завершена!"
echo "[+] Новый Public key: $NEW_PUBLIC"
echo "[+] Новый Short ID:  $NEW_SHORT_ID"
echo "[+] Обновите клиенты новым client-config.json"
echo "[+] VLESS-ссылка: /root/vpn-config/vless-link.txt"
ROTATE

chmod 700 /root/rotate-keys.sh
log "Скрипт ротации создан: /root/rotate-keys.sh"
log "Для ротации ключей запустите: sudo bash /root/rotate-keys.sh"

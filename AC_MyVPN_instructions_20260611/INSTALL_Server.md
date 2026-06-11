# MyVPN Server — Инструкция по установке и настройке

## Протокол: VLESS + XTLS-Reality (Xray-core)
## Серверная часть: setup_xray.sh

---

## Часть 1 — Выбор и настройка VPS

### 1.1 Требования к серверу

| Параметр | Минимум | Рекомендуется |
|---|---|---|
| ОС | Ubuntu 20.04 | Ubuntu 22.04 LTS |
| RAM | 512 MB | 1 GB |
| CPU | 1 vCPU | 1-2 vCPU |
| Диск | 10 GB | 20 GB SSD |
| Трафик | 500 GB/мес | безлимит |
| Порт 443 | открыт | открыт |

### 1.2 Рекомендуемые хостинги

| Хостинг | Цена/мес | Особенности |
|---|---|---|
| Hetzner Cloud | €3.79 | Германия, надёжный, быстрый |
| Vultr | $6 | 25+ локаций, почасовая оплата |
| DigitalOcean | $6 | Droplet, простой UI |
| Contabo | €4.99 | Много трафика, Германия/США |

> **Важно:** выбирайте сервер с IP **за пределами** страны, которую
> хотите обойти. Для России — Германия, Нидерланды, Финляндия.

### 1.3 Открытие порта 443 в панели хостинга

Порт 443 нужно открыть **дважды**: в панели хостинга И на самом сервере.

**Hetzner Cloud:**
```
Servers → ваш сервер → Networking → Firewalls → Add Rule
Direction: Inbound | Protocol: TCP | Port: 443
Direction: Inbound | Protocol: UDP | Port: 443
```

**DigitalOcean / Vultr:**
```
Networking → Firewalls → Inbound Rules
TCP: 443  |  UDP: 443
```

---

## Часть 2 — Установка сервера

### 2.1 Подключение к серверу

```bash
# С вашего компьютера:
ssh root@YOUR_SERVER_IP

# Если используете SSH-ключ:
ssh -i ~/.ssh/id_rsa root@YOUR_SERVER_IP
```

### 2.2 Загрузка и запуск скрипта

```bash
# 1. Распакуйте MyVPN_Server.zip на своём компьютере
# 2. Скопируйте setup_xray.sh на сервер:
scp setup_xray.sh root@YOUR_SERVER_IP:/root/

# 3. Подключитесь к серверу и запустите:
ssh root@YOUR_SERVER_IP
chmod +x setup_xray.sh
sudo bash setup_xray.sh
```

### 2.3 Что делает скрипт (пошагово)

```
Шаг 1: Определяет внешний IP сервера (api.ipify.org)
Шаг 2: Устанавливает Xray-core через официальный инсталлятор XTLS-team
Шаг 3: Генерирует UUID для клиента
Шаг 4: Генерирует X25519 keypair (private + public key) для Reality
Шаг 5: Генерирует ShortID (4 байта = 8 hex-символов)
Шаг 6: Создаёт /etc/xray/config.json (серверный конфиг)
Шаг 7: Запускает xray через systemd
Шаг 8: Создаёт /root/vpn-config/client-config.json
Шаг 9: Выводит VLESS-ссылку для мобильных клиентов
```

Время выполнения: **1-3 минуты**.

### 2.4 Вывод скрипта при успехе

```
[+] Xray версия: Xray 24.x.x
[+] UUID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
[+] Public key:  xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
[+] Short ID:    xxxxxxxx
[+] Xray запущен успешно!
[+] ================================================================
[+] Клиентский JSON конфиг:
[+]   /root/vpn-config/client-config.json
[+] VLESS-ссылка:
[+]   /root/vpn-config/vless-link.txt
[+] ================================================================
```

### 2.5 Открытие порта на сервере (UFW)

```bash
# Проверьте статус UFW
ufw status

# Если UFW активен — разрешите порт 443
ufw allow 443/tcp
ufw allow 443/udp
ufw reload

# Проверка:
ss -tlnp | grep 443
# Должна быть строка с xray и портом 443
```

### 2.6 Проверка автовосстановления iptables после ребута

Скрипт автоматически настраивает восстановление iptables:
- На Debian (interfaces): создаёт `/etc/network/if-pre-up.d/iptables-restore-xray`
- На systemd-netfilter: выполняет `netfilter-persistent save`

```bash
# Проверить наличие скрипта восстановления:
ls -la /etc/network/if-pre-up.d/iptables-restore-xray 2>/dev/null

# Проверить сохранённые правила:
cat /etc/iptables/rules.v4

# Проверить активные правила (после ребута):
iptables -L INPUT -n --line-numbers
```

---

## Часть 3 — Получение клиентского конфига

### 3.1 Скачивание client-config.json

```bash
# С вашего компьютера (Mac / Linux):
scp root@YOUR_SERVER_IP:/root/vpn-config/client-config.json ~/Downloads/

# Windows PowerShell:
scp root@YOUR_SERVER_IP:/root/vpn-config/client-config.json C:\Users\%USERNAME%\Downloads\

# Или через cat прямо на сервере, затем скопируйте текст:
cat /root/vpn-config/client-config.json
```

### 3.2 Альтернатива: VLESS-ссылка

VLESS-ссылка совместима с клиентами **v2rayNG** (Android), **Nekoray** (Desktop),
**Hiddify** (iOS/Android):

```bash
cat /root/vpn-config/vless-link.txt
# Формат:
# vless://UUID@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision
#   &security=reality&sni=www.microsoft.com&fp=chrome
#   &pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#MyVPN-Reality
```

Скопируйте ссылку и импортируйте в любой Xray-совместимый клиент.

---

## Часть 4 — Управление сервером

### 4.1 Основные команды

```bash
# Статус сервиса
systemctl status xray

# Запустить / остановить / перезапустить
systemctl start xray
systemctl stop xray
systemctl restart xray

# Логи в реальном времени
journalctl -u xray -f

# Последние 50 строк лога
journalctl -u xray -n 50

# Активные соединения
tail -20 /var/log/xray/access.log
```

### 4.2 Добавление нового клиента

```bash
# 1. Сгенерируйте новый UUID
uuidgen | tr '[:upper:]' '[:lower:]'
# Например: 12345678-abcd-1234-abcd-123456789012

# 2. Откройте конфиг сервера
nano /etc/xray/config.json

# 3. В секции "clients" добавьте нового пользователя:
# "clients": [
#   { "id": "СУЩЕСТВУЮЩИЙ_UUID", "flow": "xtls-rprx-vision" },
#   { "id": "НОВЫЙ_UUID",        "flow": "xtls-rprx-vision" }  ← добавить
# ]

# 4. Перезапустите Xray
systemctl restart xray

# 5. Создайте client-config.json для нового пользователя:
# Скопируйте /root/vpn-config/client-config.json
# Замените поле "id" на НОВЫЙ_UUID
```

### 4.3 Просмотр параметров текущей конфигурации

```bash
# Посмотреть UUID, Public key, Short ID
python3 -c "
import json
with open('/etc/xray/config.json') as f:
    c = json.load(f)
in0 = c['inbounds'][0]
print('UUID:', in0['settings']['clients'][0]['id'])
rs = in0['streamSettings']['realitySettings']
print('Short ID:', rs['shortIds'][0])
print('SNI:', rs['serverNames'][0])
"

# Public key — только в client-config.json:
python3 -c "
import json
with open('/root/vpn-config/client-config.json') as f:
    c = json.load(f)
rs = c['outbounds'][0]['streamSettings']['realitySettings']
print('Public key:', rs['publicKey'])
print('Short ID:', rs['shortId'])
print('SNI:', rs['serverName'])
"
```

---

## Часть 5 — Обновление Xray

```bash
# Официальный скрипт обновления (тот же, что и установки):
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Проверьте версию после обновления:
xray version

# Перезапустите сервис:
systemctl restart xray
```

---

## Часть 6 — Диагностика

### Xray не запускается

```bash
# Смотрим детальный лог ошибки
journalctl -u xray -n 30

# Проверяем синтаксис конфига
xray -test -c /etc/xray/config.json

# Порт 443 занят другим процессом?
ss -tlnp | grep 443
```

### Клиент подключается, но не работает интернет

```bash
# Проверяем ip_forward
cat /proc/sys/net/ipv4/ip_forward
# Должно быть: 1
# Если 0:
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p
```

### Проверка Reality handshake

```bash
# С клиентского компьютера (должен вернуть сертификат microsoft.com):
openssl s_client -connect YOUR_SERVER_IP:443 -servername www.microsoft.com
# В выводе должно быть: subject=CN = www.microsoft.com
# Это подтверждает что Reality корректно проксирует TLS к microsoft.com
```

---

## Архитектура XTLS-Reality

```
Клиент                    Сервер (Xray)           Реальный сайт
  │                           │                        │
  │  TLS ClientHello          │                        │
  │  SNI: www.microsoft.com ──►                        │
  │                           │  Если чужой запрос:    │
  │                           │  TCP proxy ────────────►
  │                           │  (проксируем к microsoft)
  │                           │                        │
  │  Если свой клиент         │                        │
  │  (знает Public Key+ShortID):                       │
  │  ◄── Reality handshake ──►                        │
  │                           │                        │
  │  VLESS поверх TLS 1.3     │                        │
  │  (xtls-rprx-vision flow)  │                        │
  │ ◄────────────────────────►│                        │
```

> **Примечание по `xtls-rprx-vision`:** этот flow работает только с TCP-транспортом.
> Для gRPC или WebSocket-транспорта используйте обычный flow без XTLS.
> В данном проекте используется TCP — `xtls-rprx-vision` применяется корректно.

**Ключевое свойство:** сторонний наблюдатель видит обычный TLS 1.3
к `www.microsoft.com`. Отличить реальный трафик от VPN-трафика
без знания приватного ключа — математически невозможно.

# MyVPN macOS — Инструкция по установке и настройке

## Протокол: VLESS + XTLS-Reality (Xray-core)

---

## Часть 1 — Установка сервера (если ещё не установлен)

```bash
# На VPS (Ubuntu 20.04/22.04, root):
chmod +x setup_xray.sh
sudo bash setup_xray.sh

# Скачать client_config.json на Mac:
scp root@YOUR_SERVER_IP:/root/vpn-config/client-config.json ~/Downloads/
```

Открыть порт 443 на сервере:
```bash
ufw allow 443/tcp && ufw reload
```

---

## Часть 2 — Требования

| Компонент | Версия | Ссылка |
|---|---|---|
| macOS | 13.0 Ventura+ | — |
| Xcode | 15+ | App Store / https://developer.apple.com |
| Homebrew | любая | https://brew.sh |
| xray | последняя | `brew install xray` |
| create-dmg | любая | `brew install create-dmg` |

---

## Часть 3 — Установка xray через Homebrew

```bash
# Установить Homebrew (если не установлен):
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Apple Silicon (M1/M2/M3):
brew install xray
# xray будет по пути: /opt/homebrew/bin/xray

# Intel Mac:
brew install xray
# xray будет по пути: /usr/local/bin/xray

# Проверка:
xray version
```

VPNManager.swift автоматически определяет путь к xray для обеих архитектур.

**Альтернатива без Homebrew:**
```bash
# Скачать бинарник напрямую:
# https://github.com/XTLS/Xray-core/releases → Xray-macos-arm64-v8a.zip (Apple Silicon)
#                                             → Xray-macos-64.zip         (Intel)
# Распакуйте и поместите xray в /usr/local/bin/:
sudo cp xray /usr/local/bin/
sudo chmod +x /usr/local/bin/xray
```

---

## Часть 4 — Создание Xcode проекта

### 4.1 Создание проекта

```
1. Запустите Xcode
2. File → New → Project
3. macOS → App → Next
4. Product Name: MyVPN
5. Bundle Identifier: com.myvpn.macos
6. Language: Swift
7. Interface: SwiftUI
8. Снимите галочки "Include Tests"
9. Next → выберите папку → Create
```

### 4.2 Замена файлов проекта

```
Замените сгенерированные файлы файлами из MyVPN_macOS.zip:

Xcode сгенерировал          →  Заменить на файл из архива
────────────────────────────────────────────────────────
ContentView.swift           →  macos/MyVPN/ContentView.swift
[AppName]App.swift          →  macos/MyVPN/MyVPNApp.swift
Info.plist (если есть)      →  macos/MyVPN/Info.plist
```

Добавьте новый файл VPNManager.swift:
```
File → New → File → Swift File → VPNManager.swift
Скопируйте содержимое macos/MyVPN/VPNManager.swift
```

### 4.3 Настройка Signing & Capabilities

```
1. Нажмите на проект в Navigator (левая панель)
2. Выберите таргет "MyVPN"
3. Signing & Capabilities
4. Team: выберите ваш Apple ID (или "None" для тестирования)
5. Bundle Identifier: com.myvpn.macos
```

Добавьте Capability:
```
+ Capability → "Outgoing Connections (Client)"
```

### 4.4 Настройка App Sandbox (Info.plist / entitlements)

Если Xcode создал `.entitlements` файл — добавьте разрешения:

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

---

## Часть 5 — Запуск для разработки

### 5.1 Прямой запуск из Xcode (бесплатно)

```
1. В Xcode нажмите ▶ (Run) или Cmd+R
2. Приложение запустится на вашем Mac
3. Apple ID не требуется для запуска на своём Mac
```

### 5.2 Тест подключения

```
1. Нажмите "Импорт config.json"
2. Выберите client_config.json (~/Downloads/client_config.json)
3. Нажмите "Подключить"
4. Xray запустится в фоне (пароль не требуется — networksetup
   управляет прокси без sudo для текущего пользователя)
5. Статус изменится на "● VLESS+Reality"
```

---

## Часть 6 — Сборка .dmg для распространения

### 6.1 Требования для распространения

Для распространения .dmg вне App Store нужен **Apple Developer Program** ($99/год):
- https://developer.apple.com/programs/
- Нужен для подписи кода (Developer ID) и нотаризации (Gatekeeper)

Для **личного использования** на своём Mac — Developer Program не обязателен.

### 6.2 Замените YOUR_TEAM_ID в ExportOptions.plist

```
1. Войдите на https://developer.apple.com/account
2. Membership Details → Team ID (10 символов, например: ABCD123456)
3. Откройте macos/ExportOptions.plist
4. Замените YOUR_TEAM_ID на ваш реальный Team ID
```

### 6.3 Запуск скрипта упаковки

```bash
cd macos/
chmod +x package_dmg.sh
./package_dmg.sh

# Результат: macos/dist/MyVPN-2.0.0.dmg
```

### 6.4 Нотаризация (для Gatekeeper)

```bash
# Шаг 1: Отправить на нотаризацию
xcrun notarytool submit dist/MyVPN-2.0.0.dmg \
  --apple-id  YOUR_APPLE_ID@example.com \
  --team-id   YOUR_TEAM_ID \
  --password  YOUR_APP_SPECIFIC_PASSWORD \
  --wait

# App-specific password: https://appleid.apple.com → App-Specific Passwords

# Шаг 2: Прикрепить нотаризацию к .dmg
xcrun stapler staple dist/MyVPN-2.0.0.dmg
```

---

## Часть 7 — Использование приложения

> **Важно!** Приватный ключ Reality должен оставаться только на сервере.
> Используйте публичный ключ (pbk) в VLESS-ссылке.
> Ссылка хранится на сервере: `/root/vpn-config/vless-link.txt`

### 7.1 Установка .dmg

```
1. Откройте MyVPN-2.0.0.dmg
2. Перетащите MyVPN.app в папку Applications
3. Откройте MyVPN из Applications
4. Если Gatekeeper заблокировал:
   Системные настройки → Конфиденциальность и безопасность → "Всё равно открыть"
```

### 7.2 Подключение

```
1. Импорт config.json → выберите client_config.json
2. Нажмите "Подключить"
3. Введите пароль macOS при запросе
4. Системный прокси (SOCKS5 + HTTP) выставляется автоматически
5. Все браузеры и приложения работают через VPN
```

---

## Часть 8 — Диагностика

### xray не найден
```bash
# Проверьте пути:
ls /opt/homebrew/bin/xray    # Apple Silicon
ls /usr/local/bin/xray       # Intel

# Если не установлен:
brew install xray
```

### Системный прокси не снялся
```bash
# Вручную через Terminal:
networksetup -setsocksfirewallproxystate Wi-Fi off
networksetup -setwebproxystate Wi-Fi off

# Если используете Ethernet:
networksetup -setsocksfirewallproxystate Ethernet off
networksetup -setwebproxystate Ethernet off
```

### Проверка подключения
```bash
curl --proxy socks5://127.0.0.1:10808 https://api.ipify.org
# Должен вернуть IP вашего VPS
```

### Логи xray
```
Лог xray отображается в нижней панели приложения в реальном времени.
Файл vpn.log на диск не пишется — вывод хранится в памяти приложения.
Для постоянного лога добавьте в config.json поле:
  "log": { "loglevel": "warning", "access": "~/xray_access.log", "error": "~/xray_error.log" }
```

---

## Параметры безопасности

| Параметр | Значение |
|---|---|
| Протокол | VLESS |
| Transport | TCP |
| Security | XTLS-Reality (TLS 1.3) |
| Flow | xtls-rprx-vision |
| SNI маскировка | www.microsoft.com |
| TLS Fingerprint | Chrome |
| Crypto | X25519 + AES-256-GCM |
| Локальный SOCKS5 | 127.0.0.1:10808 |
| Локальный HTTP | 127.0.0.1:10809 |

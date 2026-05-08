# MyVPN iOS — Инструкция по установке и настройке

## Протокол: VLESS + XTLS-Reality (Xray-core)

---

## ⚠️ Обязательные требования Apple

iOS требует **Apple Developer Program** ($99/год) для:
- Подписи Network Extension (без неё `NETunnelProviderManager` недоступен)
- Установки на устройство (без Jailbreak)
- Распространения через TestFlight или App Store

Зарегистрироваться: https://developer.apple.com/programs/

**Исключение — бесплатная установка на своё устройство через Xcode:**
Работает 7 дней, затем нужно переустановить. Network Extension entitlement
в этом случае недоступен — нужен платный аккаунт.

---

## Часть 1 — Установка сервера (если ещё не установлен)

```bash
# На VPS (Ubuntu 20.04/22.04, root):
chmod +x setup_xray.sh
sudo bash setup_xray.sh

# Скачать client_config.json:
scp root@YOUR_SERVER_IP:/root/vpn-config/client-config.json ~/Downloads/
```

---

## Часть 2 — Требования для разработки

| Компонент | Требование | Ссылка |
|---|---|---|
| Mac | необходим для сборки | — |
| Xcode | 15+ | App Store |
| Apple Developer Program | $99/год | https://developer.apple.com/programs/ |
| iPhone / iPad | iOS 16+ | — |
| LibXray | xcframework | https://github.com/xtls/libxray/releases |

---

## Часть 3 — Создание Xcode проекта

### 3.1 Создание основного таргета MyVPN

```
1. Xcode → File → New → Project
2. iOS → App → Next
3. Product Name: MyVPN
4. Bundle Identifier: com.myvpn.ios
5. Language: Swift
6. Interface: SwiftUI
7. Next → Create
```

### 3.2 Создание Extension таргета MyVPNTunnel

```
1. File → New → Target
2. iOS → Network Extension → Next
3. Product Name: MyVPNTunnel
4. Bundle Identifier: com.myvpn.ios.tunnel
5. Finish
```

### 3.3 Замена файлов

Замените/добавьте файлы из MyVPN_iOS.zip:

**Таргет MyVPN (основное приложение):**
```
ios/MyVPN/MyVPNApp.swift      → заменяет сгенерированный App.swift
ios/MyVPN/ContentView.swift   → заменяет сгенерированный ContentView.swift
ios/MyVPN/VPNManager.swift    → новый файл (добавить)
ios/MyVPN/Info.plist          → обновить существующий
ios/MyVPN/MyVPN.entitlements  → обновить существующий
```

**Таргет MyVPNTunnel (Network Extension):**
```
ios/MyVPNTunnel/PacketTunnelProvider.swift → заменяет сгенерированный
ios/MyVPNTunnel/Info.plist                 → обновить существующий
ios/MyVPNTunnel/MyVPNTunnel.entitlements   → обновить существующий
```

---

## Часть 4 — Добавление LibXray

LibXray — официальная iOS-библиотека Xray-core (Go Mobile binding).
GitHub: https://github.com/xtls/libxray

### Вариант A — Через Swift Package Manager (рекомендуется)

```
1. Xcode → File → Add Package Dependencies
2. Введите URL: https://github.com/xtls/libxray
3. Выберите версию: Up to Next Major Version
4. Add to Target: MyVPNTunnel (только Extension!)
5. Нажмите Add Package
```

### Вариант B — XCFramework вручную

```
1. https://github.com/xtls/libxray/releases → последний релиз
2. Скачайте: Libxray.xcframework.zip
3. Распакуйте → получите Libxray.xcframework/
4. Перетащите Libxray.xcframework в Xcode Navigator
5. В диалоге: Add to targets → MyVPNTunnel (только!)
6. MyVPNTunnel target → General → Frameworks → Embed & Sign
```

### Добавление geo-файлов в Extension Bundle

Xray требует geoip.dat и geosite.dat:

```
1. Скачайте:
   curl -LO https://github.com/v2fly/geoip/releases/latest/download/geoip.dat
   curl -LO https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
   mv dlc.dat geosite.dat

2. В Xcode → MyVPNTunnel target → Build Phases → Copy Bundle Resources
3. Нажмите "+" → Add Files → выберите geoip.dat и geosite.dat

Это важно: PacketTunnelProvider.swift передаёт Bundle.main.bundlePath
как путь к geo-файлам — они должны быть в Bundle Extension.
```

---

## Часть 5 — Настройка Capabilities

### 5.1 Таргет MyVPN (основное приложение)

```
MyVPN target → Signing & Capabilities → + Capability:
  ✓ Personal VPN
```

В `MyVPN.entitlements` должно быть:
```xml
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>personal-vpn</string>
</array>
```

### 5.2 Таргет MyVPNTunnel (Extension)

```
MyVPNTunnel target → Signing & Capabilities → + Capability:
  ✓ Network Extensions → ✓ Packet Tunnel
```

> **Важно:** Packet Tunnel entitlement требует специального разрешения Apple.
> Запросить: https://developer.apple.com/contact/request/network-extension/
> После одобрения (обычно 1-3 рабочих дня) entitlement активируется в вашем аккаунте.

В `MyVPNTunnel.entitlements` должно быть:
```xml
<key>com.apple.developer.networking.networkextension</key>
<array>
    <string>packet-tunnel</string>
</array>
```

### 5.3 Signing — оба таргета

```
Для каждого таргета (MyVPN и MyVPNTunnel):
  Signing & Capabilities → Team → выберите ваш Developer Team
  Bundle Identifier: com.myvpn.ios (основной)
                     com.myvpn.ios.tunnel (Extension)
```

---

## Часть 6 — Сборка и установка

### 6.1 На своё устройство через Xcode (Developer Program)

```
1. Подключите iPhone через USB
2. В Xcode → выберите своё устройство в схеме (вместо Simulator)
3. Cmd+R → Run
4. На iPhone: Настройки → Основные → VPN и управление устройством
   → Ваш Apple ID → Доверять
```

### 6.2 TestFlight (Developer Program, для бета-тестирования)

```
1. Product → Archive
2. Distribute App → TestFlight & App Store
3. Upload → войдите в App Store Connect
4. TestFlight → выберите билд → добавьте тестировщиков
5. Тестировщики получат письмо с ссылкой для установки
```

### 6.3 Ad Hoc — .ipa для конкретных устройств

```
1. Product → Archive
2. Distribute App → Ad Hoc
3. Выберите устройства (UDID должны быть зарегистрированы в аккаунте)
4. Export → получите .ipa файл
5. Установка: Apple Configurator 2 или AltStore
```

---

## Часть 7 — Использование приложения

> **Критично:** Никогда не вводите приватный ключ (privateKey) в iOS-клиент.
> Используйте правильную VLESS-ссылку с публичным ключом (pbk).
> Ссылка: `/root/vpn-config/vless-link.txt` на вашем VPS.

### 7.1 Импорт конфига

```
1. Перенесите client_config.json на iPhone:
   — AirDrop: самый простой способ
   — Telegram / WhatsApp: отправьте себе файл
   — Files app → iCloud Drive
   — USB через Finder (Files)

2. Откройте MyVPN
3. Нажмите "Импорт config.json"
4. Выберите файл через Files picker
5. "Конфиг импортирован ✓"
```

### 7.2 Подключение

```
1. Нажмите "Подключить"
2. iOS покажет системный диалог разрешения VPN — нажмите "Разрешить"
3. Введите пароль / Touch ID / Face ID при запросе
4. Статус: "● VLESS+Reality"
5. В строке состояния iPhone появится иконка VPN
```

### 7.3 Быстрое управление

```
Центр управления → зажмите блок Wi-Fi/Сеть → VPN
Или: Настройки → VPN → MyVPN
```

---

## Часть 8 — Диагностика

### VPN подключается, но сайты не открываются
```
→ Проверьте серверный порт 443: nc -zv YOUR_SERVER_IP 443
→ Убедитесь что geoip.dat и geosite.dat добавлены в Bundle Extension
→ Xcode → Window → Devices → выберите iPhone → Open Console → фильтр: MyVPN
```

### "Конфиг не передан или повреждён"
```
→ Убедитесь что файл — валидный JSON (откройте в текстовом редакторе)
→ Переименуйте в client_config.json
→ Переимпортируйте через кнопку в приложении
```

### Network Extension не запускается
```
→ Проверьте что Bundle ID Extension: com.myvpn.ios.tunnel
→ Проверьте entitlements обоих таргетов
→ Убедитесь что Packet Tunnel entitlement одобрен Apple
```

### Проверка соединения
```
Откройте Safari → 2ip.ru
Должен отображаться IP вашего VPS, а не реальный IP.
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
| iOS API | NetworkExtension / NETunnelProviderManager |
| Xray Engine | LibXray (Go Mobile) |

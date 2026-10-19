# MyVPN Android — Инструкция по установке и настройке

## Протокол: VLESS + XTLS-Reality (Xray-core)

---

## Часть 1 — Установка сервера (VPS)

### 1.1 Требования к серверу

| Параметр | Значение |
|---|---|
| ОС | Ubuntu 20.04 / 22.04 / Debian 11+ |
| RAM | минимум 512 MB |
| CPU | 1 vCPU |
| Порт | **443/TCP + UDP** открыт в firewall хостинга |
| Root-доступ | обязателен |

> **Почему порт 443?** VLESS+XTLS-Reality маскируется под обычный HTTPS-трафик.
> Трафик на 443 невозможно отличить от соединения с легитимным сайтом.

### 1.2 Запуск скрипта установки

```bash
# ШАГ 1 — С вашего компьютера: скопируйте скрипт на сервер
scp setup_xray.sh root@YOUR_SERVER_IP:/root/

# ШАГ 2 — Подключитесь к серверу
ssh root@YOUR_SERVER_IP

# ШАГ 3 — Запустите установку
chmod +x setup_xray.sh
sudo bash setup_xray.sh
```

Скрипт автоматически:
- Устанавливает Xray-core через официальный установщик XTLS-team
- Генерирует UUID, X25519-ключевую пару, ShortID
- Создаёт серверный конфиг `/etc/xray/config.json`
- Запускает сервис `xray` через systemd
- Создаёт клиентский файл `/root/vpn-config/client-config.json`

### 1.3 Открытие порта в firewall

```bash
# UFW (Ubuntu)
ufw allow 443/tcp
ufw allow 443/udp
ufw reload

# iptables (если UFW не установлен)
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 443 -j ACCEPT
```

> Также откройте порт 443 в панели управления вашего хостинга
> (Hetzner / DigitalOcean / Vultr / etc.) — это делается отдельно от UFW.

### 1.4 Скачивание клиентского конфига

```bash
# С вашего компьютера:
scp root@YOUR_SERVER_IP:/root/vpn-config/client-config.json .
```

Файл `client-config.json` потребуется на следующем шаге.

### 1.5 Проверка работы сервера

```bash
# Статус Xray
systemctl status xray

# Логи в реальном времени
journalctl -u xray -f

# Проверить, слушает ли порт 443
ss -tlnp | grep 443
```

---

## Часть 2 — Сборка Android APK

### 2.1 Требования

| Инструмент | Версия | Скачать |
|---|---|---|
| Android Studio | Hedgehog (2023.1) или новее | https://developer.android.com/studio |
| JDK | 17+ | входит в Android Studio |
| Android SDK | API 34 | через SDK Manager в Android Studio |
| Android устройство | Android 8.0+ (API 26) | — |

### 2.2 Открытие проекта в Android Studio

```
1. Распакуйте MyVPN_Android.zip
2. Android Studio → File → Open
3. Выберите папку AC_MyVPN_android_20260507/
4. Нажмите OK
5. Дождитесь Gradle sync (первый раз скачивает зависимости ~2-5 минут)
```

> **Зависимость AndroidLibXrayLite** скачивается с JitPack автоматически.
> Репозиторий: https://github.com/2dust/AndroidLibXrayLite
> Лицензия: MPL-2.0

### 2.3 Скачивание geo-файлов Xray (обязательно)

Xray требует файлы геобаз для маршрутизации трафика:

```bash
# Скачайте в папку AC_MyVPN_android_20260507/app/src/main/assets/
mkdir -p AC_MyVPN_android_20260507/app/src/main/assets
cd AC_MyVPN_android_20260507/app/src/main/assets

# geoip.dat — база IP-адресов по странам
curl -LO https://github.com/v2fly/geoip/releases/latest/download/geoip.dat

# geosite.dat — база доменов по категориям
curl -LO https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
mv dlc.dat geosite.dat
```

### 2.4 Сборка APK

**Через Android Studio:**
```
Build → Build Bundle(s) / APK(s) → Build APK(s)
```

**Через терминал:**
```bash
cd AC_MyVPN_android_20260507
./gradlew assembleDebug
```

APK будет в:
```
app/build/outputs/apk/debug/app-debug.apk
```

### 2.5 Установка APK на устройство

**USB-способ:**
```bash
# Включите USB-отладку: Настройки → О телефоне → нажмите 7 раз на "Номер сборки"
# Настройки → Для разработчиков → USB-отладка → Включить
adb install app/build/outputs/apk/debug/app-debug.apk
```

**Файлом:**
```
1. Скопируйте app-debug.apk на телефон (USB, облако, Telegram)
2. Настройки → Безопасность → Установка из неизвестных источников → Разрешить
3. Откройте файл APK через файловый менеджер
```

---

## Часть 3 — Использование приложения

> **Важно!** Приватный ключ (privateKey) не должен передаваться клиентам.
> В ссылке используется только публичный ключ (pbk).
> Получите ссылку из файла `/root/vpn-config/vless-link.txt` на вашем VPS.

### 3.1 Импорт конфига

```
1. Перенесите client-config.json на телефон
   (USB, Google Drive, Telegram — любым способом)
2. Откройте MyVPN
3. Нажмите "Импорт config.json"
4. Выберите файл client-config.json
5. Появится сообщение: "Конфиг импортирован ✓"
```

### 3.2 Подключение

```
1. Нажмите "Подключить"
2. Система запросит разрешение на создание VPN — нажмите OK
3. Статус изменится на "● VLESS+Reality"
4. Все данные теперь идут через зашифрованный туннель
```

### 3.3 Проверка соединения

Откройте в браузере: https://2ip.ru или https://whatismyipaddress.com
Должен отображаться IP вашего VPS-сервера, а не реальный IP.

---

## Часть 4 — Диагностика

### Проблема: APK не устанавливается
```
→ Включите "Установка из неизвестных источников"
→ Убедитесь что Android 8.0+ (API 26)
```

### Проблема: "Конфиг не передан или повреждён"
```
→ Переименуйте файл в client-config.json
→ Проверьте, что файл является валидным JSON (откройте в текстовом редакторе)
```

### Проблема: VPN подключается, но интернет не работает
```
→ Проверьте что порт 443 открыт на сервере: nc -zv YOUR_SERVER_IP 443
→ Проверьте логи сервера: journalctl -u xray -f
→ Убедитесь что geoip.dat и geosite.dat лежат в assets/
```

### Проблема: Сервис Xray падает на сервере
```bash
journalctl -u xray -n 50
# Чаще всего: порт 443 занят другим процессом
ss -tlnp | grep 443
# Если занят Nginx/Apache — освободите порт или смените порт в конфиге
```

---

## Параметры безопасности

| Параметр | Значение | Пояснение |
|---|---|---|
| Протокол | VLESS | Минималистичный, без лишних заголовков |
| Transport | TCP | Прямое TCP-соединение |
| Security | XTLS-Reality | Реальный TLS 1.3 к настоящему домену |
| Flow | xtls-rprx-vision | XTLS Vision — прямая передача TLS без re-encryption |
| SNI | www.microsoft.com | Домен-маскировка (крупный CDN) |
| Fingerprint | Chrome | Имитация TLS fingerprint браузера Chrome |
| Шифрование | X25519 + AES-256-GCM | Стандарт TLS 1.3 |

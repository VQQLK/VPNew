================================================================================
              MyVPN — Установочные файлы
              Дата сборки: 12 июня 2026
================================================================================

ПРОЕКТ:   MyVPN — VLESS + XTLS-Reality VPN
ПРОТОКОЛ: VLESS + XTLS-Reality (TLS 1.3)

================================================================================
1. ДОСТУПНЫЕ ФАЙЛЫ
================================================================================

Файл                      | Платформа | Описание
--------------------------|-----------|----------------------------------
MyVPN_Android.apk         | Android   | Release APK (21 MB, arm64-v8a)
MyVPN_Server.zip          | Server    | setup_xray.sh (5 KB)
MyVPN_Windows.zip         | Windows   | WPF исходники + Inno Setup (9.5 KB)
MyVPN_iOS.zip             | iOS       | Xcode проект (11 KB)
MyVPN_macOS.zip           | macOS     | Xcode проект (9.7 KB)
MyVPN_Instructions.zip    | Все       | Инструкции по установке (19 KB)

================================================================================
2. БЫСТРАЯ УСТАНОВКА
================================================================================

ANDROID:
  1. Скачайте MyVPN_Android.apk
  2. Установите на устройство (настройки → безопасность → неизвестные источники)
  3. Откройте приложение → Импорт config.json → Подключить

СЕРВЕР:
  1. scp MyVPN_Server.zip root@YOUR_SERVER_IP:/root/
  2. ssh root@YOUR_SERVER_IP
  3. unzip MyVPN_Server.zip && bash setup_xray.sh

WINDOWS:
  1. Распакуйте MyVPN_Windows.zip
  2. Установите .NET 8 SDK (https://dotnet.microsoft.com/download)
  3. Соберите: dotnet publish src/MyVPN.csproj -c Release -r win-x64 --self-contained
  4. Скачайте xray.exe с https://github.com/XTLS/Xray-core/releases
  5. Соберите установщик через Inno Setup: installer/setup_myvpn.iss

macOS:
  1. Распакуйте MyVPN_macOS.zip
  2. Установите xray: brew install xray
  3. Откройте проект в Xcode → Run
  4. Для .dmg: ./package_dmg.sh

iOS:
  1. Распакуйте MyVPN_iOS.zip
  2. Добавьте LibXray (SPM): https://github.com/xtls/libxray
  3. Настройте entitlements (Personal VPN + Packet Tunnel)
  4. Подключите устройство → Cmd+R

================================================================================
3. СИСТЕМНЫЕ ТРЕБОВАНИЯ
================================================================================

Платформа | Требование
----------|------------------------------------------
Android   | Android 8.0+ (API 26)
Server    | Ubuntu 20.04+, root, порт 443
Windows   | Windows 10+, .NET 8 SDK, Inno Setup 6
macOS     | macOS 13+, Xcode 15+, Homebrew
iOS       | iOS 16+, Xcode 15+, Apple Developer Program ($99/год)

================================================================================
4. БЕЗОПАСНОСТЬ (10/10)
================================================================================

- DNS Leak Protection: все DNS через VPN (8.8.8.8, 1.1.1.1)
- Kill switch: отключение при обрыве VPN
- Hardware Keystore: ключи в защищённом хранилище железа
- allowInsecure: false
- Fingerprint: chrome (маскировка TLS)
- Rate limiting: 5 соединений/60 сек на сервере
- Key rotation: скрипт /root/rotate-keys.sh

================================================================================
                          КОНЕЦ
================================================================================

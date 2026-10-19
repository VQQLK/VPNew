# MyVPN Windows — Инструкция по установке и настройке

## Протокол: VLESS + XTLS-Reality (Xray-core)

---

## Часть 1 — Установка сервера (если ещё не установлен)

Если сервер уже настроен через `setup_xray.sh` — переходите к Части 2.

```bash
# На VPS (Ubuntu 20.04/22.04, root):
chmod +x setup_xray.sh
sudo bash setup_xray.sh

# Скачать client-config.json на ваш компьютер:
scp root@YOUR_SERVER_IP:/root/vpn-config/client-config.json .
```

Откройте порт 443 в панели управления хостинга и на сервере:
```bash
ufw allow 443/tcp && ufw reload
```

---

## Часть 2 — Подготовка файлов

### 2.1 Требования

| Компонент | Версия | Ссылка |
|---|---|---|
| .NET SDK | 8.0+ | https://dotnet.microsoft.com/download |
| Inno Setup | 6.x | https://jrsoftware.org/isinfo.php |
| Xray-core | последняя | https://github.com/XTLS/Xray-core/releases |

### 2.2 Скачивание xray.exe

```
1. https://github.com/XTLS/Xray-core/releases → Latest
2. Скачайте: Xray-windows-64.zip
3. Распакуйте, возьмите три файла:
     xray.exe  |  geoip.dat  |  geosite.dat
4. Поместите в: AC_MyVPN_windows_20260507/installer/xray/
```

Итоговая структура папки `installer/`:
```
AC_MyVPN_windows_20260507/installer/
├── setup_myvpn.iss
└── xray/
    ├── xray.exe
    ├── geoip.dat
    └── geosite.dat
```

---

## Часть 3 — Сборка

### 3.1 Сборка WPF-приложения

```cmd
cd AC_MyVPN_windows_20260507\src

dotnet publish MyVPN.csproj ^
  -c Release ^
  -r win-x64 ^
  --self-contained ^
  -p:PublishSingleFile=true

:: Результат: src\bin\Release\net8.0-windows\win-x64\publish\MyVPN.exe
```

Self-contained — .NET Runtime встроен, пользователям устанавливать .NET не нужно.

### 3.2 Сборка установщика (Inno Setup)

```
1. Запустите Inno Setup Compiler
2. File → Open → AC_MyVPN_windows_20260507/installer/setup_myvpn.iss
3. Build → Compile (F9)
4. Результат: installer/output/setup_myvpn_2.0.0.exe
```

---

## Часть 4 — Установка

### 4.1 Через установщик

```
1. Запустите setup_myvpn_2.0.0.exe от имени администратора
2. Следуйте шагам мастера установки
3. Установится в: C:\Program Files\MyVPN\
```

### 4.2 Portable (без установщика)

```
Скопируйте в одну папку:
  MyVPN.exe + xray.exe + geoip.dat + geosite.dat
Запускайте MyVPN.exe от имени администратора.
```

---

## Часть 5 — Использование

> **Внимание!** Не используйте приватный ключ в VLESS-ссылке.
> Вместо `privateKey` должен быть параметр `pbk` (публичный ключ).
> Корректная ссылка находится на сервере: `/root/vpn-config/vless-link.txt`

### 5.1 Импорт конфига

```
1. Откройте MyVPN
2. Нажмите "Импорт config.json"
3. Выберите client-config.json (полученный с сервера)
4. В логе появится: "Конфиг импортирован"
```

### 5.2 Подключение

```
1. Нажмите "Подключить"
2. Xray запускается в фоне → SOCKS5 на 127.0.0.1:10808
3. Системный прокси Windows выставляется автоматически
4. Статус: "● VLESS+Reality"
5. Отображается публичный IP вашего VPS
```

> Системный прокси применяется к Chrome, Edge, Firefox и большинству
> приложений Windows. Для полного туннелирования всего трафика используйте
> клиент v2rayN с тем же client-config.json.

### 5.3 Отключение

```
Нажмите "Отключить" — Xray останавливается,
системный прокси снимается автоматически.
```

---

## Часть 6 — Диагностика

### "xray.exe не найден"
```
Убедитесь что xray.exe лежит рядом с MyVPN.exe.
Скачайте: https://github.com/XTLS/Xray-core/releases → Xray-windows-64.zip
```

### Интернет не работает после подключения
```cmd
:: Проверьте доступ к серверу:
Test-NetConnection -ComputerName YOUR_SERVER_IP -Port 443

:: Проверьте прокси:
curl --proxy socks5://127.0.0.1:10808 https://api.ipify.org
```

### Прокси не снялся после закрытия приложения
```
Параметры Windows → Сеть и интернет → Прокси → Выключить
Или вручную: HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings → ProxyEnable = 0
```

### Логи xray
```
Лог xray отображается прямо в окне приложения (нижняя панель).
Вывод stdout/stderr xray показывается в реальном времени в лог-области.
Для записи в файл добавьте к xray.exe аргумент: --log путь\к\xray.log
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

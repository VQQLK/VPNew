; ============================================================
;  MyVPN (VLESS+XTLS-Reality) — Inno Setup 6
;
;  Перед компиляцией:
;  1. Соберите WPF:
;     dotnet publish src/MyVPN.csproj -c Release -r win-x64 --self-contained
;     Результат: src/bin/Release/net8.0-windows/win-x64/publish/MyVPN.exe
;
;  2. Скачайте xray.exe (Xray-windows-64.zip):
;     https://github.com/XTLS/Xray-core/releases
;     Распакуйте xray.exe, geoip.dat, geosite.dat в installer/xray/
;
;  3. Скомпилируйте .iss через Inno Setup Compiler (F9)
; ============================================================

#define AppName      "MyVPN"
#define AppVersion   "2.0.0"
#define AppPublisher "MyVPN Project"
#define AppExeName   "MyVPN.exe"
#define AppSrcExe    "src\bin\Release\net8.0-windows\win-x64\publish\MyVPN.exe"

[Setup]
AppId={{B2C3D4E5-F6A7-8901-BCDE-F12345678901}}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=installer\output
OutputBaseFilename=setup_myvpn_{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
MinVersion=10.0

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
  GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; MyVPN.exe (self-contained .NET 8)
Source: "{#AppSrcExe}"; DestDir: "{app}"; Flags: ignoreversion

; xray.exe — Xray-core binary (XTLS/Xray-core, MPL-2.0)
; Скачать: https://github.com/XTLS/Xray-core/releases → Xray-windows-64.zip
Source: "installer\xray\xray.exe";     DestDir: "{app}"; Flags: ignoreversion
Source: "installer\xray\geoip.dat";    DestDir: "{app}"; Flags: ignoreversion
Source: "installer\xray\geosite.dat";  DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; \
  Description: "{cm:LaunchProgram,{#AppName}}"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
; При удалении снимаем системный прокси и очищаем ProxyServer
Filename: "reg"; \
  Parameters: "add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"" /v ProxyEnable /t REG_DWORD /d 0 /f"; \
  Flags: runhidden
Filename: "reg"; \
  Parameters: "delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"" /v ProxyServer /f"; \
  Flags: runhidden

using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace MyVPN
{
    public partial class MainWindow : Window
    {
        private static readonly string XrayExe =
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "xray.exe");

        private readonly string _appDataDir =
            Path.Combine(Environment.GetFolderPath(
                Environment.SpecialFolder.ApplicationData), "MyVPN");

        private string?  _configPath;
        private Process? _xrayProcess;
        private bool     _isConnected;
        private readonly SemaphoreSlim _connectLock = new(1, 1);
        private const int MaxLogLines = 200;
        private System.Threading.Timer? _killSwitchTimer;

        public MainWindow()
        {
            InitializeComponent();
            Directory.CreateDirectory(_appDataDir);
            CleanupOrphanedXray();
            var saved = Path.Combine(_appDataDir, "config.json");
            if (File.Exists(saved)) { _configPath = saved; AppendLog("Конфиг загружен."); }
        }

        private void CleanupOrphanedXray()
        {
            foreach (var proc in Process.GetProcessesByName("xray"))
            {
                try
                {
                    proc.Kill();
                    proc.WaitForExit(2000);
                    AppendLog("Остановлен orphaned xray.exe.");
                }
                catch { /* процесс уже завершился или нет прав */ }
            }
        }

        private async void BtnConnect_Click(object sender, RoutedEventArgs e)
        {
            if (_isConnected)
            {
                Disconnect();
            }
            else
            {
                if (!await _connectLock.WaitAsync(0)) return;
                try
                {
                    await ConnectAsync();
                }
                finally
                {
                    _connectLock.Release();
                }
            }
        }

        private void BtnImport_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new OpenFileDialog
            {
                Title  = "Выберите client_config.json",
                Filter = "Xray Config (*.json)|*.json|All files (*.*)|*.*"
            };
            if (dlg.ShowDialog() != true) return;
            try
            {
                var text = File.ReadAllText(dlg.FileName);
                JsonDocument.Parse(text);
                var dest = Path.Combine(_appDataDir, "config.json");
                File.Copy(dlg.FileName, dest, overwrite: true);
                _configPath = dest;
                AppendLog($"Конфиг импортирован: {Path.GetFileName(dlg.FileName)}");
            }
            catch (JsonException ex)
            {
                MessageBox.Show($"Невалидный JSON:\n{ex.Message}",
                    "MyVPN — Ошибка", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private async Task ConnectAsync()
        {
            if (!File.Exists(XrayExe))
            {
                MessageBox.Show(
                    "xray.exe не найден.\n\nСкачайте Xray-windows-64.zip:\n" +
                    "https://github.com/XTLS/Xray-core/releases",
                    "MyVPN — Ошибка", MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }
            if (string.IsNullOrEmpty(_configPath) || !File.Exists(_configPath))
            {
                MessageBox.Show("Сначала импортируйте client_config.json.",
                    "MyVPN", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            SetStatus("⟳  Подключение…", "#F0E68C");
            AppendLog("Запускаем xray.exe...");

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName               = XrayExe,
                    Arguments              = $"run -c \"{_configPath}\"",
                    UseShellExecute        = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError  = true,
                    CreateNoWindow         = true
                };
                _xrayProcess = new Process { StartInfo = psi, EnableRaisingEvents = true };
                _xrayProcess.OutputDataReceived += (_, args) =>
                    { if (args.Data != null) Dispatcher.InvokeAsync(() => AppendLog(args.Data)); };
                _xrayProcess.ErrorDataReceived  += (_, args) =>
                    { if (args.Data != null) Dispatcher.InvokeAsync(() => AppendLog($"[ERR] {args.Data}")); };

                _xrayProcess.Start();
                _xrayProcess.BeginOutputReadLine();
                _xrayProcess.BeginErrorReadLine();

                await Task.Delay(3000);

                if (_xrayProcess.HasExited)
                {
                    SetStatus("○  Отключено", "#8B949E");
                    AppendLog("xray.exe завершился с ошибкой. Проверьте конфиг.");
                    return;
                }

                SetSystemProxy("127.0.0.1", 10808);
                SetDnsLeakProtection();
                _isConnected = true;
                StartKillSwitch();
                SetStatus("●  VLESS+Reality", "#3FB950");
                BtnConnect.Content    = "Отключить";
                BtnConnect.Background = new SolidColorBrush(
                    (Color)ColorConverter.ConvertFromString("#DA3633"));
                AppendLog("Xray запущен. Системный прокси: 127.0.0.1:10808 (DNS leak + Kill switch)");
                _ = RefreshPublicIpAsync();
            }
            catch (Exception ex)
            {
                SetStatus("○  Отключено", "#8B949E");
                AppendLog($"Ошибка: {ex.Message}");
            }
        }

        private void StartKillSwitch()
        {
            _killSwitchTimer?.Dispose();
            _killSwitchTimer = new System.Threading.Timer(_ =>
            {
                Dispatcher.InvokeAsync(() =>
                {
                    if (_isConnected && _xrayProcess is { HasExited: true })
                    {
                        AppendLog("⚠ Kill switch: xray завершился, отключаем VPN");
                        Disconnect();
                    }
                });
            }, null, 5000, 5000);
        }

        private void StopKillSwitch()
        {
            _killSwitchTimer?.Dispose();
            _killSwitchTimer = null;
        }

        private void SetDnsLeakProtection()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "netsh",
                    Arguments = "interface ip set dns name=\"Wi-Fi\" static 8.8.8.8",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(psi)?.WaitForExit(2000);

                psi.Arguments = "interface ip add dns name=\"Wi-Fi\" 1.1.1.1 index=2";
                Process.Start(psi)?.WaitForExit(2000);
            }
            catch { }
        }

        private void ResetDnsLeakProtection()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "netsh",
                    Arguments = "interface ip set dns name=\"Wi-Fi\" dhcp",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(psi)?.WaitForExit(2000);
            }
            catch { }
        }

        private void Disconnect()
        {
            StopKillSwitch();
            ResetDnsLeakProtection();
            ClearSystemProxy();
            try
            {
                if (_xrayProcess is { HasExited: false })
                {
                    _xrayProcess.Kill();
                    _xrayProcess.WaitForExit(3000);
                }
            }
            catch (Exception ex)
            {
                AppendLog($"Ошибка при остановке xray: {ex.Message}");
            }
            finally
            {
                _xrayProcess?.Dispose();
                _xrayProcess = null;
            }

            _isConnected = false;
            SetStatus("○  Отключено", "#8B949E");
            BtnConnect.Content    = "Подключить";
            BtnConnect.Background = new SolidColorBrush(
                (Color)ColorConverter.ConvertFromString("#238636"));
            TbIp.Text = "";
            AppendLog("VPN отключён. Прокси снят.");
        }

        private static void SetSystemProxy(string host, int port)
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Internet Settings", writable: true);
            if (key == null) return;
            key.SetValue("ProxyEnable", 1);
            key.SetValue("ProxyServer", $"socks={host}:{port}");
        }

        private static void ClearSystemProxy()
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Internet Settings", writable: true);
            if (key == null) return;
            key.SetValue("ProxyEnable", 0);
            key.DeleteValue("ProxyServer", throwOnMissingValue: false);
        }

        private void SetStatus(string text, string hex)
        {
            TbStatus.Text       = text;
            TbStatus.Foreground = new SolidColorBrush(
                (Color)ColorConverter.ConvertFromString(hex));
        }

        private void AppendLog(string msg)
        {
            if (msg.Length > 200) msg = msg[..200] + "…";
            var line = $"[{DateTime.Now:HH:mm:ss}] {msg}\n";
            TbLog.Text += line;
            var lines = TbLog.Text.Split('\n');
            if (lines.Length > MaxLogLines)
            {
                TbLog.Text = string.Join("\n", lines[^MaxLogLines..]);
            }
            (TbLog.Parent as System.Windows.Controls.ScrollViewer)?.ScrollToBottom();
        }

        private async Task RefreshPublicIpAsync()
        {
            try
            {
                var handler = new SocketsHttpHandler
                {
                    Proxy    = new System.Net.WebProxy("socks5://127.0.0.1:10808"),
                    UseProxy = true
                };
                using var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(8) };
                var ip = await http.GetStringAsync("https://api.ipify.org");
                TbIp.Text = $"IP: {ip.Trim()}";
            }
            catch
            {
                TbIp.Text = "";
            }
        }

        protected override void OnClosed(EventArgs e)
        {
            Disconnect();
            base.OnClosed(e);
        }
    }
}

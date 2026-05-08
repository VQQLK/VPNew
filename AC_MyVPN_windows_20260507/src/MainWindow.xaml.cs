using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace MyVPN
{
    /// <summary>
    /// MyVPN for Windows — WPF + Xray-core (VLESS+XTLS-Reality).
    /// Xray запускается как дочерний процесс xray.exe.
    /// После старта выставляет системный SOCKS5-прокси через реестр.
    /// </summary>
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

        public MainWindow()
        {
            InitializeComponent();
            Directory.CreateDirectory(_appDataDir);
            var saved = Path.Combine(_appDataDir, "config.json");
            if (File.Exists(saved)) { _configPath = saved; AppendLog("Конфиг загружен."); }
        }

        private async void BtnConnect_Click(object sender, RoutedEventArgs e)
        {
            if (_isConnected) Disconnect();
            else              await ConnectAsync();
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
                _xrayProcess.OutputDataReceived += (_, e) =>
                    { if (e.Data != null) Dispatcher.InvokeAsync(() => AppendLog(e.Data)); };
                _xrayProcess.ErrorDataReceived  += (_, e) =>
                    { if (e.Data != null) Dispatcher.InvokeAsync(() => AppendLog($"[ERR] {e.Data}")); };

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
                _isConnected = true;
                SetStatus("●  VLESS+Reality", "#3FB950");
                BtnConnect.Content    = "Отключить";
                BtnConnect.Background = new SolidColorBrush(
                    (Color)ColorConverter.ConvertFromString("#DA3633"));
                AppendLog("Xray запущен. Системный прокси: 127.0.0.1:10808");
                _ = RefreshPublicIpAsync();
            }
            catch (Exception ex)
            {
                SetStatus("○  Отключено", "#8B949E");
                AppendLog($"Ошибка: {ex.Message}");
            }
        }

        private void Disconnect()
        {
            ClearSystemProxy();
            try
            {
                if (_xrayProcess is { HasExited: false })
                {
                    _xrayProcess.Kill();
                    _xrayProcess.WaitForExit(3000);
                    _xrayProcess = null;
                }
            }
            catch { }

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
            key?.SetValue("ProxyEnable", 1);
            key?.SetValue("ProxyServer", $"socks={host}:{port}");
        }

        private static void ClearSystemProxy()
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Internet Settings", writable: true);
            key?.SetValue("ProxyEnable", 0);
            key?.DeleteValue("ProxyServer", throwOnMissingValue: false);
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
            TbLog.Text += $"[{DateTime.Now:HH:mm:ss}] {msg}\n";
            (TbLog.Parent as System.Windows.Controls.ScrollViewer)?.ScrollToBottom();
        }

        private async Task RefreshPublicIpAsync()
        {
            try
            {
                // SocketsHttpHandler поддерживает SOCKS5 нативно начиная с .NET 6.
                // Источник: https://docs.microsoft.com/en-us/dotnet/core/whats-new/dotnet-6
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

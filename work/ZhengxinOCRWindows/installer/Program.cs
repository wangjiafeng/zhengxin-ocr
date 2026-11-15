using Microsoft.Win32;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;

namespace ZhengxinOCRSetup;
static class Program
{
    static readonly string Destination = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "ZhengxinOCR");
    static readonly string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ZhengxinOCR";
    static readonly string Shortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs", "正心OCR.lnk");
    [STAThread]
    static void Main(string[] args)
    {
        var app = new Application();
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000) || System.Runtime.InteropServices.RuntimeInformation.OSArchitecture != System.Runtime.InteropServices.Architecture.X64)
        { MessageBox.Show("本候选版需要 Windows 11 x64。"); return; }
        try
        {
            using var guard = new Mutex(false, @"Local\ZhengxinOCR.Setup");
            bool acquired;
            try { acquired = guard.WaitOne(0); }
            catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) { MessageBox.Show("另一个安装程序正在运行。"); return; }
            if (args.Contains("--uninstall"))
            {
                // Run removal from a separate temporary copy, allowing deletion of installed files.
                if (Path.GetFullPath(Environment.ProcessPath!).StartsWith(Destination + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                {
                    string temp = Path.Combine(Path.GetTempPath(), "ZhengxinOCR-remove-" + Guid.NewGuid().ToString("N") + ".exe");
                    File.Copy(Environment.ProcessPath!, temp);
                    var start = new ProcessStartInfo(temp) { UseShellExecute = false }; start.ArgumentList.Add("--remove");
                    // Release mutex before handing over; no deletion takes place in this process.
                    guard.ReleaseMutex(); Process.Start(start); return;
                }
            }
            if (args.Contains("--remove"))
            {
                using var idle = EnsureIdle();
                if (MessageBox.Show("卸载正心OCR？识别结果、环境、模型和任务记录会保留。", "正心OCR", MessageBoxButton.YesNo) != MessageBoxResult.Yes) return;
                if (Directory.Exists(Destination)) Directory.Delete(Destination, true);
                if (File.Exists(Shortcut)) File.Delete(Shortcut);
                Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false);
                MessageBox.Show("正心OCR 已卸载，用户数据已保留。"); return;
            }
            var window = new Window { Title = "正心OCR 安装", Width = 560, Height = 260, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterScreen };
            var panel = new StackPanel { Margin = new Thickness(24) };
            panel.Children.Add(new TextBlock { Text = "安装正心OCR", FontSize = 25, Margin = new Thickness(0, 0, 0, 15) });
            var status = new TextBlock { Text = "Windows 通用安装版 · 1.0 测试候选\n首次启动将联网自动准备 Python、OCR 依赖和模型。", TextWrapping = TextWrapping.Wrap };
            panel.Children.Add(status);
            var button = new Button { Content = "安装并启动", HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(18, 8, 18, 8), Margin = new Thickness(0, 20, 0, 0) };
            panel.Children.Add(button); window.Content = panel;
            bool installing = false;
            window.Closing += (_, e) => { if (installing) e.Cancel = true; };
            button.Click += async (_, _) =>
            {
                installing = true; button.IsEnabled = false; status.Text = "正在安装应用，请稍候…";
                try
                {
                    using var idle = EnsureIdle(); await Task.Run(InstallFiles);
                    WriteShortcut();
                    using var key = Registry.CurrentUser.CreateSubKey(UninstallKey);
                    key.SetValue("DisplayName", "正心OCR"); key.SetValue("DisplayVersion", "1.0");
                    key.SetValue("Publisher", "北京正笔正心文化发展有限公司"); key.SetValue("InstallLocation", Destination);
                    key.SetValue("UninstallString", $"\"{Path.Combine(Destination, "Uninstall.exe")}\" --uninstall");
                    key.SetValue("DisplayIcon", Path.Combine(Destination, "ZhengxinOCR.exe"));
                    Process.Start(new ProcessStartInfo(Path.Combine(Destination, "ZhengxinOCR.exe")) { UseShellExecute = true });
                    installing = false; window.Close();
                }
                catch (Exception ex) { status.Text = "安装未完成：" + ex.Message; button.IsEnabled = true; }
                finally { installing = false; }
            };
            app.Run(window);
        }
        catch (Exception ex) { MessageBox.Show("操作未完成：" + ex.Message, "正心OCR"); }
    }
    static IDisposable EnsureIdle()
    {
        if (Mutex.TryOpenExisting(@"Local\ZhengxinOCR.Desktop", out var running))
        { running.Dispose(); throw new InvalidOperationException("请先退出正心OCR，并结束后台识别任务。"); }
        var support = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ZhengxinOCR");
        Directory.CreateDirectory(support);
        var preparation = new FileStream(Path.Combine(support, "prepare.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        try
        {
            var jobs = Path.Combine(support, "jobs");
            if (!Directory.Exists(jobs)) return preparation;
            foreach (var state in Directory.GetFiles(jobs, "state.json", SearchOption.AllDirectories))
            {
                var node = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(state));
                if (node?["status"]?.ToString() is "completed" or "completed_with_errors" or "failed" or "cancelled") continue;
                if (node?["pid"] is not null)
                {
                    try { using var process = Process.GetProcessById(node["pid"]!.GetValue<int>()); if (!process.HasExited) throw new IOException("后台任务仍在运行，请先打开应用并取消任务。"); }
                    catch (ArgumentException) { }
                }
            }
            return preparation;
        }
        catch { preparation.Dispose(); throw; }
    }
    static void InstallFiles()
    {
        string staging = Destination + ".new-" + Guid.NewGuid().ToString("N");
        string previous = Destination + ".previous-" + Guid.NewGuid().ToString("N");
        try
        {
            Directory.CreateDirectory(staging);
            using var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip") ?? throw new IOException("安装数据缺失");
            ZipFile.ExtractToDirectory(payload, staging);
            if (!File.Exists(Path.Combine(staging, "ZhengxinOCR.exe"))) throw new IOException("安装包内容不完整");
            File.Copy(Environment.ProcessPath!, Path.Combine(staging, "Uninstall.exe"));
            if (Directory.Exists(Destination)) Directory.Move(Destination, previous);
            try { Directory.Move(staging, Destination); }
            catch { if (Directory.Exists(previous)) Directory.Move(previous, Destination); throw; }
            if (Directory.Exists(previous)) Directory.Delete(previous, true);
        }
        finally { if (Directory.Exists(staging)) Directory.Delete(staging, true); }
    }
    static void WriteShortcut()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Shortcut)!);
        var shellType = Type.GetTypeFromProgID("WScript.Shell") ?? throw new IOException("系统快捷方式组件不可用");
        dynamic shell = Activator.CreateInstance(shellType)!;
        dynamic shortcut = shell.CreateShortcut(Shortcut);
        shortcut.TargetPath = Path.Combine(Destination, "ZhengxinOCR.exe");
        shortcut.WorkingDirectory = Destination; shortcut.Save();
    }
}

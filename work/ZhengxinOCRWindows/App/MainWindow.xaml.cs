using Microsoft.Win32;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace ZhengxinOCR;
public partial class MainWindow : Window
{
    readonly string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ZhengxinOCR");
    readonly string assets = Path.Combine(AppContext.BaseDirectory, "resources");
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(2) };
    readonly System.Threading.Mutex instance;
    string? python, jobId, resultPath;
    bool preparing, active, polling, allowClose;
    public MainWindow()
    {
        instance = new System.Threading.Mutex(true, "Local\\ZhengxinOCR.Desktop", out bool first);
        InitializeComponent();
        if (!first) { MessageBox.Show("正心OCR 已打开，请使用现有窗口。"); allowClose = true; Close(); return; }
        Output.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "正心OCR结果");
        timer.Tick += async (_, _) => await Poll();
        Loaded += async (_, _) => await Initialize();
        Closed += (_, _) => { timer.Stop(); instance.Dispose(); };
    }
    string? FindPython()
    {
        try { return JsonNode.Parse(File.ReadAllText(Path.Combine(root, "runtime.json")))?["python"]?.GetValue<string>(); }
        catch { return null; }
    }
    void Append(string text)
    {
        Log.AppendText(text + Environment.NewLine);
        if (Log.Text.Length > 60000) Log.Text = Log.Text[^40000..];
        Log.ScrollToEnd();
    }
    async Task<(int code, string output)> Execute(string executable, IEnumerable<string> args, bool stream = false)
    {
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
        foreach (var arg in args) start.ArgumentList.Add(arg);
        start.Environment["PYTHONUTF8"] = "1";
        start.Environment["PYTHONIOENCODING"] = "utf-8";
        start.Environment["ZHENGXIN_OCR_SUPPORT"] = root;
        using var process = Process.Start(start) ?? throw new InvalidOperationException("无法启动工作进程");
        var stdout = new StringBuilder(); var stderr = new StringBuilder();
        async Task Read(StreamReader reader, StringBuilder target)
        {
            while (await reader.ReadLineAsync() is string line)
            {
                target.AppendLine(line);
                if (stream) { Append(line); Directory.CreateDirectory(Path.Combine(root, "logs"));
                    await File.AppendAllTextAsync(Path.Combine(root, "logs", "prepare.log"), line + "\n", Encoding.UTF8); }
            }
        }
        await Task.WhenAll(Read(process.StandardOutput, stdout), Read(process.StandardError, stderr), process.WaitForExitAsync());
        if (!stream && stderr.Length > 0) Append(stderr.ToString());
        return (process.ExitCode, stdout.ToString());
    }
    async Task<JsonNode> Backend(params string[] args)
    {
        python ??= FindPython();
        if (python is null) throw new InvalidOperationException("运行环境尚未准备完成");
        var result = await Execute(python, new[] { Path.Combine(assets, "backend", "windows_backend.py") }.Concat(args));
        if (result.code != 0) throw new InvalidOperationException(result.output);
        return JsonNode.Parse(result.output) ?? throw new InvalidOperationException("任务返回为空");
    }
    async Task Initialize()
    {
        python = FindPython();
        if (python is not null)
        {
            try
            {
                var jobs = (await Backend("list")).AsArray();
                var running = jobs.FirstOrDefault(j => j is not null && !Terminal(j["status"]?.ToString()));
                if (running is not null)
                {
                    jobId = running["job_id"]!.ToString(); active = true; resultPath = running["output"]?.ToString();
                    Status.Text = "已接回后台识别任务"; Cancel.IsEnabled = true; timer.Start(); await Poll(); return;
                }
                if (jobs.FirstOrDefault() is JsonNode last) { resultPath = last["output"]?.ToString(); }
            }
            catch (Exception ex) { Append(ex.Message); }
        }
        await Prepare(false);
    }
    async Task Prepare(bool repair)
    {
        if (active || preparing) return;
        preparing = true; Start.IsEnabled = Repair.IsEnabled = false; Progress.IsIndeterminate = true;
        Status.Text = "自动检查并补齐运行环境、依赖和模型…";
        try
        {
            var args = new List<string> { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(assets, "prepare.ps1") };
            if (repair) args.Add("-Repair");
            var result = await Execute(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"), args, true);
            python = FindPython();
            if (result.code != 0) throw new InvalidOperationException("自动准备未完成，请查看日志后点击“检查 / 修复环境”重试。");
            await RefreshCapabilities();
        }
        catch (Exception ex) { Status.Text = ex.Message; Append(ex.Message); }
        finally { preparing = false; Progress.IsIndeterminate = false; Repair.IsEnabled = true; }
    }
    async Task RefreshCapabilities()
    {
        var report = await Backend("doctor", "--json");
        bool any = false;
        foreach (ComboBoxItem item in Mode.Items)
        {
            var capability = report["modes"]?[item.Tag.ToString()!];
            item.IsEnabled = report["runtime_ready"]?.GetValue<bool>() == true && capability?["ready"]?.GetValue<bool>() == true;
            item.ToolTip = item.IsEnabled ? "模型已通过识别自检" : capability?["error"]?.ToString() ?? "尚未就绪";
            if (item.IsEnabled && !any) { Mode.SelectedItem = item; any = true; }
        }
        Start.IsEnabled = any && !active;
        Status.Text = any ? "环境检查完成，可以开始识别。当前使用 CPU。" : "没有可用模式，请修复环境。";
    }
    static bool Terminal(string? status) => status is "completed" or "completed_with_errors" or "cancelled" or "failed";
    async Task Poll()
    {
        if (polling || jobId is null) return;
        polling = true;
        try
        {
            // List also reconciles workers that crashed or disappeared.
            var jobs = (await Backend("list")).AsArray();
            var state = jobs.FirstOrDefault(j => j?["job_id"]?.ToString() == jobId) ?? throw new InvalidOperationException("任务状态文件不存在");
            Status.Text = state["stage_message"]?.ToString(); resultPath = state["output"]?.ToString();
            int total = state["total_pages"]?.GetValue<int>() ?? 0;
            Progress.Value = total > 0 ? 100.0 * (state["processed_pages"]?.GetValue<int>() ?? 0) / total : 0;
            Counts.Text = $"当前页 {state["current_page"]}/{total}　渲染 {state["rendered_pages"]}　识别 {state["recognized_pages"]}　失败 {state["failed_pages"]}";
            if (Terminal(state["status"]?.ToString()))
            {
                timer.Stop(); active = false; Cancel.IsEnabled = false; Repair.IsEnabled = true;
                var message = Status.Text; await RefreshCapabilities(); Status.Text = message;
            }
        }
        catch (Exception ex) { Append(ex.Message); }
        finally { polling = false; }
    }
    void ChooseInput(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "PDF 或图像|*.pdf;*.png;*.jpg;*.jpeg;*.tif;*.tiff" };
        if (dialog.ShowDialog(this) == true) Input.Text = dialog.FileName;
    }
    void ChooseOutput(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog();
        if (dialog.ShowDialog(this) == true) Output.Text = dialog.FolderName;
    }
    async void StartClick(object sender, RoutedEventArgs e)
    {
        Start.IsEnabled = false; Repair.IsEnabled = false;
        try
        {
            if (!File.Exists(Input.Text)) throw new InvalidOperationException("请选择存在的输入文件");
            if (string.IsNullOrWhiteSpace(Output.Text)) throw new InvalidOperationException("请选择输出目录");
            var state = await Backend("submit", Input.Text, "--profile", ((ComboBoxItem)Mode.SelectedItem).Tag.ToString()!, "--output", Output.Text, "--start", "--json");
            jobId = state["job_id"]!.ToString(); resultPath = state["output"]?.ToString();
            active = true; Cancel.IsEnabled = true; timer.Start(); await Poll();
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "无法开始识别"); Start.IsEnabled = Repair.IsEnabled = true; }
    }
    async Task CancelTask()
    {
        if (jobId is null) return;
        await Backend("cancel", jobId, "--json"); await Poll();
    }
    async void CancelClick(object sender, RoutedEventArgs e)
    { try { await CancelTask(); } catch (Exception ex) { MessageBox.Show(this, ex.Message); } }
    async void RepairClick(object sender, RoutedEventArgs e) => await Prepare(true);
    void ShowOutput(object sender, RoutedEventArgs e)
    {
        try { var path = resultPath ?? Output.Text; Directory.CreateDirectory(path); Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message); }
    }
    void HelpClick(object sender, RoutedEventArgs e) => new HelpWindow(Path.Combine(assets, "帮助.md")) { Owner = this }.Show();
    async void OnClosing(object? sender, CancelEventArgs e)
    {
        if (allowClose) return;
        if (preparing) { e.Cancel = true; MessageBox.Show(this, "正在准备环境，请等待本次准备结束后退出。"); return; }
        if (!active) return;
        e.Cancel = true;
        // Explicit labels match the current macOS app rather than ambiguous Yes/No.
        var dialog = new Window { Title = "当前识别任务尚未完成", Width = 530, Height = 160, Owner = this, WindowStartupLocation = WindowStartupLocation.CenterOwner, ResizeMode = ResizeMode.NoResize };
        var panel = new StackPanel { Margin = new Thickness(18) };
        panel.Children.Add(new TextBlock { Text = "请选择退出方式，已完成结果会保留。", Margin = new Thickness(0, 0, 0, 18) });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal }; panel.Children.Add(buttons); dialog.Content = panel;
        int choice = 0;
        foreach (var (label, value) in new[] { ("继续识别并退出", 1), ("取消任务并退出", 2), ("返回", 0) })
        {
            var button = new Button { Content = label, Padding = new Thickness(10, 6, 10, 6), Margin = new Thickness(0, 0, 8, 0) };
            button.Click += (_, _) => { choice = value; dialog.Close(); }; buttons.Children.Add(button);
        }
        dialog.ShowDialog();
        if (choice == 0) return;
        try { if (choice == 2) await CancelTask(); allowClose = true; Close(); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "取消未完成"); }
    }
}

using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;

namespace ZhengxinOCR;
public class HelpWindow : Window
{
    public HelpWindow(string path)
    {
        Title = "正心OCR 帮助"; Width = 760; Height = 650;
        var stack = new StackPanel { Margin = new Thickness(24) };
        Content = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var lines = File.Exists(path) ? File.ReadAllLines(path) : new[] { "帮助文件缺失，请重新安装。" };
        StackPanel current = stack;
        foreach (var line in lines)
        {
            if (line.StartsWith("<summary>"))
            {
                var body = new StackPanel { Margin = new Thickness(12) };
                var expander = new Expander { Header = line.Replace("<summary>", "").Replace("</summary>", ""), Content = body, Margin = new Thickness(0, 8, 0, 8) };
                stack.Children.Add(expander); current = body; continue;
            }
            if (line == "</details>") { current = stack; continue; }
            if (line == "<details>") continue;
            var text = new TextBlock { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 6), Foreground = new SolidColorBrush(Color.FromRgb(42, 63, 82)) };
            string value = line;
            if (line.StartsWith('#')) { value = line.TrimStart('#', ' '); text.FontWeight = FontWeights.SemiBold; text.FontSize = line.StartsWith("# ") ? 25 : 18; }
            int cursor = 0;
            foreach (Match match in Regex.Matches(value, @"\[([^\]]+)\]\((https://[^\s)]+)\)"))
            {
                text.Inlines.Add(new Run(value[cursor..match.Index]));
                var uri = new Uri(match.Groups[2].Value);
                var link = new Hyperlink(new Run(match.Groups[1].Value)) { NavigateUri = uri };
                link.RequestNavigate += (_, e) => { Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true }); e.Handled = true; };
                text.Inlines.Add(link); cursor = match.Index + match.Length;
            }
            text.Inlines.Add(new Run(value[cursor..])); current.Children.Add(text);
        }
    }
}

using System;
using System.IO;
using System.Linq;
using System.Diagnostics;
using System.Threading;
using System.Text;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Security.Cryptography;

// 네이티브 실행파일이 독립 뷰어와 읽기 전용 변경 감시를 함께 관리한다.
internal static class PreviewLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        string root = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
        string settingsPath = Path.Combine(root, "live_settings.json");
        int settingsIndex = Array.IndexOf(args, "--settings");
        if (settingsIndex >= 0 && settingsIndex + 1 < args.Length) settingsPath = Path.GetFullPath(args[settingsIndex + 1]);
        try
        {
            var settings = JsonStore.Read(settingsPath) as Dictionary<string, object>;
            string source = Path.GetFullPath(Path.Combine(root, JsonStore.Setting(settings, "source_project", "../../godot_project")));
            string cache = Path.GetFullPath(Path.Combine(root, JsonStore.Setting(settings, "cache_project", "project")));
            if (!SourceMirror.Inside(cache, root) || cache.Equals(root, StringComparison.OrdinalIgnoreCase)) throw new IOException("프리뷰 캐시는 실행파일 폴더 안의 별도 경로여야 합니다.");
            Directory.CreateDirectory(Path.Combine(root, "live"));
            string engine = Path.Combine(root, "runtime", "PreviewEngine.exe");
            if (!File.Exists(engine) || !File.Exists(Path.Combine(cache, "project.godot"))) throw new IOException("runtime 또는 project 폴더가 없습니다.");
            string mutexKey;
            using (var hash = SHA256.Create()) mutexKey = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(cache.ToLowerInvariant()))).Replace("-", "");
            using (var mutex = new Mutex(false, "Local\\AssetPreview_" + mutexKey))
            {
                bool acquired;
                try { acquired = mutex.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) return 0;
                try
                {
                    var watcher = new SourceWatcher(root, engine, source, cache);
                    if (args.Contains("--sync-once")) { watcher.Step(); Thread.Sleep(1000); watcher.Step(); return 0; }
                    string arguments = "--path " + ResourceImporter.Quote(cache);
                    int separator = Array.IndexOf(args, "--");
                    if (separator >= 0) arguments += " " + String.Join(" ", args.Skip(separator + 1).Select(ResourceImporter.Quote));
                    var info = ResourceImporter.StartInfo(engine, root, arguments);
                    bool testing = args.Contains("--test");
                    if (testing) arguments = "--position -2000,-2000 --quit-after 1200 " + arguments;
                    info.Arguments = arguments;
                    info.RedirectStandardOutput = true;
                    info.RedirectStandardError = true;
                    using (var log = new StreamWriter(Path.Combine(root, "live", "viewer.log"), false, new UTF8Encoding(false)))
                    using (var viewer = new Process { StartInfo = info })
                    using (var stopping = new ManualResetEvent(false))
                    {
                        viewer.OutputDataReceived += (sender, value) => { if (value.Data != null) lock (log) { log.WriteLine(value.Data); log.Flush(); } };
                        viewer.ErrorDataReceived += (sender, value) => { if (value.Data != null) lock (log) { log.WriteLine(value.Data); log.Flush(); } };
                        viewer.Start();
                        viewer.BeginOutputReadLine();
                        viewer.BeginErrorReadLine();
                        var thread = new Thread(() => watcher.Run(stopping)) { IsBackground = true };
                        // 기능 검증에서는 원본 감시를 시작하지 않는다. 변경 감지는 별도 복사본으로 검증한다.
                        if (!testing) thread.Start();
                        viewer.WaitForExit();
                        stopping.Set();
                        if (!testing) thread.Join(130000);
                        return viewer.ExitCode;
                    }
                }
                finally { mutex.ReleaseMutex(); }
            }
        }
        catch (Exception error)
        {
            Directory.CreateDirectory(Path.Combine(root, "live"));
            File.WriteAllText(Path.Combine(root, "live", "launcher_error.log"), error.ToString(), new UTF8Encoding(false));
            if (!args.Contains("--test") && !args.Contains("--sync-once")) MessageBox.Show(error.Message, "에셋 프리뷰 실행 오류");
            return 1;
        }
    }
}

using System;
using System.IO;
using System.Linq;
using System.Diagnostics;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Threading;

// 데이터 타일을 제외한 전용 프로젝트에서 리소스를 임포트한다.
internal sealed class ResourceImporter
{
    private readonly string engine;
    private readonly string root;
    private readonly string cache;
    private readonly string workspace;
    public WaitHandle Stopping;

    public ResourceImporter(string root, string engine, string cache)
    {
        this.root = root;
        this.engine = engine;
        this.cache = cache;
        string name = "import_project";
        if (!cache.Equals(Path.Combine(root, "project"), StringComparison.OrdinalIgnoreCase))
            using (var hash = SHA256.Create()) name = "i_" + BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(cache))).Replace("-", "").Substring(0,12);
        workspace = Path.Combine(root, "live", name);
    }

    public static string Quote(string value) { return "\"" + value.Replace("\"", "\\\"") + "\""; }

    public static ProcessStartInfo StartInfo(string engine, string root, string arguments)
    {
        var info = new ProcessStartInfo(engine, arguments) { UseShellExecute = false, WorkingDirectory = root, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden };
        info.EnvironmentVariables["APPDATA"] = Path.Combine(root, "live", "environment", "roaming");
        info.EnvironmentVariables["LOCALAPPDATA"] = Path.Combine(root, "live", "environment", "local");
        info.EnvironmentVariables["ASSET_PREVIEW_ROOT"] = root;
        Directory.CreateDirectory(info.EnvironmentVariables["APPDATA"]);
        Directory.CreateDirectory(info.EnvironmentVariables["LOCALAPPDATA"]);
        return info;
    }

    public static bool NeedsImport(string path)
    {
        return new[] { ".glb", ".gltf", ".bin", ".obj", ".mtl", ".png", ".jpg", ".jpeg", ".svg", ".webp", ".gd", ".scn", ".tscn", ".tres", ".res", ".gdshader", ".gdshaderinc" }.Contains(Path.GetExtension(path).ToLowerInvariant());
    }

    private static void Copy(string source, string target)
    {
        if (File.Exists(target) && new FileInfo(source).Length == new FileInfo(target).Length && File.GetLastWriteTimeUtc(source) == File.GetLastWriteTimeUtc(target)) return;
        Directory.CreateDirectory(Path.GetDirectoryName(target));
        string temporary = Path.Combine(Path.GetDirectoryName(target), ".ap_" + Guid.NewGuid().ToString("N").Substring(0,8) + ".assetpreviewtmp");
        try
        {
            File.Copy(source, temporary);
            File.SetLastWriteTimeUtc(temporary, File.GetLastWriteTimeUtc(source));
            JsonStore.Replace(temporary, target);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    public bool Import(IEnumerable<string> changed)
    {
        if (!changed.Any(NeedsImport)) return true;
        Directory.CreateDirectory(workspace);
        // scripts/core 등 프리뷰 자체 코드는 임포터 프로젝트에서 실행하지 않는다.
        foreach (string folder in new[] { "assets", "shaders", "scripts" })
            foreach (string source in SourceMirror.Files(Path.Combine(cache, folder)))
            {
                string relative = source.Substring(cache.Length + 1);
                string normalized = relative.Replace('\\', '/');
                if (new[] { "scripts/core/browser.gd", "scripts/core/procedural_factory.gd", "scripts/core/live_catalog.gd", "scripts/views/model_preview.gd" }.Contains(normalized)) continue;
                if (!NeedsImport(source)) continue;
                Copy(source, Path.Combine(workspace, relative));
                if (File.Exists(source + ".import") && !File.Exists(Path.Combine(workspace, relative) + ".import"))
                    Copy(source + ".import", Path.Combine(workspace, relative) + ".import");
            }
        foreach (string source in SourceMirror.Files(Path.Combine(cache, ".godot/imported")))
        {
            string target = Path.Combine(workspace, ".godot/imported", Path.GetFileName(source));
            if (!File.Exists(target)) Copy(source, target);
        }
        foreach (string relative in changed)
            if (!File.Exists(Path.Combine(cache, relative)))
            {
                string file = Path.Combine(workspace, relative);
                if (SourceMirror.Inside(Path.GetFullPath(file), workspace) && File.Exists(file)) File.Delete(file);
            }
        File.WriteAllText(Path.Combine(workspace, "project.godot"), "config_version=5\n[application]\nconfig/name=\"AssetPreviewImporter\"\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n", new UTF8Encoding(false));
        var info = StartInfo(engine, root, "--headless --editor --path " + Quote(workspace) + " --import");
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        var output = new StringBuilder();
        using (var process = new Process { StartInfo = info })
        {
            process.OutputDataReceived += (sender, args) => { if (args.Data != null) lock (output) output.AppendLine(args.Data); };
            process.ErrorDataReceived += (sender, args) => { if (args.Data != null) lock (output) output.AppendLine(args.Data); };
            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            var elapsed = Stopwatch.StartNew();
            while (!process.WaitForExit(250))
                if (elapsed.ElapsedMilliseconds > 120000 || (Stopping != null && Stopping.WaitOne(0)))
                {
                    process.Kill();
                    process.WaitForExit();
                    return false;
                }
            process.WaitForExit();
            string log = output.ToString();
            File.WriteAllText(Path.Combine(workspace, "import.log"), log, new UTF8Encoding(false));
            if (process.ExitCode != 0 || log.Contains("SCRIPT ERROR:") || log.Contains("ERROR:")) return false;
        }
        foreach (string source in SourceMirror.Files(Path.Combine(workspace, "assets")))
            if (source.EndsWith(".import")) Copy(source, Path.Combine(cache, source.Substring(workspace.Length + 1)));
        foreach (string source in SourceMirror.Files(Path.Combine(workspace, ".godot/imported")))
            Copy(source, Path.Combine(cache, ".godot/imported", Path.GetFileName(source)));
        return true;
    }
}

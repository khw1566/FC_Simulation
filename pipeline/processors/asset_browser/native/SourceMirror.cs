using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

// 원본은 읽기만 하며 안정된 파일만 프리뷰 캐시에 반영한다.
internal sealed class SourceMirror
{
    public readonly string Source;
    public readonly string Cache;
    private readonly Dictionary<string, string> stamps = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    private Dictionary<string, string> previous = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> previousMissing = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> scriptPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    public readonly Dictionary<string, string> Labels = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

    public SourceMirror(string source, string cache)
    {
        Source = Path.GetFullPath(source);
        Cache = Path.GetFullPath(cache);
        if (Inside(Cache, Source) || Inside(Source, Cache)) throw new IOException("원본과 프리뷰 캐시가 겹칩니다.");
        var saved = JsonStore.Read(Path.Combine(Cache, "live_source_index.json")) as Dictionary<string, object>;
        if (saved != null && JsonStore.Setting(saved, "source", "") == Source)
        {
            var files = saved["files"] as Dictionary<string, object>;
            if (files != null) foreach (var entry in files) stamps[entry.Key] = Convert.ToString(entry.Value);
        }
        var catalog = JsonStore.Read(Path.Combine(Cache, "catalog.json")) as Dictionary<string, object>;
        if (catalog != null)
        {
            var entries = catalog["entries"] as object[];
            if (entries != null) foreach (Dictionary<string, object> entry in entries)
            {
                string path = Convert.ToString(entry["path"]);
                Labels[path] = Convert.ToString(entry["name"]);
                if (path.StartsWith("res://assets/") || path.StartsWith("res://shaders/"))
                    if (!stamps.ContainsKey(path.Substring(6))) stamps[path.Substring(6)] = "";
            }
        }
    }

    public static bool Inside(string path, string folder)
    {
        return path.Equals(folder, StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith(folder.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    public static IEnumerable<string> Files(string folder)
    {
        if (!Directory.Exists(folder)) yield break;
        var pending = new Stack<string>();
        pending.Push(folder);
        while (pending.Count != 0)
        {
            string current = pending.Pop();
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) continue;
            foreach (string file in Directory.GetFiles(current))
                if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) == 0) yield return file;
            foreach (string child in Directory.GetDirectories(current))
                if (!Path.GetFileName(child).StartsWith(".")) pending.Push(child);
        }
    }

    private static string Stamp(string file)
    {
        var info = new FileInfo(file);
        return info.Length + ":" + info.LastWriteTimeUtc.Ticks;
    }

    private static bool VisibleFile(string file)
    {
        string name = Path.GetFileName(file);
        return !name.StartsWith(".") && !name.EndsWith(".assetpreviewtmp") &&
            !new[] { ".import", ".uid", ".tmp", ".part" }.Contains(Path.GetExtension(file).ToLowerInvariant());
    }

    private Dictionary<string, string> Collect()
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (string folder in new[] { "assets", "shaders" })
            foreach (string file in Files(Path.Combine(Source, folder)))
                if (VisibleFile(file)) result[Relative(file)] = Stamp(file);
        var scripts = new Queue<string>(new[] {
            "railway_train_builder", "railway_track_builder", "railway_route", "building_mesh_builder",
            "campus_building_policy", "campus_architecture_builder", "building_courtyard_builder", "campus_ground_overlay"
        }.Select(name => "scripts/terrain/" + name + ".gd"));
        // 새 텍스트 씬이 참조하는 스크립트도 원본 경로를 유지하여 복사한다.
        foreach (string relative in result.Keys.Where(path => new[] { ".tscn", ".tres", ".scn", ".res" }.Contains(Path.GetExtension(path))).ToArray())
            foreach (Match match in Regex.Matches(File.ReadAllText(Path.Combine(Source, relative)), "res://([^\"\\s\\x00]+\\.gd)"))
                scripts.Enqueue(match.Groups[1].Value);
        scriptPaths.Clear();
        while (scripts.Count > 0)
        {
            string relative = scripts.Dequeue().Replace('\\', '/');
            string path = Path.GetFullPath(Path.Combine(Source, relative));
            if (!relative.StartsWith("scripts/") || !Inside(path, Source) || !scriptPaths.Add(relative) || !File.Exists(path)) continue;
            // 프리뷰 고유 모듈의 경로는 원본 파일로 덮어쓰지 않는다.
            if (relative == "scripts/core/browser.gd" || relative == "scripts/core/procedural_factory.gd" ||
                relative == "scripts/core/live_catalog.gd" || relative == "scripts/views/model_preview.gd") continue;
            result[relative] = Stamp(path);
            foreach (Match match in Regex.Matches(File.ReadAllText(path), "res://([^\"\\s]+\\.gd)"))
                scripts.Enqueue(match.Groups[1].Value);
        }
        return result;
    }

    private string Relative(string path)
    {
        string full = Path.GetFullPath(path);
        if (!Inside(full, Source)) throw new IOException("원본 경로 범위를 벗어났습니다.");
        return full.Substring(Source.TrimEnd(Path.DirectorySeparatorChar).Length + 1).Replace('\\', '/');
    }

    private static string Hash(string path)
    {
        using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        using (var hash = SHA256.Create()) return Convert.ToBase64String(hash.ComputeHash(stream));
    }

    private bool MirrorFile(string relative, string expected)
    {
        string source = Path.GetFullPath(Path.Combine(Source, relative));
        string target = Path.GetFullPath(Path.Combine(Cache, relative));
        if (!Inside(target, Cache) || !Inside(source, Source)) throw new IOException("복사 경로 검증 실패");
        string sourceHash = Hash(source);
        if (File.Exists(target) && new FileInfo(target).Length == new FileInfo(source).Length && Hash(target) == sourceHash)
        {
            if (Stamp(source) != expected) throw new IOException("원본 파일 쓰기가 진행 중입니다.");
            return false;
        }
        Directory.CreateDirectory(Path.GetDirectoryName(target));
        string temporary = Path.Combine(Path.GetDirectoryName(target), ".ap_" + Guid.NewGuid().ToString("N").Substring(0,8) + ".assetpreviewtmp");
        try
        {
            using (var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) input.CopyTo(output);
            if (Stamp(source) != expected || Hash(temporary) != sourceHash) throw new IOException("원본 파일 쓰기가 진행 중입니다.");
            if (relative == "scripts/terrain/campus_ground_overlay.gd")
                File.WriteAllText(temporary, File.ReadAllText(temporary).Replace("var image := Image.load_from_file(path)",
                    "var texture := load(path) as Texture2D\n\tvar image := texture.get_image() if texture != null else null"), new UTF8Encoding(false));
            File.SetLastWriteTimeUtc(temporary, File.GetLastWriteTimeUtc(source));
            JsonStore.Replace(temporary, target);
            return true;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    public List<string> Scan()
    {
        var current = Collect();
        var changed = new List<string>();
        foreach (var file in current)
        {
            string old, observation;
            if (stamps.TryGetValue(file.Key, out old) && old == file.Value) continue;
            if (!previous.TryGetValue(file.Key, out observation) || observation != file.Value) continue;
            try
            {
                if (MirrorFile(file.Key, file.Value)) changed.Add(file.Key);
                stamps[file.Key] = file.Value;
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        foreach (string relative in stamps.Keys.Where(key => !current.ContainsKey(key)).ToArray())
        {
            if (!previousMissing.Contains(relative)) continue;
            string target = Path.GetFullPath(Path.Combine(Cache, relative));
            if (!Inside(target, Cache) || !(relative.StartsWith("assets/") || relative.StartsWith("shaders/") || relative.StartsWith("scripts/terrain/"))) continue;
            try
            {
                if (File.Exists(target)) File.Delete(target);
                stamps.Remove(relative);
                changed.Add(relative);
            }
            catch (IOException) { }
        }
        previousMissing.Clear();
        foreach (string relative in stamps.Keys.Where(key => !current.ContainsKey(key))) previousMissing.Add(relative);
        previous = current;
        return changed;
    }

    public void Save()
    {
        JsonStore.Write(Path.Combine(Cache, "live_source_index.json"), new { source = Source, files = stamps });
    }

    public object[] Entries()
    {
        var entries = new List<object>();
        foreach (string relative in stamps.Keys.OrderBy(value => value))
        {
            if (!(relative.StartsWith("assets/") || relative.StartsWith("shaders/"))) continue;
            string file = Path.Combine(Cache, relative);
            if (!File.Exists(file)) continue;
            string path = "res://" + relative, name;
            if (!Labels.TryGetValue(path, out name)) name = Path.GetFileNameWithoutExtension(file);
            string extension = Path.GetExtension(file).ToLowerInvariant();
            string kind = relative.StartsWith("shaders/") ? "셰이더" :
                new[] { ".scn", ".tscn", ".glb", ".gltf", ".obj" }.Contains(extension) ? "3D" :
                new[] { ".png", ".jpg", ".jpeg", ".svg", ".webp" }.Contains(extension) ? "이미지" : "데이터";
            entries.Add(new { name = name, path = path, kind = kind, size = new FileInfo(file).Length });
        }
        string servicesPath = Path.Combine(Cache, "assets/generated/railway/services.json");
        var services = JsonStore.Read(servicesPath) as Dictionary<string, object>;
        if (services != null && services.ContainsKey("services"))
            foreach (Dictionary<string, object> service in (object[])services["services"])
                foreach (string kind in new[] { "train", "track" })
                    entries.Add(new { name = Convert.ToString(service["name"]) + " · " + (kind == "train" ? "열차" : "철도"), path = kind + ":" + service["id"], kind = "생성 모델", size = 0 });
        foreach (var item in new Dictionary<string, string> { { "campus", "울산대학교 · 과학대 캠퍼스" }, { "buildings", "일반 건물 · 게임 메시 생성기" }, { "water", "간몬 수면 · 게임 셰이더" } })
            entries.Add(new { name = item.Value, path = item.Key + ":preview", kind = "생성 모델", size = 0 });
        return entries.ToArray();
    }
}

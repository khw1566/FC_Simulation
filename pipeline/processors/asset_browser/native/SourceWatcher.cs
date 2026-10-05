using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Collections.Generic;

// 복사, 임포트, 목록 공개를 한 번에 한 작업만 수행한다.
internal sealed class SourceWatcher
{
    private readonly SourceMirror mirror;
    private readonly ResourceImporter importer;
    private readonly HashSet<string> pending = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    private long revision = DateTime.UtcNow.Ticks;
    private bool initialized;

    public SourceWatcher(string root, string engine, string source, string cache)
    {
        mirror = new SourceMirror(source, cache);
        importer = new ResourceImporter(root, engine, cache);
        var saved = JsonStore.Read(Path.Combine(cache, "live_pending.json")) as object[];
        if (saved != null) foreach (object file in saved) pending.Add(Convert.ToString(file));
    }

    private void Status(string state, string message)
    {
        JsonStore.Write(Path.Combine(mirror.Cache, "live_status.json"), new { state = state, message = message, source = mirror.Source, updated_at = DateTime.UtcNow.ToString("o") });
    }

    public void Step()
    {
        if (!Directory.Exists(Path.Combine(mirror.Source, "assets")))
        {
            Status("offline", "원본 폴더를 찾을 수 없어 마지막 복사본을 표시합니다.");
            return;
        }
        try
        {
            foreach (string file in mirror.Scan()) pending.Add(file);
            JsonStore.Write(Path.Combine(mirror.Cache, "live_pending.json"), pending.ToArray());
            mirror.Save();
            if (pending.Count > 0)
            {
                Status("importing", "변경 " + pending.Count + "개 반영 중 · 기존 프리뷰를 계속 사용할 수 있습니다.");
                if (!importer.Import(pending))
                {
                    Status("retry", "임포트가 완료되지 않았습니다. 기존 목록을 유지하고 다시 시도합니다.");
                    return;
                }
            }
            if (!initialized || pending.Count > 0)
            {
                object[] entries = mirror.Entries();
                JsonStore.Write(Path.Combine(mirror.Cache, "catalog.json"), new { created_at = DateTime.Now.ToString("o"), entries = entries, file_count = entries.Length });
                JsonStore.Write(Path.Combine(mirror.Cache, "live_state.json"), new { revision = (++revision).ToString(), changed = pending.ToArray() });
                pending.Clear();
                JsonStore.Write(Path.Combine(mirror.Cache, "live_pending.json"), pending.ToArray());
                initialized = true;
            }
            Status("ready", "자동 최신화 · 3초 간격 확인 · 마지막 확인 " + DateTime.Now.ToString("HH:mm:ss"));
        }
        catch (IOException error) { Status("retry", "파일 반영을 재시도합니다: " + error.Message); }
        catch (UnauthorizedAccessException) { Status("retry", "원본을 읽을 수 없어 기존 프리뷰를 유지합니다."); }
        catch (Exception error) { Status("retry", "변경 반영을 재시도합니다: " + error.Message); }
    }

    public void Run(WaitHandle stopping)
    {
        importer.Stopping = stopping;
        while (!stopping.WaitOne(0))
        {
            try { Step(); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            stopping.WaitOne(3000);
        }
    }
}

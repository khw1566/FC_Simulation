using System;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
using System.Collections.Generic;

// 프리뷰 전용 JSON 상태를 원자적으로 교체한다.
internal static class JsonStore
{
    public static object Read(string path)
    {
        try { return new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue }.DeserializeObject(File.ReadAllText(path, Encoding.UTF8)); }
        catch (IOException) { return null; }
        catch (ArgumentException) { return null; }
    }

    public static void Write(string path, object value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".assetpreviewtmp";
        try
        {
            File.WriteAllText(temporary, new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue }.Serialize(value), new UTF8Encoding(false));
            Replace(temporary, path);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    public static void Replace(string temporary, string target)
    {
        for (int attempt = 0; attempt < 8; attempt++)
        {
            try
            {
                if (File.Exists(target)) File.Replace(temporary, target, null);
                else File.Move(temporary, target);
                return;
            }
            catch (IOException)
            {
                if (attempt == 7) throw;
                System.Threading.Thread.Sleep(30 * (attempt + 1));
            }
        }
    }

    public static string Setting(Dictionary<string, object> settings, string key, string fallback)
    {
        object value;
        return settings != null && settings.TryGetValue(key, out value) ? Convert.ToString(value) : fallback;
    }
}

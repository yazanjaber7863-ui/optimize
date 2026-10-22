// Optimize.exe: a small launcher that carries the compiled winutil.ps1 inside it.
//
// The manifest asks Windows for admin rights when the exe is opened, so PowerShell starts
// elevated and Optimize does not have to relaunch itself. The script is written to the temp
// folder as winutil-<random>.ps1, the name Optimize already deletes when it closes.
//
// Opened without arguments, it first checks GitHub for a newer release and offers to update
// itself. BuildInfo.Version is written by Build-OptimizeExe.ps1.
//
// Built by Build-OptimizeExe.ps1 with the C# compiler that ships with Windows.

using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

[assembly: AssemblyTitle("Optimize")]
[assembly: AssemblyProduct("Optimize")]
[assembly: AssemblyDescription("Windows setup, tweak and cleanup tool")]
[assembly: AssemblyCompany("yazanjaber7863-ui")]
[assembly: AssemblyCopyright("MIT license. Based on WinUtil by Chris Titus Tech.")]

static class Program
{
    const string LatestRelease = "https://api.github.com/repos/yazanjaber7863-ui/optimize/releases/latest";

    [STAThread]
    static int Main(string[] args)
    {
        string exe = Assembly.GetExecutingAssembly().Location;
        RemoveLeftoverFromUpdate(exe);

        // With arguments it is being run by a script or a preset, which must not stop on a question
        if (args.Length == 0 && UpdateIfNewer(exe))
        {
            return 0;
        }

        try
        {
            string script = Path.Combine(Path.GetTempPath(), "winutil-" + Guid.NewGuid().ToString("N") + ".ps1");
            using (Stream embedded = Assembly.GetExecutingAssembly().GetManifestResourceStream("winutil.ps1"))
            using (FileStream file = File.Create(script))
            {
                embedded.CopyTo(file);
            }

            ProcessStartInfo start = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"" + QuoteArguments(args),
                UseShellExecute = true,
                // The log console stays reachable on the taskbar without covering the app
                WindowStyle = ProcessWindowStyle.Minimized,
            };
            Process.Start(start);
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show("Optimize could not start:\n\n" + error.Message, "Optimize", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    // Arguments such as -Preset MySetup are handed on, each quoted
    static string QuoteArguments(string[] args)
    {
        StringBuilder quoted = new StringBuilder();
        foreach (string arg in args)
        {
            quoted.Append(" \"").Append(arg.Replace("\"", "\\\"")).Append('"');
        }
        return quoted.ToString();
    }

    // Returns true when a newer exe was put in place and started, so this one should exit
    static bool UpdateIfNewer(string exe)
    {
        string newFile = exe + ".new";
        string oldFile = OldPath(exe);
        bool moved = false;
        try
        {
            // .NET Framework 4 does not offer TLS 1.2 by default, and GitHub requires it
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;

            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(LatestRelease);
            request.UserAgent = "Optimize-Launcher";
            request.Timeout = 4000;
            request.ReadWriteTimeout = 4000;
            string json;
            using (WebResponse response = request.GetResponse())
            using (StreamReader reader = new StreamReader(response.GetResponseStream()))
            {
                json = reader.ReadToEnd();
            }

            string tag = Regex.Match(json, "\"tag_name\"\\s*:\\s*\"([^\"]+)\"").Groups[1].Value;
            string url = Regex.Match(json, "\"browser_download_url\"\\s*:\\s*\"([^\"]+/Optimize\\.exe)\"").Groups[1].Value;
            Version latest, current;
            if (url.Length == 0 || !Version.TryParse(tag.TrimStart('v'), out latest) ||
                !Version.TryParse(BuildInfo.Version, out current) || latest <= current)
            {
                return false;
            }

            DialogResult answer = MessageBox.Show(
                "A newer Optimize is out: " + tag + " (you have " + BuildInfo.Version + ").\n\nUpdate now? It takes a few seconds.",
                "Optimize update", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (answer != DialogResult.Yes)
            {
                return false;
            }

            using (WebClient client = new WebClient())
            {
                client.Headers[HttpRequestHeader.UserAgent] = "Optimize-Launcher";
                client.DownloadFile(url, newFile);
            }

            // A real exe starts with "MZ"; an error page or a cut-off download does not
            byte[] head = new byte[2];
            using (FileStream check = File.OpenRead(newFile))
            {
                if (check.Length < 100 * 1024 || check.Read(head, 0, 2) != 2 || head[0] != 'M' || head[1] != 'Z')
                {
                    throw new InvalidDataException("the download was not a complete Optimize.exe");
                }
            }

            // A running exe cannot be overwritten, but it can be renamed out of the way
            if (File.Exists(oldFile)) File.Delete(oldFile);
            File.Move(exe, oldFile);
            moved = true;
            File.Move(newFile, exe);

            Process.Start(new ProcessStartInfo { FileName = exe, UseShellExecute = true });
            return true;
        }
        catch (Exception error)
        {
            try
            {
                if (moved && !File.Exists(exe)) File.Move(oldFile, exe);
                if (File.Exists(newFile)) File.Delete(newFile);
            }
            catch { }
            // Offline or GitHub unreachable: carry on with this version without bothering anyone
            if (error is WebException) return false;
            MessageBox.Show("The update did not work, so this version opens instead.\n\n" + error.Message,
                "Optimize update", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }
    }

    static string OldPath(string exe)
    {
        return Path.Combine(Path.GetDirectoryName(exe), Path.GetFileNameWithoutExtension(exe) + ".old.exe");
    }

    // The previous version, renamed out of the way during an update, can go once it has exited
    static void RemoveLeftoverFromUpdate(string exe)
    {
        try
        {
            string oldFile = OldPath(exe);
            if (File.Exists(oldFile)) File.Delete(oldFile);
        }
        catch { }
    }
}

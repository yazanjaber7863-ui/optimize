// Optimize.exe: a small launcher that carries the compiled winutil.ps1 inside it.
//
// The manifest asks Windows for admin rights when the exe is opened, so PowerShell starts
// elevated and Optimize does not have to relaunch itself. The script is written to the temp
// folder as winutil-<random>.ps1, the name Optimize already deletes when it closes.
//
// Built by Build-OptimizeExe.ps1 with the C# compiler that ships with Windows.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Optimize")]
[assembly: AssemblyProduct("Optimize")]
[assembly: AssemblyDescription("Windows setup, tweak and cleanup tool")]
[assembly: AssemblyCompany("yazanjaber7863-ui")]
[assembly: AssemblyCopyright("MIT license. Based on WinUtil by Chris Titus Tech.")]

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            string script = Path.Combine(Path.GetTempPath(), "winutil-" + Guid.NewGuid().ToString("N") + ".ps1");
            using (Stream embedded = Assembly.GetExecutingAssembly().GetManifestResourceStream("winutil.ps1"))
            using (FileStream file = File.Create(script))
            {
                embedded.CopyTo(file);
            }

            // Arguments such as -Preset MySetup are handed on to Optimize
            StringBuilder arguments = new StringBuilder("-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"");
            foreach (string arg in args)
            {
                arguments.Append(" \"").Append(arg.Replace("\"", "\\\"")).Append('"');
            }

            ProcessStartInfo start = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = arguments.ToString(),
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
}

// LazyBicep by Netmedia (https://netmedia.agency, netmedia@netmedia.hr).
//
// The launcher behind lazybicep.exe and initintoproject.exe: it runs the PowerShell script of the same
// name next to it (lazybicep.exe -> lazybicep.ps1) with every argument, in the same console, and returns
// its exit code. The .ps1 stays the program; the .exe only starts it (built by build-exe.ps1).
//
// C# 5 (the compiler that comes with Windows): C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

[assembly: AssemblyTitle("LazyBicep")]
[assembly: AssemblyDescription("LazyBicep by Netmedia: starts the PowerShell script of the same name next to it")]
[assembly: AssemblyCompany("Netmedia")]
[assembly: AssemblyProduct("LazyBicep")]
[assembly: AssemblyCopyright("Netmedia - https://netmedia.agency - netmedia@netmedia.hr")]
[assembly: AssemblyVersion(LazyBicepLauncher.Version)]
[assembly: AssemblyFileVersion(LazyBicepLauncher.Version)]
[assembly: AssemblyInformationalVersion(LazyBicepLauncher.Version)]

static class LazyBicepLauncher
{
    public const string Version = "0.1.0.0";

    static int Main(string[] args)
    {
        string exe = Assembly.GetExecutingAssembly().Location;
        string name = Path.GetFileNameWithoutExtension(exe) + ".ps1";
        string dir = Path.GetDirectoryName(exe);
        // Next to it (infra\lazybicep.exe), or in infra\ below it (the project root's lazybicep.exe).
        string script = Path.Combine(dir, name);
        if (!File.Exists(script)) { script = Path.Combine(Path.Combine(dir, "infra"), name); }
        if (!File.Exists(script))
        {
            Console.Error.WriteLine("LazyBicep (Netmedia): " + name + " is missing next to " + Path.GetFileName(exe) + " and in infra\\ below it.");
            Console.Error.WriteLine("The .exe only starts the .ps1 of the same name; keep them together.");
            return 1;
        }

        StringBuilder line = new StringBuilder("-NoProfile -ExecutionPolicy Bypass -File ");
        line.Append(Quote(script));
        foreach (string a in args) { line.Append(' ').Append(Quote(a)); }

        ProcessStartInfo start = new ProcessStartInfo(PowerShell(), line.ToString());
        start.UseShellExecute = false; // the same console: colours, keys, the terminal UI
        start.WorkingDirectory = Environment.CurrentDirectory;

        // Ctrl+C is the script's to handle (lazybicep asks before it stops a run).
        Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e) { e.Cancel = true; };

        try
        {
            using (Process p = Process.Start(start))
            {
                p.WaitForExit();
                return p.ExitCode;
            }
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("LazyBicep (Netmedia): can't start PowerShell: " + e.Message);
            return 1;
        }
    }

    // Windows PowerShell 5.1, which every Windows has (the scripts also run in PowerShell 7).
    static string PowerShell()
    {
        string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        return File.Exists(path) ? path : "powershell.exe";
    }

    // One argument as Windows splits command lines: quoted when needed, backslashes before quotes doubled.
    static string Quote(string arg)
    {
        if (arg.Length > 0 && arg.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) { return arg; }
        StringBuilder sb = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in arg)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { sb.Append('\\', slashes * 2 + 1); }
            else { sb.Append('\\', slashes); }
            slashes = 0;
            sb.Append(c);
        }
        sb.Append('\\', slashes * 2);
        return sb.Append('"').ToString();
    }
}

// CaesiumPortable community launcher. Copyright (c) 2026. MIT license.
// NO global AppData overrides. Scoped, journaled preservation of Caesium's own
// reported HKCU key and two app-specific folders. Avoid running an installed
// Caesium concurrently. No automatic Windows-wide cleanup.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System.Security.Principal;
using Microsoft.Win32;

internal static class CaesiumPortable
{
    const string RegSubkey = @"Software\SaeraSoft\Caesium Image Compressor";
    const string RegParent = @"Software\SaeraSoft";
    const string AppSubpath = @"SaeraSoft\Caesium Image Compressor";
    const string Marker = ".caesium-portable-owned";
    static string Root, Data, Recovery, Target, RoamingHost, LocalHost;
    static string RoamingBackup, LocalBackup, OriginalReg, Journal;
    static bool HadRoaming, HadLocal, HadRegistry;
    // Only remove empty containers newly created by THIS launch.
    static bool HadRoamingParent, HadLocalParent, HadRegistryParent;
    static string MachineIdentity;

    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            Root = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
            Data = Path.Combine(Root, "Data");
            Recovery = Path.Combine(Data, "Recovery");
            Journal = Path.Combine(Recovery, "active.txt");
            OriginalReg = Path.Combine(Recovery, "host-original.reg");
            string selected = Path.Combine(Root, "Other", "Launcher", "target.txt");
            if (!File.Exists(selected)) throw new InvalidOperationException("Missing Other/Launcher/target.txt. Rebuild the package.");
            string relative = File.ReadAllText(selected).Trim().Replace('/', Path.DirectorySeparatorChar);
            string appRoot = Path.GetFullPath(Path.Combine(Root, "App", "Caesium"));
            Target = Path.GetFullPath(Path.Combine(appRoot, relative));
            if (!Target.StartsWith(appRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || !File.Exists(Target))
                throw new InvalidOperationException("Official Caesium executable is missing or outside App/Caesium: " + relative);
            RoamingHost = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), AppSubpath);
            LocalHost = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), AppSubpath);
            string sid = WindowsIdentity.GetCurrent().User.Value;
            MachineIdentity = Environment.MachineName + "|" + sid;
            if (args.Length == 1 && args[0] == "--self-test")
                return File.Exists(Path.Combine(Root, "App", "AppInfo", "appinfo.ini")) ? 0 : 12;
            Directory.CreateDirectory(Data);
            bool owns;
            using (Mutex mutex = new Mutex(true, @"Local\CaesiumPortableSharedHostPaths", out owns))
            {
                if (!owns) throw new InvalidOperationException("A Caesium portable launcher is already running on this Windows account. Close it first.");
                try { return Run(args); }
                finally { mutex.ReleaseMutex(); }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Caesium Portable", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    static int Run(string[] args)
    {
        string procName = Path.GetFileNameWithoutExtension(Target);
        if (Process.GetProcessesByName(procName).Length > 0)
            throw new InvalidOperationException("Close the other Caesium instance before launching the portable version. Concurrent instances could overwrite settings.");

        if (File.Exists(Journal))
        {
            LoadJournal();
            if (MachineIdentity != ReadJournalIdentity())
                throw new InvalidOperationException("An interrupted Caesium session belongs to another PC/account. Keep the Recovery folder and restore it on that PC first. No host files have been changed.");
            RestoreAndCapture();
        }
        int exitCode = 0;
        try
        {
            BeginSession();
            ProcessStartInfo p = new ProcessStartInfo(Target);
            p.WorkingDirectory = Path.GetDirectoryName(Target);
            p.UseShellExecute = false;
            p.Arguments = QuoteArgs(args);
            string temp = Path.Combine(Data, "Temp");
            Directory.CreateDirectory(temp);
            p.EnvironmentVariables["TEMP"] = temp;
            p.EnvironmentVariables["TMP"] = temp;
            using (Process child = Process.Start(p))
            {
                if (child == null) throw new InvalidOperationException("Caesium could not start.");
                child.WaitForExit();
                exitCode = child.ExitCode;
            }
            if (Process.GetProcessesByName(procName).Length > 0)
                throw new InvalidOperationException("Caesium still has a running process. The portable settings will be restored on the next clean launch. Exit Caesium first.");
        }
        finally { RestoreAndCapture(); }
        return exitCode;
    }

    static string QuoteArgs(string[] args)
    {
        StringBuilder sb = new StringBuilder();
        foreach (string a in args)
        {
            if (sb.Length > 0) sb.Append(' ');
            sb.Append('"');
            int bs = 0;
            foreach (char ch in a)
            {
                if (ch == '\\') { bs++; continue; }
                if (ch == '"') { sb.Append('\\', bs * 2 + 1); sb.Append('"'); bs = 0; continue; }
                sb.Append('\\', bs); bs = 0; sb.Append(ch);
            }
            sb.Append('\\', bs * 2); sb.Append('"');
        }
        return sb.ToString();
    }

    static void BeginSession()
    {
        Directory.CreateDirectory(Recovery);
        RoamingBackup = RoamingHost + ".CaesiumPortableHostBackup";
        LocalBackup = LocalHost + ".CaesiumPortableHostBackup";
        if (Directory.Exists(RoamingBackup) || Directory.Exists(LocalBackup) || File.Exists(OriginalReg))
            throw new InvalidOperationException("A previous host backup exists but its recovery journal is missing. No files were changed. Inspect the CaesiumPortableHostBackup folders before continuing.");
        HadRoaming = Directory.Exists(RoamingHost);
        HadLocal = Directory.Exists(LocalHost);
        HadRegistry = HasKey();
        HadRoamingParent = Directory.Exists(Path.GetDirectoryName(RoamingHost));
        HadLocalParent = Directory.Exists(Path.GetDirectoryName(LocalHost));
        HadRegistryParent = HasParentKey();
        WriteJournal(); // save recovery info BEFORE touching Windows

        PrepareFolder(RoamingHost, RoamingBackup, Path.Combine(Data, "Roaming"), HadRoaming);
        PrepareFolder(LocalHost, LocalBackup, Path.Combine(Data, "Local"), HadLocal);
        if (HadRegistry) ExportReg(OriginalReg);
        if (HasKey()) Registry.CurrentUser.DeleteSubKeyTree(RegSubkey, false);
        string portableReg = Path.Combine(Data, "Settings", "registry.reg");
        if (File.Exists(portableReg)) ImportReg(portableReg);
    }

    static void PrepareFolder(string host, string backup, string portable, bool previouslyExists)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(host));
        if (previouslyExists) Directory.Move(host, backup);
        Directory.CreateDirectory(host);
        if (Directory.Exists(portable)) CopyDirectory(portable, host, true);
        File.WriteAllText(Path.Combine(host, Marker), "Owned by CaesiumPortable. Do not remove while running.");
    }

    static void RestoreAndCapture()
    {
        if (!File.Exists(Journal)) return;
        // Never touch a different PC/account's current user settings.
        LoadJournal();
        if (MachineIdentity != ReadJournalIdentity())
            throw new InvalidOperationException("Recovery was created by another Windows account/PC. Host data was not changed.");
        string procName = Path.GetFileNameWithoutExtension(Target);
        if (Process.GetProcessesByName(procName).Length > 0)
            throw new InvalidOperationException("Caesium is still running; refusing to restore while it is writing settings.");

        // Capture portable registry only if the app-created key may be present.
        if (HasKey() && (!HadRegistry || File.Exists(OriginalReg)))
        {
            string regDir = Path.Combine(Data, "Settings");
            Directory.CreateDirectory(regDir);
            ExportReg(Path.Combine(regDir, "registry.reg"));
            Registry.CurrentUser.DeleteSubKeyTree(RegSubkey, false);
        }
        // Restore the pre-existing registry state exactly; never delete parent SaeraSoft.
        if (HadRegistry && File.Exists(OriginalReg)) ImportReg(OriginalReg);
        RecoverFolder(RoamingHost, RoamingBackup, Path.Combine(Data, "Roaming"), HadRoaming);
        RecoverFolder(LocalHost, LocalBackup, Path.Combine(Data, "Local"), HadLocal);
        // Do not remove parents that existed BEFORE this launch, even if empty.
        // Never delete non-empty parents: other SaeraSoft tools may share them.
        if (!HadRoamingParent) RemoveNewEmptyFolderParent(Path.GetDirectoryName(RoamingHost));
        if (!HadLocalParent) RemoveNewEmptyFolderParent(Path.GetDirectoryName(LocalHost));
        if (!HadRegistryParent) RemoveNewEmptyRegistryParent();
        if (File.Exists(OriginalReg)) File.Delete(OriginalReg);
        File.Delete(Journal);
        // Recovery directory is left empty for easy inspection.
    }

    static void RecoverFolder(string host, string backup, string portable, bool hadHost)
    {
        bool owned = File.Exists(Path.Combine(host, Marker));
        if (owned)
        {
            CopyOutDirectory(host, portable);
            Directory.Delete(host, true);
        }
        if (hadHost && Directory.Exists(backup))
        {
            if (Directory.Exists(host)) throw new InvalidOperationException("Refusing to overwrite an existing host Caesium directory: " + host);
            Directory.Move(backup, host);
        }
        // If the original host folder never existed, do not remove unmarked data.
    }

    static void CopyOutDirectory(string host, string portable)
    {
        string staging = portable + ".pending";
        string previous = portable + ".previous";
        if (Directory.Exists(staging)) Directory.Delete(staging, true);
        Directory.CreateDirectory(staging);
        CopyDirectory(host, staging, false);
        if (Directory.Exists(previous)) Directory.Delete(previous, true);
        if (Directory.Exists(portable)) Directory.Move(portable, previous);
        Directory.Move(staging, portable);
        if (Directory.Exists(previous)) Directory.Delete(previous, true);
    }

    static void CopyDirectory(string src, string dst, bool includeMarker)
    {
        Directory.CreateDirectory(dst);
        foreach (string file in Directory.GetFiles(src))
        {
            if (!includeMarker && Path.GetFileName(file).Equals(Marker, StringComparison.OrdinalIgnoreCase)) continue;
            File.Copy(file, Path.Combine(dst, Path.GetFileName(file)), true);
        }
        foreach (string directory in Directory.GetDirectories(src))
            CopyDirectory(directory, Path.Combine(dst, Path.GetFileName(directory)), includeMarker);
    }

    static void RemoveNewEmptyFolderParent(string parent)
    {
        try
        {
            if (!Directory.Exists(parent)) return;
            DirectoryInfo info = new DirectoryInfo(parent);
            // Refuse symlinks and reparse points, regardless of directory emptiness.
            if ((info.Attributes & FileAttributes.ReparsePoint) != 0) return;
            if (Directory.GetFileSystemEntries(parent).Length == 0)
                Directory.Delete(parent, false); // never recursive
        }
        catch (IOException) { /* Keep parent if it is in use or changed. */ }
        catch (UnauthorizedAccessException) { /* Never elevate for cleanup. */ }
        catch (System.Security.SecurityException) { }
    }

    static bool HasParentKey()
    {
        using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RegParent)) return k != null;
    }

    static void RemoveNewEmptyRegistryParent()
    {
        try
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RegParent, false))
            {
                if (k == null || k.SubKeyCount != 0 || k.ValueCount != 0) return;
            }
            // DeleteSubKey refuses non-empty subkey trees (unlike DeleteSubKeyTree).
            Registry.CurrentUser.DeleteSubKey(RegParent, false);
        }
        catch (IOException) { /* Keep existing or concurrently created contents. */ }
        catch (UnauthorizedAccessException) { }
        catch (System.Security.SecurityException) { }
        catch (ArgumentException) { }
    }

    static bool HasKey()
    {
        using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RegSubkey)) return k != null;
    }
    static void ExportReg(string to)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(to));
        RunReg("export \"HKCU\\" + RegSubkey + "\" \"" + to + "\" /y");
    }
    static void ImportReg(string from) { RunReg("import \"" + from + "\""); }
    static void RunReg(string args)
    {
        ProcessStartInfo p = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "reg.exe"), args);
        p.UseShellExecute = false; p.CreateNoWindow = true;
        using (Process proc = Process.Start(p))
        {
            if (proc == null) throw new InvalidOperationException("Failed to start reg.exe.");
            proc.WaitForExit();
            if (proc.ExitCode != 0) throw new InvalidOperationException("Windows registry operation failed with exit code " + proc.ExitCode + ": " + args);
        }
    }
    static void WriteJournal()
    {
        // Escaping Base64 avoids misparsing Unicode paths and separators.
        string[] values = {
            "Owner=" + Convert.ToBase64String(Encoding.UTF8.GetBytes(MachineIdentity)),
            "HadRoaming=" + HadRoaming,
            "HadLocal=" + HadLocal,
            "HadRegistry=" + HadRegistry,
            "HadRoamingParent=" + HadRoamingParent,
            "HadLocalParent=" + HadLocalParent,
            "HadRegistryParent=" + HadRegistryParent,
            "RoamingBackup=" + Convert.ToBase64String(Encoding.UTF8.GetBytes(RoamingBackup)),
            "LocalBackup=" + Convert.ToBase64String(Encoding.UTF8.GetBytes(LocalBackup))
        };
        string tmp = Journal + ".new";
        File.WriteAllLines(tmp, values, Encoding.UTF8);
        if (File.Exists(Journal)) File.Delete(Journal);
        File.Move(tmp, Journal);
    }
    static string ReadJournalIdentity()
    {
        foreach (string line in File.ReadAllLines(Journal, Encoding.UTF8))
            if (line.StartsWith("Owner=")) return Encoding.UTF8.GetString(Convert.FromBase64String(line.Substring(6)));
        throw new InvalidOperationException("Recovery journal is damaged; refusing to modify host settings.");
    }
    static void LoadJournal()
    {
        // v1.0 recovery journals have no parent flags. Assume those parents
        // existed so upgrading during an interrupted session cannot delete them.
        HadRoamingParent = true;
        HadLocalParent = true;
        HadRegistryParent = true;
        string owner = null;
        foreach (string line in File.ReadAllLines(Journal, Encoding.UTF8))
        {
            int pos = line.IndexOf('='); if (pos < 1) continue;
            string k = line.Substring(0, pos), v = line.Substring(pos + 1);
            if (k == "Owner") owner = Encoding.UTF8.GetString(Convert.FromBase64String(v));
            else if (k == "HadRoaming") HadRoaming = bool.Parse(v);
            else if (k == "HadLocal") HadLocal = bool.Parse(v);
            else if (k == "HadRegistry") HadRegistry = bool.Parse(v);
            else if (k == "HadRoamingParent") HadRoamingParent = bool.Parse(v);
            else if (k == "HadLocalParent") HadLocalParent = bool.Parse(v);
            else if (k == "HadRegistryParent") HadRegistryParent = bool.Parse(v);
            else if (k == "RoamingBackup") RoamingBackup = Encoding.UTF8.GetString(Convert.FromBase64String(v));
            else if (k == "LocalBackup") LocalBackup = Encoding.UTF8.GetString(Convert.FromBase64String(v));
        }
        if (owner == null || RoamingBackup == null || LocalBackup == null ||
            !RoamingBackup.Equals(RoamingHost + ".CaesiumPortableHostBackup", StringComparison.OrdinalIgnoreCase) ||
            !LocalBackup.Equals(LocalHost + ".CaesiumPortableHostBackup", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Recovery journal is invalid; no host settings were changed.");
    }
}

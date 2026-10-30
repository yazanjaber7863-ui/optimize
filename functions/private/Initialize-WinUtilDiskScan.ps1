function Initialize-WinUtilDiskScan {
    <#
    .SYNOPSIS
        Compiles the drive scanner Find Big Files uses, once per session

    .DESCRIPTION
        A few lines of C#: PowerShell's own Get-ChildItem takes minutes on a full system drive.
        Folders that cannot be read are skipped, and links to other folders are not followed, so
        nothing is counted twice. [OptimizeDiskScan]::Scan returns the largest files and fills
        FolderBytes with the size of every folder up to three levels below the root.
    #>

    if ("OptimizeDiskScan" -as [type]) {
        return
    }
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;

public static class OptimizeDiskScan
{
public static long TotalBytes;
public static Dictionary<string, long> FolderBytes;

// Returns the largest files; FolderBytes gets the size of every folder up to three levels down
public static List<KeyValuePair<string, long>> Scan(string root, int keep)
{
    TotalBytes = 0;
    FolderBytes = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
    List<KeyValuePair<string, long>> largest = new List<KeyValuePair<string, long>>();
    long smallestKept = 0;
    Stack<DirectoryInfo> pending = new Stack<DirectoryInfo>();
    pending.Push(new DirectoryInfo(root));
    int rootDepth = root.TrimEnd('\\').Split('\\').Length;

    while (pending.Count > 0)
    {
        DirectoryInfo folder = pending.Pop();
        FileSystemInfo[] entries;
        try { entries = folder.GetFileSystemInfos(); }
        catch (Exception) { continue; }

        foreach (FileSystemInfo entry in entries)
        {
            if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) continue;
            DirectoryInfo subfolder = entry as DirectoryInfo;
            if (subfolder != null) { pending.Push(subfolder); continue; }

            long size;
            try { size = ((FileInfo)entry).Length; }
            catch (Exception) { continue; }
            TotalBytes += size;

            // Charge the file to each of its folders up to three levels below the root
            string[] parts = entry.FullName.Split('\\');
            for (int depth = rootDepth + 1; depth <= rootDepth + 3 && depth < parts.Length; depth++)
            {
                string key = string.Join("\\", parts, 0, depth);
                long current;
                FolderBytes.TryGetValue(key, out current);
                FolderBytes[key] = current + size;
            }

            if (largest.Count < keep || size > smallestKept)
            {
                largest.Add(new KeyValuePair<string, long>(entry.FullName, size));
                if (largest.Count > keep)
                {
                    largest.Sort((a, b) => b.Value.CompareTo(a.Value));
                    largest.RemoveAt(largest.Count - 1);
                    smallestKept = largest[largest.Count - 1].Value;
                }
            }
        }
    }
    largest.Sort((a, b) => b.Value.CompareTo(a.Value));
    return largest;
}
}
"@
}

# Caesium Portable - read-only trace audit v1.1
# Runs the existing CaesiumPortable.exe once, captures nominated AppData / registry
# locations before and after, reports names/metadata only, NEVER deletes anything.
# Compatible with Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Fail([string] $message) { throw $message }

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcher = Join-Path $root 'CaesiumPortable.exe'
if (!(Test-Path -LiteralPath $launcher -PathType Leaf)) {
    Fail 'Put Audit-CaesiumPortable.ps1 and Run-Caesium-Trace-Audit.cmd alongside CaesiumPortable.exe, then run the CMD again.'
}
$activeJournal = Join-Path $root 'Data\Recovery\active.txt'
if (Test-Path -LiteralPath $activeJournal -PathType Leaf) {
    Fail 'An unfinished CaesiumPortable recovery journal exists. Do not run the audit yet. Keep Data\Recovery intact and report this to ChatGPT.'
}
if ([string]::IsNullOrWhiteSpace($env:APPDATA) -or [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Fail 'Could not resolve Windows AppData folders.'
}
$diagnosticDir = Join-Path $root 'Data\Diagnostics'
New-Item -ItemType Directory -Force -Path $diagnosticDir | Out-Null
$now = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = Join-Path $diagnosticDir "Caesium-Trace-Audit-$now.txt"
$archive = Join-Path $diagnosticDir "Caesium-Trace-Audit-$now.zip"
$maxEntries = 18000
# Secret digest key exists only in memory for this diagnostic invocation.
# Registry values are never written to the report, even as unsalted hashes.
$privateDigestKey = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($privateDigestKey) } finally { $rng.Dispose() }

function Get-RegistryValueFingerprint($reg, [string] $name) {
    try {
        $kind = $reg.GetValueKind($name).ToString()
        $value = $reg.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $value) { $bytes = [System.Text.Encoding]::UTF8.GetBytes('<NULL>') }
        elseif ($value -is [byte[]]) { $bytes = $value }
        elseif ($value -is [string[]]) { $bytes = [System.Text.Encoding]::UTF8.GetBytes(($value -join [char]31)) }
        else { $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$value) }
        $hmac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (,$privateDigestKey)
        try { $digest = [Convert]::ToBase64String($hmac.ComputeHash($bytes)) }
        finally { $hmac.Dispose() }
        return ($kind + ':' + $digest)
    }
    catch { return ('VALUE_UNAVAILABLE:' + [string]$reg.GetValueKind($name)) }
}

# Restrict collection to likely Caesium/Qt areas, not entire user profile.
# No contents, credential values, or registry value data are read into the report.
function Get-CandidateFolderPaths {
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($base in @($env:APPDATA, $env:LOCALAPPDATA)) {
        foreach ($relative in @('SaeraSoft', 'QtProject', 'Qt', 'Caesium Image Compressor', 'Caesium')) {
            $p = Join-Path $base $relative
            if (Test-Path -LiteralPath $p -PathType Container) { $paths.Add($p) }
        }
        # A component may use a different Qt/Caesium root name.
        try {
            Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -match '(?i)caesium|saerasoft|^qt(?:project)?$'
            } | ForEach-Object { if (!$paths.Contains($_.FullName)) { $paths.Add($_.FullName) } }
        } catch { }
    }
    return @($paths | Sort-Object -Unique)
}

function Obscure-Path([string] $value) {
    $localDir = $env:LOCALAPPDATA.TrimEnd('\')
    $roamingDir = $env:APPDATA.TrimEnd('\')
    if ($value.StartsWith($localDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        return '%LOCALAPPDATA%' + $value.Substring($localDir.Length)
    }
    if ($value.StartsWith($roamingDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        return '%APPDATA%' + $value.Substring($roamingDir.Length)
    }
    return $value
}

function Get-FileSnapshot {
    $map = @{}
    foreach ($base in @(Get-CandidateFolderPaths)) {
        # Include existence of parent directory even if empty.
        $baseKey = 'DIR|' + (Obscure-Path $base)
        $map[$baseKey] = 'present'
        $count = 0
        try {
            Get-ChildItem -LiteralPath $base -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                $count++
                if ($count -le $maxEntries) {
                    $kind = if ($_.PSIsContainer) { 'DIR|' } else { 'FILE|' }
                    $key = $kind + (Obscure-Path $_.FullName)
                    if ($_.PSIsContainer) { $map[$key] = 'present' }
                    else { $map[$key] = 'bytes=' + $_.Length + ';utc=' + $_.LastWriteTimeUtc.Ticks }
                }
            }
            if ($count -gt $maxEntries) {
                $map[('LIMIT|' + (Obscure-Path $base))] = 'More than ' + $maxEntries + ' entries (truncated)'
            }
        } catch {
            $map[('ACCESS|' + (Obscure-Path $base))] = 'Could not enumerate all entries'
        }
    }
    # Also watch Caesium-specific crash dump / TEMP filenames without enumerating deep system trees.
    foreach ($pair in @(
        @{ Folder = (Join-Path $env:LOCALAPPDATA 'CrashDumps'); Label = '%LOCALAPPDATA%\CrashDumps' },
        @{ Folder = (Join-Path $env:LOCALAPPDATA 'Temp'); Label = '%LOCALAPPDATA%\Temp' }
    )) {
        if (Test-Path -LiteralPath $pair.Folder -PathType Container) {
            try {
                Get-ChildItem -LiteralPath $pair.Folder -Force -ErrorAction SilentlyContinue | Where-Object {
                    $_.Name -match '(?i)caesium|saerasoft'
                } | ForEach-Object {
                    $key = $(if ($_.PSIsContainer) { 'DIR|' } else { 'FILE|' }) + $pair.Label + '\' + $_.Name
                    $map[$key] = if ($_.PSIsContainer) { 'present' } else { 'bytes=' + $_.Length + ';utc=' + $_.LastWriteTimeUtc.Ticks }
                }
            } catch { }
        }
    }
    return $map
}

function Get-RegSnapshot {
    $map = @{}
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($s in @('Software\SaeraSoft', 'Software\QtProject', 'Software\Caesium',
                     'Software\Classes\Applications\caesium_image_compressor.exe',
                     'Software\Classes\Applications\Caesium.exe')) {
        $keys.Add($s)
    }
    # Other matching company/application names immediately under HKCU\Software.
    try {
        $software = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software')
        if ($null -ne $software) {
            foreach ($name in $software.GetSubKeyNames()) {
                if ($name -match '(?i)caesium|saerasoft|^qtproject$') {
                    $key = 'Software\' + $name
                    if (!$keys.Contains($key)) { $keys.Add($key) }
                }
            }
            $software.Close()
        }
    } catch { }
    foreach ($path in $keys) {
        try {
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
            if ($null -eq $key) { continue }
            $pending = New-Object 'System.Collections.Generic.Queue[object]'
            $pending.Enqueue(@($path, $key))
            $count = 0
            while ($pending.Count -gt 0 -and $count -lt 4000) {
                $item = $pending.Dequeue()
                [string] $subpath = $item[0]
                $reg = [Microsoft.Win32.RegistryKey] $item[1]
                $map['REGKEY|HKCU\' + $subpath] = 'present'
                foreach ($valueName in $reg.GetValueNames()) {
                    $displayName = if ($valueName -eq '') { '(Default)' } else { $valueName }
                    # Only registry value name and type; not its content.
                    $map['REGVAL|HKCU\' + $subpath + '\' + $displayName] = Get-RegistryValueFingerprint $reg $valueName
                }
                foreach ($childName in $reg.GetSubKeyNames()) {
                    try {
                        $child = $reg.OpenSubKey($childName)
                        if ($null -ne $child) {
                            $pending.Enqueue(@(($subpath + '\' + $childName), $child))
                        }
                    } catch { }
                }
                $reg.Close()
                $count++
            }
            if ($pending.Count -gt 0) { $map['LIMIT|HKCU\' + $path] = 'Registry subtree truncated' }
        } catch { $map['ACCESS|HKCU\' + $path] = 'Unable to inspect subtree' }
    }
    return $map
}

function Take-Snapshot {
    $result = Get-FileSnapshot
    $reg = Get-RegSnapshot
    foreach ($k in $reg.Keys) { $result[$k] = $reg[$k] }
    return $result
}

function List-Diff($old, $new, [string] $kind) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in @($new.Keys | Sort-Object)) {
        if (!$old.ContainsKey($key)) { $lines.Add('ADDED   ' + $key) }
        elseif ($old[$key] -ne $new[$key]) { $lines.Add('CHANGED ' + $key) }
    }
    foreach ($key in @($old.Keys | Sort-Object)) {
        if (!$new.ContainsKey($key)) { $lines.Add('REMOVED ' + $key) }
    }
    if ($lines.Count -eq 0) { $lines.Add('(no changes in monitored areas)') }
    return $lines
}

Write-Host ''
Write-Host 'Caesium Portable - Read-only Trace Audit' -ForegroundColor Cyan
Write-Host 'This tool DOES NOT clean, delete, or edit host AppData or registry.'
Write-Host 'It does launch the existing Caesium Portable normally.'
Write-Host ''
Write-Host 'Taking baseline snapshot...'
$before = Take-Snapshot
Write-Host 'Launching CaesiumPortable.exe. Use it normally, then fully exit.' -ForegroundColor Yellow
$start = Get-Date
try {
    $child = Start-Process -FilePath $launcher -WorkingDirectory $root -PassThru -Wait
    $exitCode = $child.ExitCode
} catch {
    Write-Warning ('Launch failed: ' + $_.Exception.Message)
    $exitCode = 'failed-to-launch'
}
Write-Host 'Taking after-exit snapshot...'
$after = Take-Snapshot
$changes = @(List-Diff $before $after 'changes')
$allRemaining = @($after.Keys | Sort-Object)
$summary = @(
    'Caesium Portable read-only trace audit v1.1',
    ('Run time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
    ('Launched: CaesiumPortable.exe; exit code: ' + $exitCode),
    ('Elapsed seconds: ' + [math]::Round(((Get-Date) - $start).TotalSeconds, 1)),
    ('Before entries: ' + $before.Count + '; After entries: ' + $after.Count),
    '',
    'Changes after application exit (possible traces; attribution not automatically proven):',
    '--------------------------------------------------------------------------'
) + $changes + @(
    '', '',
    'Remaining monitored paths after exit (some may predate the test):',
    '--------------------------------------------------------------------------'
) + $allRemaining + @(
    '', '',
    'Interpretation:',
    '* ADDED = did not exist in monitored location before this run.',
    '* CHANGED = file size/time or registry value type/contents changed. Registry value CONTENT is compared only by a private, in-memory keyed fingerprint and is NOT included in this report.',
    '* REMOVED = no longer existed after this run.',
    '* Remaining entries can belong to an existing installation and may predate this test.',
    '* This is a targeted audit, not a complete trace of every operating-system write.',
    '* No file contents, raw registry value data, fingerprints, or private account credentials are exported in this report.',
    '* File and folder names may still reveal user information: review the report before sharing.',
    '* DO NOT delete shared SaeraSoft, QtProject, AppData, or registry parents.',
    '* If Data\\Recovery\\active.txt remains, retain it and contact us before further changes.'
)
[System.IO.File]::WriteAllLines($report, [string[]]$summary, (New-Object System.Text.UTF8Encoding($false)))
Compress-Archive -LiteralPath $report -DestinationPath $archive -Force
Write-Host ''
Write-Host ('Recorded change entries: ' + $(if($changes[0] -match '^\('){0}else{$changes.Count})) -ForegroundColor Green
Write-Host ('Report: ' + $report)
Write-Host ('ZIP to upload: ' + $archive) -ForegroundColor Green
Write-Host ''
Write-Host 'Review the report first; it contains path names but no file or registry contents.'

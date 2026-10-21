# OPTIONAL one-time cleanup for old Qt FileDialog preferences.
# Does not run automatically. Requires explicit typed confirmation and saves a .reg backup.
# Scope: ONLY HKCU\Software\QtProject\OrganizationDefaults\FileDialog;
# parents are removed ONLY if they become completely empty.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$active = Join-Path $root 'Data\Recovery\active.txt'
if (Test-Path -LiteralPath $active) { throw 'An interrupted portable session needs recovery. Open CaesiumPortable.exe first, then retry.' }
$targetTxt = Join-Path $root 'Other\Launcher\target.txt'
if (!(Test-Path -LiteralPath $targetTxt)) { throw 'Cannot locate the portable installation.' }
$processName = [IO.Path]::GetFileNameWithoutExtension((Get-Content -LiteralPath $targetTxt -Raw).Trim())
if (@(Get-Process -Name $processName -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Please exit Caesium completely first.' }
$leaf = 'Software\QtProject\OrganizationDefaults\FileDialog'
$regLeaf = 'Registry::HKEY_CURRENT_USER\' + $leaf
if (!(Test-Path -LiteralPath $regLeaf)) { Write-Host 'No legacy Qt FileDialog key exists. Nothing to clean.'; exit 0 }
$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($leaf)
try {
    if ($null -eq $k) { throw 'Registry entry was unavailable.' }
    $unexpected = @($k.GetValueNames() | Where-Object { $_ -notin @('history','lastVisited','qtVersion','viewMode') })
    $subkeys = @($k.GetSubKeyNames())
    if ($unexpected.Count -gt 0 -or $subkeys.Count -gt 0) {
        throw 'Unexpected values or subkeys detected. No deletion performed; use a more specific ownership audit.'
    }
} finally { if ($null -ne $k) {$k.Dispose()} }
Write-Host ''
Write-Host 'Legacy Qt FileDialog state was found.' -ForegroundColor Yellow
Write-Host 'IMPORTANT: This is SHARED Qt state. VLC, other Qt programs and Caesium can use it.'
Write-Host 'Only continue if you accept resetting this shared file-dialog history.'
Write-Host 'No changes will be made unless you type the exact confirmation below.'
$confirmation = Read-Host 'Type REMOVE SHARED QT HISTORY to back up and remove this one registry leaf'
if ($confirmation -cne 'REMOVE SHARED QT HISTORY') { Write-Host 'Cancelled; no changes.'; exit 0 }
$backupDir = Join-Path $root 'Data\LegacyHostBackups'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$backup = Join-Path $backupDir ('QtFileDialog-BeforeCleanup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.reg')
& reg.exe export ('HKCU\' + $leaf) $backup /y | Out-Null
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $backup)) { throw 'Backup failed; no settings were removed.' }
# Remove only the known leaf. Do not erase the QtProject tree.
[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($leaf, $false)
foreach ($parent in @('Software\QtProject\OrganizationDefaults','Software\QtProject')) {
    $parentKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($parent)
    if ($null -eq $parentKey) { continue }
    try { $isEmpty = ($parentKey.ValueCount -eq 0 -and $parentKey.SubKeyCount -eq 0) }
    finally { $parentKey.Dispose() }
    if ($isEmpty) {
        try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($parent, $false) }
        catch [System.IO.IOException] { Write-Warning ('Another application modified '+ $parent + '; preserved.') }
    }
}
Write-Host ('Saved backup: ' + $backup) -ForegroundColor Green
Write-Host 'Removed the selected legacy FileDialog key. Qt applications may recreate it later.'
Write-Host 'Do not delete the backup until you have verified your other Qt applications.'

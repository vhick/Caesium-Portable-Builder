param([string]$ReleaseTag='latest')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProgressPreference='SilentlyContinue'
$repoRoot=Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
if ($ReleaseTag -ne 'latest' -and $ReleaseTag -notmatch '^v?\d+\.\d+\.\d+$') {
  throw 'Use latest or an official stable tag such as v2.8.5.'
}
$headers=@{'Accept'='application/vnd.github+json';'User-Agent'='Caesium-Portable-Builder'}
if ($env:GH_TOKEN) { $headers.Authorization='Bearer '+$env:GH_TOKEN }
$base='https://api.github.com/repos/Lymphatus/caesium-image-compressor/releases'
$release=if($ReleaseTag -eq 'latest') { Invoke-RestMethod -Uri ($base+'/latest') -Headers $headers } else {
  $tag=if($ReleaseTag.StartsWith('v')){$ReleaseTag}else{'v'+$ReleaseTag}
  Invoke-RestMethod -Uri ($base+'/tags/'+$tag) -Headers $headers
}
if ($release.prerelease -or $release.draft) { throw 'A stable official release is required.' }
$version=([string]$release.tag_name).TrimStart('v')
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Unrecognized stable tag: '+$version }
$assetPattern='^caesium-image-compressor-'+[regex]::Escape($version)+'-win-portable\.zip$'
$assets=@($release.assets | Where-Object { [string]$_.name -match $assetPattern })
if ($assets.Count -ne 1) {
  $names=@($release.assets | ForEach-Object {[string]$_.name}) -join ', '
  throw "Expected one official Windows portable ZIP for $version; got $($assets.Count). Assets: $names"
}
$asset=$assets[0]
$work=Join-Path $repoRoot 'build-work'
$root=Join-Path $work 'CaesiumPortable'
$app=Join-Path $root 'App/Caesium'
$appinfo=Join-Path $root 'App/AppInfo'
$other=Join-Path $root 'Other'
$dist=Join-Path $repoRoot 'dist'
if(Test-Path $work){Remove-Item $work -Recurse -Force}
if(Test-Path $dist){Remove-Item $dist -Recurse -Force}
New-Item -ItemType Directory -Force -Path $work,$app,$appinfo,(Join-Path $other 'Launcher'),(Join-Path $other 'Source'),$dist | Out-Null
foreach($p in @('Data/Settings','Data/Roaming','Data/Local','Data/Temp','Data/Recovery')){
  New-Item -ItemType Directory -Force -Path (Join-Path $root $p) | Out-Null
}
$download=Join-Path $work ([string]$asset.name)
Write-Host "Downloading official Caesium $version portable archive: $($asset.name)"
Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $download
$checksum=(Get-FileHash $download -Algorithm SHA256).Hash
Write-Host "Downloaded SHA-256: $checksum"
# Check against the developer's hash if GitHub publishes one.
if ($asset.PSObject.Properties.Name -contains 'digest' -and [string]$asset.digest -match '^sha256:([a-fA-F0-9]{64})$') {
  if ($checksum -ine $Matches[1]) { throw 'Upstream SHA-256 digest mismatch.' }
  Write-Host 'PASS: upstream SHA-256 digest verified'
} else {
  Write-Warning 'No upstream digest is published. Downloaded from the official GitHub release over HTTPS; computed hash is NOT independent verification.'
}
$extract=Join-Path $work 'upstream'
Expand-Archive -LiteralPath $download -DestinationPath $extract -Force
# Inspect archive rather than guessing binary spelling or wrapper folder depth.
$allExecutables=@(Get-ChildItem -LiteralPath $extract -Recurse -File -Filter '*.exe')
$main=@($allExecutables | Where-Object { $_.BaseName -match '(?i)^caesium( image compressor|-image-compressor)?$' })
if($main.Count -ne 1){
  $listed=$allExecutables | ForEach-Object {$_.FullName.Substring($extract.Length+1)}
  throw ('Expected exactly one Caesium GUI exe. Found: '+($listed -join '; '))
}
$upstreamRoot=$main[0].Directory.FullName
Get-ChildItem -LiteralPath $upstreamRoot -Force | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $app -Recurse -Force
}
# Fail rather than packaging an empty or partial runtime.
if (@(Get-ChildItem -LiteralPath $app -Recurse -File -Filter '*.dll').Count -lt 2) {
  throw 'Portable archive seems incomplete: cannot find the bundled native libraries.'
}
$relative=$main[0].Name
Set-Content -LiteralPath (Join-Path $other 'Launcher/target.txt') -Value $relative -Encoding ascii
# Original upstream icon group, preserved in every supported resolution.
python -m pip install --disable-pip-version-check -q pefile Pillow
python (Join-Path $repoRoot 'scripts/extract_icon.py') (Join-Path $app $relative) (Join-Path $appinfo 'appicon.ico')
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the original multi-resolution icon.' }
$versionParts=$version.Split('.')
$ini=@"
[Format]
Type=PortableApps.comFormat
Version=3.5

[Details]
Name=Caesium Image Compressor Portable
AppID=CaesiumPortable
Publisher=SaeraSoft & Portable Community
Homepage=https://github.com/Lymphatus/caesium-image-compressor
Category=Graphics & Pictures
Description=Image compression with portable user settings
Language=Multilingual

[License]
Shareable=true
OpenSource=true
Freeware=true
CommercialUse=true

[Version]
PackageVersion=${version}.0
DisplayVersion=$version

[Control]
Start=CaesiumPortable.exe
"@
Set-Content -LiteralPath (Join-Path $appinfo 'appinfo.ini') -Value $ini -Encoding utf8
Copy-Item -LiteralPath (Join-Path $repoRoot 'launcher/CaesiumPortable.cs') -Destination (Join-Path $other 'Source/CaesiumPortable.cs')
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE-LAUNCHER.txt') -Destination (Join-Path $other 'Source/LICENSE-LAUNCHER.txt')
Copy-Item -LiteralPath (Join-Path $repoRoot 'docs/TESTING.md') -Destination (Join-Path $other 'TESTING.md')
# Read-only diagnostic, manually invoked when needed; never auto-runs.
$diagnostics=Join-Path $other 'Diagnostics'
New-Item -ItemType Directory -Force -Path $diagnostics | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repoRoot 'diagnostics') -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $diagnostics
}
$maintenance=Join-Path $other 'Maintenance'
New-Item -ItemType Directory -Force -Path $maintenance | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repoRoot 'maintenance') -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $maintenance
}
# Windows 10/11 includes .NET Framework 4.x runtime; compile a small launcher, NOT a setup installer.
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
if (!(Test-Path $csc)) { throw 'Windows .NET Framework C# compiler is unavailable on this runner.' }
$launchExe=Join-Path $root 'CaesiumPortable.exe'
& $csc /nologo /target:winexe /platform:anycpu /optimize+ /r:System.Windows.Forms.dll "/win32icon:$(Join-Path $appinfo 'appicon.ico')" "/out:$launchExe" (Join-Path $repoRoot 'launcher/CaesiumPortable.cs')
if($LASTEXITCODE -ne 0 -or !(Test-Path $launchExe)){throw 'Native Windows launcher compilation failed.'}
& $launchExe --self-test
if($LASTEXITCODE -ne 0){throw "Launcher self-test failed: $LASTEXITCODE"}
# Include exactly one top-level CaesiumPortable/ folder inside the downloadable ZIP.
$portableZip=Join-Path $dist "CaesiumPortable-$version-x64.zip"
Compress-Archive -LiteralPath $root -DestinationPath $portableZip -CompressionLevel Optimal
if(!(Test-Path $portableZip)) {throw 'No output portable ZIP was produced.'}
$zipItem=Get-Item -LiteralPath $portableZip
if($zipItem.Length -lt 2MB){throw 'Final package is unexpectedly small.'}
Write-Host "SUCCESS: $portableZip ($([math]::Round($zipItem.Length/1MB,1)) MB)"

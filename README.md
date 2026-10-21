# Caesium True Portable Builder v1.0

An unofficial, manual GitHub Actions builder for the official Caesium Image
Compressor Windows x64 portable release. **The builder ZIP contains scripts,
not the completed application.** A successful GitHub Actions run will produce
the complete `CaesiumPortable-[version]-x64.zip` application ZIP.

## Quick start

1. Create an empty GitHub repository `Caesium-Portable-Builder`.
2. Extract **this builder ZIP**. Upload every extracted file/folder to the repo,
   including the hidden `.github` directory. Commit and push.
3. Open the repository > Actions > **Build Caesium True Portable (Manual)**.
4. Click **Run workflow**, leave `release_tag` at `latest`, click the green Run.
5. After success, under Artifacts, download `CaesiumPortable-Windows-x64`.
6. Unzip the downloaded artifact. Inside it is `CaesiumPortable-2.8.5-x64.zip`
   (version changes as upstream releases change). Unzip **this inner ZIP** into
   the directory containing your PortableApps.com Menu installation.
7. Open the root `CaesiumPortable.exe` or refresh icons in PortableApps Menu.

## Upgrade without losing preferences

Fully exit Caesium. Extract a new application ZIP and **replace only**
`CaesiumPortable.exe`, `App/` and `Other/`. Preserve your existing `Data/`.

## What is special about Caesium portability?

Even the official portable ZIP writes to three reported external locations:

- `%APPDATA%\SaeraSoft\Caesium Image Compressor`
- `%LOCALAPPDATA%\SaeraSoft\Caesium Image Compressor`
- `HKCU\Software\SaeraSoft\Caesium Image Compressor`

Reference: https://github.com/Lymphatus/caesium-image-compressor/issues/317

The launcher handles those **specific Caesium** locations. It backs up any
pre-existing Caesium settings, places your portable state for the duration of
the process, waits for the process to close, saves it into `Data`, and restores
the original host state. A recovery journal is maintained for interrupted runs.
This deliberately does **not** globally change `APPDATA`, remove entire
SaeraSoft folders, delete other programs' registry keys, or erase Windows
activity traces.

If Caesium is already running, the launcher refuses to launch concurrently.
A portable app left running during power loss can leave `.CaesiumPortableHostBackup`
folders temporarily. **Do not delete those backups**; quit Caesium and start
this same portable launcher on the same PC/user to restore them. Never transfer
an active `Data/Recovery/active.txt` to another computer.

## Package layout

```
CaesiumPortable/
  CaesiumPortable.exe               (original upstream icon)
  App/
    AppInfo/
      appinfo.ini
      appicon.ico                   (multiresolution from upstream EXE)
      appicon_16.png / 32 / 75 / 128
    Caesium/                         (replaceable official application)
  Data/
    Settings/registry.reg            (saved personal preferences)
    Roaming/                         (portable roaming app files)
    Local/                           (portable local app files)
    Temp/                            (temporary files)
    Recovery/                        (crash recovery: never remove mid-session)
  Other/
    Launcher/target.txt
    Source/CaesiumPortable.cs
    TESTING.md
```

## Version selection and security

`latest` queries the **official** GitHub API's latest stable release. You can
specify an official `vX.Y.Z` tag. The builder matches the official
`caesium-image-compressor-X.Y.Z-win-portable.zip` asset, rejects drafts or
prereleases, and validates the original SHA-256 **when GitHub publishes one**.
If GitHub does not publish a digest, the script clearly warns; a hash computed
locally is not independent verification. No third-party binary mirrors are used.

The application is licensed by its upstream authors under its own GPL license.
The custom launcher is separately MIT licensed. Icons are extracted from the
same official version being packaged. This is an unofficial community builder.

## Limitations

The launcher uses journaled temporary movement of only Caesium-specific host
settings. The host settings must be restored after exit; an abrupt shutdown
requires automatic recovery on next launch with the same Windows account.
When moving between PCs, old absolute output directories from preferences
might no longer exist. Do not run multiple Caesium copies simultaneously.
This design cannot prevent Windows-managed traces or unanticipated writes from
upstream components. Test using `docs/TESTING.md` before claiming zero remnants.

Windows build and full GUI tests require your first GitHub Actions run.

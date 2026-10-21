# Caesium True Portable Builder v1.2

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

**v1.2 improvement: remaining empty parents and Qt file-dialog state.** After
restoring host settings, the launcher now removes EMPTY `SaeraSoft` parent
folders and registry keys even if older v1.0/v1.1 sessions left them behind.
Cleanup is nonrecursive, refuses symlinks, and never removes a parent containing
another file, subkey, or registry value.

Qt has another settings location, `HKCU\Software\QtProject\OrganizationDefaults\FileDialog`,
which is **shared by multiple Qt applications**. The launcher now temporarily
backs up only this `FileDialog` leaf, swaps in the portable copy saved in
`Data/Settings/qtfiledialog.reg`, then restores the original host leaf after
Caesium exits. Newly created empty Qt parents are pruned. Existing Qt
preferences are deliberately preserved, so concurrent Qt applications must
NOT be used while Caesium Portable is running. Crash recovery includes this
state, including upgrade recovery from v1.1 journals.

A previously existing `QtProject/FileDialog` key **will remain after v1.2**
if it belonged to the Windows account before launch. This is intentional to
avoid destroying other programs' preferences. A one-time optional cleanup tool
in `Other/Maintenance/Review-Old-QtFileDialog.cmd` can back up and remove
that specific old key with your typed approval. It refuses unexpected registry
entries and never removes the whole QtProject tree.

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
    Settings/qtfiledialog.reg        (portable Qt file-dialog state)
    Roaming/                         (portable roaming app files)
    Local/                           (portable local app files)
    Temp/                            (temporary files)
    Recovery/                        (crash recovery: never remove mid-session)
  Other/
    Launcher/target.txt
    Source/CaesiumPortable.cs
    Maintenance/                    (OPTIONAL old Qt key review & cleanup)
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

The launcher temporarily swaps Caesium's two AppData folders, the SaeraSoft
application registry key, and the Qt `FileDialog` registry leaf. It then saves
the portable settings and restores the previous host state. An interrupted
run uses the recovery journal; never delete an active journal or backup.
Do not run concurrent Qt applications while Caesium Portable is open; changes
from another Qt program to the shared file-dialog key could otherwise be lost.
The launcher cannot prevent Windows-managed traces or unknown upstream writes;
test on Windows before claiming complete isolation.

Windows build and full GUI tests require your first GitHub Actions run.

## Read-only verification (v1.2)

The portable ZIP includes `Other/Diagnostics/` with the optional v1.1 audit.
To use it, COPY `Audit-CaesiumPortable.ps1` and `Run-Caesium-Trace-Audit.cmd`
from that directory next to the root `CaesiumPortable.exe`, then run the CMD.
The report is created inside `Data/Diagnostics` and never cleans Windows.
It now compares **existing registry value contents** privately, using an
in-memory keyed fingerprint, without exporting their values or digests.

An unchanged baseline does not prove where an old trace came from.

## Removing OLD Qt traces from earlier Caesium builds (OPTIONAL)

You may see `HKCU\Software\QtProject\OrganizationDefaults\FileDialog`
remaining from BEFORE you install v1.2. The launcher cannot safely assume
ownership of that existing shared Qt data. To remove only that old leaf:

1. Fully exit Caesium and other Qt-based programs.
2. Run `Other/Maintenance/Review-Old-QtFileDialog.cmd` from the generated
   portable folder (this helper is NOT inside the downloaded builder alone).
3. Read the warning. Only type the exact confirmation if you accept resetting
   other Qt programs' file-picker history. A backup is saved in `Data/LegacyHostBackups`.
4. Rerun the included trace audit, import images and compress them.

Do NOT remove all of `QtProject`, and never delete nonempty `SaeraSoft` parents.

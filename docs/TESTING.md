# Windows portability test (Caesium v1.1 builder)

1. Extract the final inner ZIP directly into your `PortableApps` folder. It must
   create **one** `CaesiumPortable` directory containing `CaesiumPortable.exe`.
2. Open PortableApps Menu, then Apps > Refresh App Icons. Launch **Caesium Image
   Compressor Portable**. Do not directly open the EXE inside App/Caesium.
3. Test JPEG, PNG, WebP, and optionally TIFF using copies of pictures, never
   valuable originals. Verify compression results, not just successful launch.
4. Change a setting (e.g. UI theme), close Caesium fully, relaunch, check it
   persisted. Confirm `Data/Settings/registry.reg` exists when Caesium writes
   its Qt preferences.
5. Check new portable state inside `Data/Roaming` and `Data/Local` (these may
   remain empty if Caesium does not write there on your version).
6. Check under `%APPDATA%\SaeraSoft\Caesium Image Compressor` and
   `%LOCALAPPDATA%\SaeraSoft\Caesium Image Compressor`: the launcher-created
   folders should be gone after a clean exit. Existing folders should be
   returned to their pre-launch state.
7. Check `HKCU\Software\SaeraSoft\Caesium Image Compressor`: if no installed
   Caesium key existed before launch, it should not remain after clean exit;
   otherwise the original host key should be restored.
8. Use a new Windows user or spare PC to repeat steps 2–7. Move the portable
   folder to a different drive letter and verify settings persistence.
9. Test while an installed Caesium instance is already running: launcher must
   refuse rather than disturb that instance.
10. Test crash safety with a disposable test account: terminate the **launcher**
    while Caesium runs; close Caesium; re-run the launcher. It should recover
    host settings before starting. A sudden power loss can leave backup files
    until the same PC/account next runs the launcher.
11. Upgrade: exit Caesium, replace `CaesiumPortable.exe`, `App/`, `Other/` with
    the new build. **Keep `Data/` intact.**

Do not delete `Data/Recovery` while the launcher is running or an interrupted
session has not recovered. Do not delete other apps' SaeraSoft or registry data.

## What this does not guarantee

Windows system-managed traces (prefetch, recent files, Defender history) are
outside the application launcher. The custom launcher does not erase them.
Qt or codecs might use other paths in future upstream releases; use ProcMon
as a secondary verification step and report any remaining application-owned
paths. This builder has not been run by the author on Windows.

## v1.1 specific check - newly created parent containers

1. On a Windows test account **without** any `SaeraSoft` paths, take a
   before snapshot of `%APPDATA%\SaeraSoft`, `%LOCALAPPDATA%\SaeraSoft`,
   and `HKCU\Software\SaeraSoft`. Do not delete existing paths to create
   an artificial clean account.
2. Launch the v1.1 root launcher, compress a test image, exit normally.
3. Check the three parent containers. They should be absent if they were
   absent before the run and remained empty after settings restoration.
4. If any parent existed before launch, it must be preserved, even if empty.
5. Check an installed Caesium copy or unrelated SaeraSoft application, if
   present, still has its original settings.
6. Do not delete `HKCU\Software\QtProject`; this is shared Qt storage.

The previously provided trace audit found 10 entries before and after the
run. It does not prove no existing registry **value data** was modified.

### v1.2 shared Qt state verification

1. Note whether `HKCU\Software\QtProject\OrganizationDefaults\FileDialog`
   existed BEFORE launch. (If yes it should still exist with exactly its original values.)
2. Launch CaesiumPortable and open an image using the file picker.
3. Exit fully. The host Qt FileDialog leaf should be back to its original state;
   portable state should be under `Data/Settings/qtfiledialog.reg`.
4. On a clean Windows account where the key was absent, verify that the Qt leaf
   and empty parent keys are absent AFTER exit.
5. Re-run the read-only diagnostic. Any new or changed entries require investigation.
6. If old empty `SaeraSoft` parents remained from v1.1, they should now be gone.

Do not use a second Qt program concurrently during this test. The optional
Qt legacy-cleaning helper requires explicit consent and keeps a registry backup.

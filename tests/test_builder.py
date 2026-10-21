import pathlib,re,unittest,zipfile,struct,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]

class CheckBuilder(unittest.TestCase):
    def test_workflow_manual_only(self):
        s=(ROOT/'.github/workflows/build-caesium-portable.yml').read_text(encoding='utf8')
        self.assertIn('workflow_dispatch:',s)
        self.assertIn('actions/upload-artifact@v4',s)
        self.assertIn('retention-days: 1',s)
        self.assertNotIn('schedule:',s)
    def test_official_origin(self):
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf8')
        self.assertIn('api.github.com/repos/Lymphatus/caesium-image-compressor/releases',s)
        self.assertIn('win-portable',s)
        self.assertIn('checksum -ine $Matches[1]',s)
        self.assertIn('Compress-Archive -LiteralPath $root',s)
    def test_settings_scoped(self):
        s=(ROOT/'launcher/CaesiumPortable.cs').read_text(encoding='utf8')
        self.assertIn('Software\\SaeraSoft\\Caesium Image Compressor',s)
        self.assertIn('SaeraSoft\\Caesium Image Compressor',s)
        self.assertNotIn('SetEnvironmentVariable("APPDATA"',s)
    def test_restore_guard(self):
        s=(ROOT/'launcher/CaesiumPortable.cs').read_text(encoding='utf8')
        for x in ('HadRoaming','HadLocal','HadRegistry','WriteJournal','LoadJournal','RestoreAndCapture','MachineIdentity'):
            self.assertIn(x,s)
    def test_process_wait_and_exclusivity(self):
        s=(ROOT/'launcher/CaesiumPortable.cs').read_text(encoding='utf8')
        self.assertIn('Mutex',s)
        self.assertIn('child.WaitForExit()',s)
        self.assertIn('Process.GetProcessesByName',s)
    def test_original_icon_processing(self):
        s=(ROOT/'scripts/extract_icon.py').read_text(encoding='utf8')
        self.assertIn('IMAGE_DIRECTORY_ENTRY_RESOURCE',s)
        self.assertIn("'appicon_'",s)
        self.assertIn("struct.pack('<HHH'",s)
    def test_appinfo_and_single_folder(self):
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf8')
        self.assertIn('App/AppInfo',s)
        self.assertIn('Start=CaesiumPortable.exe',s)
        self.assertIn('Category=Graphics & Pictures',s)
        self.assertIn("'build-work'",s)
    def test_keep_data_documented(self):
        s=(ROOT/'README.md').read_text(encoding='utf8')
        self.assertIn('Preserve your existing `Data/`',s)
        self.assertIn('Do not delete those backups',s)
    def test_new_empty_parent_cleanup_only(self):
        s=(ROOT/'launcher/CaesiumPortable.cs').read_text(encoding='utf8')
        for part in ('HadRoamingParent','HadLocalParent','HadRegistryParent',
                     'RemoveNewEmptyFolderParent','RemoveNewEmptyRegistryParent',
                     'Directory.GetFileSystemEntries(parent).Length == 0',
                     'info.Attributes & FileAttributes.ReparsePoint',
                     'k.SubKeyCount != 0 || k.ValueCount != 0',
                     'DeleteSubKey(RegParent, false)'):
            self.assertIn(part,s)
        self.assertNotIn('DeleteSubKeyTree(RegParent',s)
        self.assertNotIn('DeleteSubKeyTree(@"Software\\QtProject',s)
    def test_preexisting_parents_never_removed(self):
        s=(ROOT/'launcher/CaesiumPortable.cs').read_text(encoding='utf8')
        for part in ('if (!HadRoamingParent) RemoveNewEmptyFolderParent',
                     'if (!HadLocalParent) RemoveNewEmptyFolderParent',
                     'if (!HadRegistryParent) RemoveNewEmptyRegistryParent'):
            self.assertIn(part,s)
    def test_v10_journal_compatibility(self):
        s=(ROOT/'launcher/CaesiumPortable.cs').read_text(encoding='utf8')
        self.assertIn('HadRoamingParent = true;',s)
        self.assertIn('HadLocalParent = true;',s)
        self.assertIn('HadRegistryParent = true;',s)
        self.assertIn('"HadRoamingParent=" + HadRoamingParent',s)
    def test_readonly_audit_compares_value_contents_without_reporting_hashes(self):
        a=(ROOT/'diagnostics/Audit-CaesiumPortable.ps1').read_text(encoding='utf8')
        self.assertIn('Get-RegistryValueFingerprint',a)
        self.assertIn('DoNotExpandEnvironmentNames',a)
        self.assertIn('privateDigestKey',a)
        self.assertIn('Get-RegistryValueFingerprint $reg $valueName',a)
        self.assertIn('Compress-Archive -LiteralPath $report',a)
        self.assertNotIn('Remove-Item ',a)
        s=(ROOT/'scripts/build.ps1').read_text(encoding='utf8')
        self.assertIn("Join-Path $repoRoot 'diagnostics'",s)
    def test_no_upstream_binaries_in_builder(self):
        self.assertFalse(list(ROOT.rglob('*.exe')))
        self.assertFalse(list(ROOT.rglob('*.dll')))

if __name__=='__main__':unittest.main()

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
    def test_no_upstream_binaries_in_builder(self):
        self.assertFalse(list(ROOT.rglob('*.exe')))
        self.assertFalse(list(ROOT.rglob('*.dll')))

if __name__=='__main__':unittest.main()

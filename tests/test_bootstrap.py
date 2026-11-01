import pathlib, subprocess, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class BootstrapTests(unittest.TestCase):
    def test_configuration_can_be_loaded_without_disks(self):
        p=subprocess.run(['bash','-c','source scripts/00-config.sh; printf "%s/%s" "$UBUNTU_RELEASE" "$DATA_MAPPER"'],cwd=ROOT,text=True,capture_output=True)
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(p.stdout,'resolute/cryptdata')
    def test_installer_refuses_missing_live_opt_in(self):
        p=subprocess.run(['bash','scripts/01-partition-and-encrypt.sh'],cwd=ROOT,text=True,capture_output=True)
        self.assertNotEqual(p.returncode,0)
        self.assertIn('FRESH_INSTALL',p.stdout+p.stderr)
    def test_archive_check_rejects_secondary_key(self):
        command = 'source scripts/00-config.sh; lsinitramfs() { printf "%s\\n" cryptroot/crypttab etc/luks-data-keyfile; }; verify_initramfs fake'
        p=subprocess.run(['bash','-c',command],cwd=ROOT,text=True,capture_output=True)
        self.assertNotEqual(p.returncode,0)
        self.assertIn('Secondary key found',p.stderr)
    def test_archive_check_accepts_root_only(self):
        command = 'source scripts/00-config.sh; lsinitramfs() { printf "%s\\n" cryptroot/crypttab usr/sbin/cryptsetup; }; verify_initramfs fake'
        p=subprocess.run(['bash','-c',command],cwd=ROOT,text=True,capture_output=True)
        self.assertEqual(p.returncode,0,p.stderr)
    def test_no_incus_in_active_installation_scripts(self):
        for p in (ROOT/'scripts').glob('*.sh'):
            self.assertNotIn('INCUS_',p.read_text(),p.name)
    def test_key_never_embedded_by_system_configuration(self):
        s=(ROOT/'scripts/03-configure-system.sh').read_text()
        self.assertNotIn('${DESTDIR}/etc/luks-',s)
        self.assertIn('verify_initramfs',s)
if __name__=='__main__': unittest.main()

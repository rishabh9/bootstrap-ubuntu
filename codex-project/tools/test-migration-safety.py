"""Non-destructive CLI tests. Never invoke an apply mode on real hardware."""
import pathlib
import subprocess
import unittest

SCRIPT = pathlib.Path(__file__).with_name('migrate-workstation.sh')

class SafetyTests(unittest.TestCase):
    def call(self, *args):
        return subprocess.run(['bash', str(SCRIPT), *args], capture_output=True, text=True)

    def test_default_only_describes_plan(self):
        result = self.call()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('No changes made', result.stdout)
        self.assertIn('boot-cleanup', result.stdout)

    def test_unknown_mode_refused(self):
        result = self.call('erase-everything')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unknown mode', result.stderr)

    def test_extra_arguments_refused(self):
        result = self.call('boot-cleanup', '--yes')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('one mode', result.stderr)

    def test_apply_requires_interactive_terminal(self):
        for mode in ('boot-cleanup', 'data-migration'):
            with self.subTest(mode=mode):
                result = self.call(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('interactive terminal', result.stderr)

if __name__ == '__main__':
    unittest.main()

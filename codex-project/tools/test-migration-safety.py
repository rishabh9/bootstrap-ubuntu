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

    def test_cross_project_inventory_keeps_local_socket_without_project_flag(self):
        lines = SCRIPT.read_text().splitlines()
        setup = [line for line in lines if line.startswith(('incus_local=(', 'incus_all_projects=('))]
        command = next(line.split(' | ', 1)[0] for line in lines
                       if 'list --all-projects --format json' in line)
        # Execute only the real inventory invocation, with a shell fake instead
        # of the Incus daemon. No apply path or disk operation is evaluated.
        fake = """incus() {
            local arg project=0 all=0
            for arg in "$@"; do
                [[ $arg == --project ]] && project=1
                [[ $arg == --all-projects ]] && all=1
            done
            if (( project && all )); then
                echo "Can't specify --project with --all-projects" >&2
                return 1
            fi
            printf '%s\\n' "$@"
        }
"""
        result = subprocess.run(['bash', '-c', fake + '\n'.join(setup) + '\n' + command],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = result.stdout.splitlines()
        self.assertIn('--force-local', args)
        self.assertIn('--all-projects', args)
        self.assertNotIn('--project', args)

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

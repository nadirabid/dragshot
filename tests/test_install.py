import datetime
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('check_install', ROOT / 'scripts/check-install.py')
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

class ReadinessTests(unittest.TestCase):
    def good(self):
        return {'bundle': 'local.lookit', 'app': '/Applications/Lookit.app', 'pid': '123',
                'updated': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'screen recording': 'true', 'accessibility': 'true', 'input monitoring': 'false',
                'event tap': 'true', 'multitouch': 'true', 'three-finger drag': 'enabled'}

    def test_current_running_app_with_event_control_is_ready(self):
        self.assertEqual(check.core_issues(self.good(), Path('/Applications/Lookit.app'), alive=lambda p: None), [])

    def test_stale_wrong_copy_missing_permission_and_dead_process_are_not_ready(self):
        data = self.good()
        data.update({'updated': '2000-01-01T00:00:00Z', 'app': '/tmp/build/Lookit.app', 'screen recording': 'false'})
        def dead(pid): raise ProcessLookupError()
        issues = check.core_issues(data, Path('/Applications/Lookit.app'), alive=dead)
        self.assertEqual(len(issues), 4)

    def test_bridge_requires_live_handshake_version_and_ui(self):
        with tempfile.TemporaryDirectory(prefix='lookit-check-', dir='/tmp') as d:
            support = Path(d)
            self.assertTrue(check.bridge_issues(support, True))
            for version, ui, ready in [('0.3.0', True, False), ('0.4.0', False, False), ('0.4.0', True, True)]:
                path = str(support / 's')
                with socket.socket(socket.AF_UNIX) as server:
                    server.bind(path); server.listen()
                    (support/'dsh-bridge.json').write_text(json.dumps({'socket': path}))
                    def respond():
                        conn, _ = server.accept()
                        with conn:
                            conn.recv(4096)
                            conn.sendall((json.dumps({'id': 'install-check', 'ok': True, 'result': {
                                'plugin': 'dsh-lookit', 'protocol': 1, 'version': version, 'navigationReady': ui}})+'\n').encode())
                    thread = threading.Thread(target=respond); thread.start()
                    self.assertEqual(not check.bridge_issues(support, True), ready)
                    thread.join()
                Path(path).unlink()

@unittest.skipUnless(shutil.which('codesign'), 'macOS codesign required')
class AppInstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lookit-app-install-')
        self.root = Path(self.tmp.name)
        self.repo = self.root/'repo'; self.repo.mkdir()
        shutil.copy(ROOT/'install.sh', self.repo/'install.sh')
        self.app = self.repo/'build/Lookit.app'
        (self.app/'Contents/MacOS').mkdir(parents=True)
        (self.app/'Contents/MacOS/Lookit').write_text('#!/bin/sh\nexit 0\n')
        (self.app/'Contents/MacOS/Lookit').chmod(0o755)
        with (self.app/'Contents/Info.plist').open('wb') as f:
            plistlib.dump({'CFBundleIdentifier':'local.lookit', 'CFBundleExecutable':'Lookit', 'CFBundlePackageType':'APPL'}, f)
        shutil.copytree(ROOT/'dsh-lookit', self.app/'Contents/Resources/DSHBridge', ignore=shutil.ignore_patterns('node_modules', 'test'))
        self.sign()
        self.bin = self.root/'bin'; self.bin.mkdir()
        for name, body in {'defaults': 'printf "%s\\n" "$*" >> "$TEST_DEFAULTS_LOG"', 'pgrep': 'exit 1', 'lsregister': 'exit 0'}.items():
            p=self.bin/name; p.write_text('#!/bin/bash\n'+body+'\n'); p.chmod(0o755)
        self.dest = self.root/'Applications'; self.dest.mkdir()
        self.env = dict(os.environ, HOME=str(self.root/'home'), DSH_HOME=str(self.root/'dsh'),
                        LOOKIT_SUPPORT_DIR=str(self.root/'support'), LOOKIT_INSTALL_DIR=str(self.dest),
                        LOOKIT_LSREGISTER=str(self.bin/'lsregister'), TEST_DEFAULTS_LOG=str(self.root/'defaults.log'),
                        PATH=str(self.bin)+os.pathsep+os.environ['PATH'])

    def tearDown(self): self.tmp.cleanup()
    def sign(self):
        subprocess.run(['codesign','--force','--sign','-','--identifier','local.lookit',str(self.app)], check=True, capture_output=True)
    def run_install(self, *args):
        return subprocess.run(['bash',str(self.repo/'install.sh'),'--no-open',*args], env=self.env, text=True, capture_output=True)
    def installed_bytes(self): return (self.dest/'Lookit.app/Contents/MacOS/Lookit').read_bytes()

    def test_clean_repeat_install_and_no_destination_resets(self):
        for _ in range(2):
            result=self.run_install(); self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.installed_bytes(), b'#!/bin/sh\nexit 0\n')
        changes=(self.root/'defaults.log').read_text().splitlines()
        self.assertEqual(len(changes), 2)
        self.assertTrue(all(line.startswith('write local.lookit installedAppPath ') for line in changes))
        self.assertIn('Readiness not checked', result.stdout)

    def test_invalid_build_preserves_existing_app(self):
        self.assertEqual(self.run_install().returncode,0)
        before=self.installed_bytes()
        (self.app/'Contents/MacOS/Lookit').write_text('broken signature')
        self.assertNotEqual(self.run_install().returncode,0)
        self.assertEqual(self.installed_bytes(),before)

    def test_changed_signing_requirement_is_not_silently_installed(self):
        self.assertEqual(self.run_install().returncode,0)
        before=self.installed_bytes()
        (self.app/'Contents/MacOS/Lookit').write_text('#!/bin/sh\nexit 1\n'); self.sign()
        result=self.run_install()
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Signing identity changed',result.stderr)
        self.assertEqual(self.installed_bytes(),before)
        self.assertEqual(self.run_install('--allow-signing-change').returncode,0)

    def test_first_install_registers_bridge_when_profile_exists(self):
        profile=self.root/'dsh/profiles/desktop'; profile.mkdir(parents=True)
        result=self.run_install(); self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue((self.root/'support/Integrations/dsh-lookit/lib/client.js').is_file())
        self.assertIn('id: lookit-bridge',(profile/'cordis.patch.yml').read_text())
        shutil.rmtree(self.repo)
        self.assertTrue((self.root/'dsh/profiles/node_modules/dsh-lookit/lib/index.js').is_file())

if __name__ == '__main__': unittest.main()

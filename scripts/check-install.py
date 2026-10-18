#!/usr/bin/env python3
"""Read-only checks. Exit 0 means ready; 2 means installed but needs attention."""
import argparse
import datetime
import json
import os
from pathlib import Path
import socket
import time


def read_diagnostics(path):
    return dict(line.split(': ', 1) for line in path.read_text().splitlines() if ': ' in line)


def core_issues(data, app, now=None, alive=None):
    now = time.time() if now is None else now
    alive = alive or (lambda pid: os.kill(pid, 0))
    issues = []
    if data.get('bundle') != 'local.lookit' or data.get('app') != str(app):
        issues.append('Diagnostics belong to another app copy. Open the installed Lookit.')
    try:
        updated = datetime.datetime.fromisoformat(data['updated'].replace('Z', '+00:00')).timestamp()
        if not 0 <= now - updated < 15:
            issues.append('Diagnostics are stale. Open the installed Lookit.')
        alive(int(data['pid']))
    except (ValueError, KeyError, OSError):
        issues.append('The app process or diagnostics are unavailable.')
    for key, label in [('screen recording', 'Screen Recording'), ('accessibility', 'Device Control / Accessibility'),
                       ('event tap', 'gesture listener'), ('multitouch', 'trackpad reader')]:
        if data.get(key) != 'true':
            issues.append(f'{label} needs attention in Lookit Settings → Permissions.')
    if data.get('input monitoring') != 'true' and data.get('event tap') != 'true':
        issues.append('Input Monitoring needs attention in Lookit Settings → Permissions.')
    if data.get('three-finger drag') != 'enabled':
        issues.append('Enable three-finger drag in macOS Pointer Control → Trackpad Options.')
    return issues


def bridge_issues(support, needs_navigation):
    try:
        discovery = json.loads((support / 'dsh-bridge.json').read_text())
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(2)
            client.connect(discovery['socket'])
            client.sendall(b'{"id":"install-check","method":"hello","params":{}}\n')
            response = b''
            while b'\n' not in response and len(response) < 65536:
                chunk = client.recv(4096)
                if not chunk:
                    break
                response += chunk
        reply = json.loads(response.split(b'\n')[0])
        result = reply.get('result', {})
        if reply.get('id') != 'install-check' or reply.get('ok') is not True or result.get('plugin') != 'dsh-lookit' or result.get('protocol') != 1:
            return ['DSH bridge handshake failed. Restart DSH after installing the bridge.']
        if result.get('version') != '0.4.0':
            return ['DSH is running an older bridge. Restart DSH to load the installed version.']
        if needs_navigation and result.get('navigationReady') is not True:
            return ['DSH host is connected, but its chat navigation companion is not ready. Open or restart DSH.']
        return []
    except (OSError, ValueError, KeyError, TypeError):
        return ['DSH bridge is not connected. Open DSH; if already open, restart it after current work finishes.']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True)
    parser.add_argument('--wait', type=float, default=0)
    args = parser.parse_args()
    app = Path(args.app).resolve()
    support = Path(os.environ.get('LOOKIT_SUPPORT_DIR', str(Path.home() / 'Library/Application Support/Lookit')))
    deadline = time.monotonic() + args.wait
    while True:
        data = {}
        try:
            data = read_diagnostics(support / 'diagnostics.txt')
            issues = core_issues(data, app)
        except (OSError, ValueError):
            issues = ['No current diagnostics from Lookit. Open the installed app.']
        if data.get('harness') == 'deepseek':
            issues += bridge_issues(support, data.get('open after sending') == 'true')
        if not issues or time.monotonic() >= deadline:
            break
        time.sleep(.5)
    print(f'Installed: {app}')
    if issues:
        print('Needs attention:')
        for issue in dict.fromkeys(issues):
            print(f'  • {issue}')
        return 2
    print('Ready: current app, permissions, gesture listener and selected harness checks passed.')
    print('A physical three-finger capture is the final hardware check; it is not simulated by installation.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Check staged/tracked source without printing private file contents."""
from pathlib import Path
import re
import subprocess

root = Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip())
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
blocked_parts = {'.verification', 'BuildLogs', 'DerivedData', '.build', 'xcuserdata', '__pycache__'}
blocked_names = {'Local.xcconfig', 'Refresh My Devices.command', 'phone-v1.json', 'watch-v1.json'}
blocked_suffixes = {'.p12', '.p8', '.pem', '.key', '.mobileprovision', '.provisionprofile', '.ipa', '.xcarchive', '.xcresult'}
patterns = [rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', rb'gh[pousr]_[A-Za-z0-9]{30,}', rb'github_pat_[A-Za-z0-9_]{40,}', rb'sk-(?:proj-)?[A-Za-z0-9_-]{32,}']
failures = []
for name in filter(None, paths):
    path = Path(name)
    if set(path.parts) & blocked_parts or path.name in blocked_names or path.suffix in blocked_suffixes or path.name.startswith('.env'):
        failures.append((name, 'private/generated path')); continue
    data = subprocess.check_output(['git', 'show', ':' + name], cwd=root)
    if any(re.search(pattern, data) for pattern in patterns):
        failures.append((name, 'credential pattern'))
    if data.startswith(b'bplist') or len(data) > 10_000_000:
        failures.append((name, 'unexpected binary or oversized file'))
for name, reason in failures:
    print(f'BLOCKED: {name}: {reason}')
if failures:
    raise SystemExit(1)
print(f'Repository boundary check passed for {len(list(filter(None, paths)))} staged/tracked files. Review the staged diff as well.')

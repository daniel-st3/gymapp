#!/usr/bin/env python3
"""Build, install and launch both apps on one EXISTING paired simulator set.

Does not erase simulators, change signing, uninstall apps, or create new pairs.
"""
from dataclasses import dataclass
from pathlib import Path
import json
import os
import platform
import plistlib
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class SimulatorPair:
    phone_id: str
    phone_name: str
    watch_id: str
    watch_name: str


def choose_pair(pair_list, device_list):
    devices = {}
    for runtime, entries in device_list.get('devices', {}).items():
        for device in entries:
            if device.get('isAvailable', True):
                devices[device['udid']] = (runtime, device)
    choices = []
    for pair in pair_list.get('pairs', {}).values():
        phone_id = pair.get('phone', {}).get('udid')
        watch_id = pair.get('watch', {}).get('udid')
        if phone_id not in devices or watch_id not in devices:
            continue
        phone_runtime, phone = devices[phone_id]
        watch_runtime, watch = devices[watch_id]
        if 'ios' not in phone_runtime.lower() or 'watchos' not in watch_runtime.lower():
            continue
        score = (20 if watch.get('state') == 'Booted' else 0)
        score += 10 if phone.get('state') == 'Booted' else 0
        score += 2 if 'Pro Max' in phone['name'] else 0
        score += 1 if '46mm' in watch['name'] else 0
        choices.append((score, phone_id, watch_id, SimulatorPair(phone_id, phone['name'], watch_id, watch['name'])))
    if not choices:
        raise RuntimeError('No available paired iPhone and Apple Watch simulators were found. Open the simulator pair you were using, then run this launcher again.')
    # Select a PAIR, not independent devices that happen to have attractive names.
    return max(choices, key=lambda item: item[:3])[3]


def run(args, *, log=None, capture=False, optional=False):
    if log:
        with log.open('w') as output:
            result = subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            tail = '\n'.join(log.read_text(errors='replace').splitlines()[-55:])
            raise RuntimeError(f'Build failed. Last messages:\n{tail}\n\nFull log: {log}')
        return ''
    result = subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode and not optional:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f'Command failed: {args[0]}')
    return result.stdout if capture else ''


def identities(phone_app, watch_app):
    with (phone_app / 'Info.plist').open('rb') as source:
        phone = plistlib.load(source)
    with (watch_app / 'Info.plist').open('rb') as source:
        watch = plistlib.load(source)
    phone_id = phone['CFBundleIdentifier']
    watch_id = watch['CFBundleIdentifier']
    if watch.get('WKCompanionAppBundleIdentifier') != phone_id or not watch_id.startswith(phone_id + '.'):
        raise RuntimeError('The phone and watch bundle identifiers do not match. Check Config/Project.xcconfig and any Local.xcconfig override.')
    return phone_id, watch_id


def verify_plan_delivery(pair, phone_bundle, watch_bundle, *, issued_after, runner=run, attempts=40, pause=time.sleep):
    """Read only this app's persisted state; never print personal workout content.

    A successful launch is not a delivery receipt. Wait for the watch to SAVE
    the current phone plan before reporting that simulator sync worked.
    """
    containers = []
    for device, bundle in ((pair.phone_id, phone_bundle), (pair.watch_id, watch_bundle)):
        folder = runner(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], capture=True).strip()
        if not folder:
            raise RuntimeError('Simulator did not return the installed app data container.')
        containers.append(Path(folder) / 'Library/Application Support/LittleLift')
    phone_file, watch_file = containers[0] / 'phone-v1.json', containers[1] / 'watch-v1.json'
    for attempt in range(attempts):
        try:
            phone = json.loads(phone_file.read_text())
            watch = json.loads(watch_file.read_text())
        except (OSError, ValueError):
            pass  # First launch may not have created either state file yet.
        else:
            phone_plan, watch_plan = phone.get('plan') or {}, watch.get('plan') or {}
            received_at = watch.get('lastSnapshotDate', 0)
            fresh = isinstance(received_at, (int, float)) and received_at / 1000 >= issued_after
            if phone_plan.get('id') and phone_plan == watch_plan and fresh:
                return
        if attempt + 1 < attempts:
            pause(0.5)
    raise RuntimeError('Both apps opened, but delivery was NOT confirmed. Your workouts were left in place. Keep both apps open and check the connection status in Little Lift. The launcher will not report success until the watch has saved the phone plan.')


def build_and_launch(pair, root=ROOT, runner=run, verifier=verify_plan_delivery):
    derived = root / '.simulator-build'
    logs = root / 'BuildLogs'
    logs.mkdir(exist_ok=True)
    print('Little Lift · local workout logger', flush=True)
    print(f'Using {pair.phone_name} + {pair.watch_name}', flush=True)
    print('1/5 Preparing the paired simulators…', flush=True)
    available = json.loads(runner(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], capture=True))
    states = {device['udid']: device['state'] for entries in available['devices'].values() for device in entries}
    for device_id in (pair.phone_id, pair.watch_id):
        if states.get(device_id) != 'Booted':
            runner(['xcrun', 'simctl', 'boot', device_id])
        runner(['xcrun', 'simctl', 'bootstatus', device_id, '-b'])
    print('2/5 Building the iPhone app…', flush=True)
    runner(['xcodebuild', '-project', str(root / 'LittleLift.xcodeproj'), '-scheme', 'LittleLift',
            '-configuration', 'Debug', '-sdk', 'iphonesimulator',
            '-destination', f'platform=iOS Simulator,id={pair.phone_id}',
            '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO', 'build'], log=logs / 'iphone-build.log')
    print('3/5 Building the watch app…', flush=True)
    runner(['xcodebuild', '-project', str(root / 'LittleLift.xcodeproj'), '-scheme', 'LittleLiftWatch',
            '-configuration', 'Debug', '-sdk', 'watchsimulator',
            '-destination', f'platform=watchOS Simulator,id={pair.watch_id}',
            '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO', 'build'], log=logs / 'watch-build.log')
    phone_app = derived / 'Build/Products/Debug-iphonesimulator/LittleLift.app'
    watch_app = derived / 'Build/Products/Debug-watchsimulator/LittleLiftWatch.app'
    phone_bundle, watch_bundle = identities(phone_app, watch_app)
    print('4/5 Installing and opening both apps…', flush=True)
    # Stop only these two app processes. Reinstallation retains their data containers.
    for device, bundle in ((pair.phone_id, phone_bundle), (pair.watch_id, watch_bundle)):
        runner(['xcrun', 'simctl', 'terminate', device, bundle], optional=True)
    runner(['xcrun', 'simctl', 'install', pair.phone_id, str(phone_app)])
    runner(['xcrun', 'simctl', 'install', pair.watch_id, str(watch_app)])
    # Xcode 27 can display simulators inside Xcode/DeviceHub without a
    # standalone Simulator.app. The simctl launches must still run there.
    runner(['open', '-a', 'Simulator'], optional=True)
    launched_at = time.time()
    runner(['xcrun', 'simctl', 'launch', pair.phone_id, phone_bundle, '--littlelift-demo'])
    runner(['xcrun', 'simctl', 'launch', pair.watch_id, watch_bundle])
    print('5/5 Checking that the watch saved the phone workout…', flush=True)
    verifier(pair, phone_bundle, watch_bundle, issued_after=launched_at, runner=runner)
    print('\nConfirmed: the phone workout is saved on the paired watch.', flush=True)
    print('A generic example workout is loaded only if the phone has no saved plan.', flush=True)
    print(f'Build logs: {logs}', flush=True)


def main():
    if platform.system() != 'Darwin':
        raise RuntimeError('Run this launcher on your Mac with Xcode installed.')
    # Scope full-Xcode selection to this launcher, without changing system settings.
    installed_xcode = Path('/Applications/Xcode.app/Contents/Developer')
    if not os.environ.get('DEVELOPER_DIR') and installed_xcode.is_dir():
        os.environ['DEVELOPER_DIR'] = str(installed_xcode)
    run(['xcrun', '--find', 'simctl'])
    run(['xcodebuild', '-version'])
    pairs = json.loads(run(['xcrun', 'simctl', 'list', 'pairs', '--json'], capture=True))
    devices = json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], capture=True))
    build_and_launch(choose_pair(pairs, devices))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(f'\nLittle Lift could not finish setup:\n{error}', file=sys.stderr)
        sys.exit(1)

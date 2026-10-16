import contextlib
import io
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

from run_simulators import SimulatorPair, build_and_launch, choose_pair, identities, verify_plan_delivery


def fixture():
    return ({'pairs': {'pair-1': {'phone': {'udid': 'paired-phone'}, 'watch': {'udid': 'watch'}}}}, {
        'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [
                {'udid': 'wrong-phone', 'name': 'iPhone 18 Pro', 'state': 'Booted', 'isAvailable': True},
                {'udid': 'paired-phone', 'name': 'iPhone 18 Pro Max', 'state': 'Shutdown', 'isAvailable': True}],
            'com.apple.CoreSimulator.SimRuntime.watchOS-27-0': [
                {'udid': 'watch', 'name': 'Apple Watch Series 12 (46mm)', 'state': 'Booted', 'isAvailable': True}]}})


class LauncherTests(unittest.TestCase):
    def test_selects_the_paired_phone_even_when_the_wrong_phone_is_booted(self):
        pairs, devices = fixture()
        selected = choose_pair(pairs, devices)
        self.assertEqual(selected.phone_id, 'paired-phone')
        self.assertEqual(selected.watch_id, 'watch')

    def test_unavailable_watch_cannot_be_selected(self):
        pairs, devices = fixture()
        next(entries for runtime, entries in devices['devices'].items() if 'watchOS' in runtime)[0]['isAvailable'] = False
        with self.assertRaises(RuntimeError):
            choose_pair(pairs, devices)

    def test_no_pair_fails_instead_of_pairing_independent_devices(self):
        _, devices = fixture()
        with self.assertRaises(RuntimeError):
            choose_pair({'pairs': {}}, devices)

    def test_prefers_an_existing_booted_pair(self):
        pairs, devices = fixture()
        pairs['pairs']['pair-2'] = {'phone': {'udid': 'another-phone'}, 'watch': {'udid': 'another-watch'}}
        for runtime, entries in devices['devices'].items():
            if 'watchOS' in runtime:
                entries.append({'udid': 'another-watch', 'name': 'Apple Watch', 'state': 'Shutdown'})
            else:
                entries.append({'udid': 'another-phone', 'name': 'iPhone', 'state': 'Shutdown'})
        self.assertEqual(choose_pair(pairs, devices).watch_id, 'watch')

    def test_mismatched_companion_identifiers_stop_installation(self):
        with tempfile.TemporaryDirectory() as temp:
            phone, watch = Path(temp) / 'Phone.app', Path(temp) / 'Watch.app'
            phone.mkdir(); watch.mkdir()
            (phone / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.example.lift'}))
            (watch / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.other.watch', 'WKCompanionAppBundleIdentifier': 'com.other'}))
            with self.assertRaises(RuntimeError):
                identities(phone, watch)

    def test_build_install_and_launch_both_on_one_pair_without_erasing_data(self):
        pairs, devices = fixture()
        selected = choose_pair(pairs, devices)
        calls = []
        verified = []
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def runner(args, **options):
                calls.append(args)
                if args == ['open', '-a', 'Simulator'] and not options.get('optional'):
                    raise RuntimeError("Unable to find application named 'Simulator'")
                if args[:4] == ['xcrun', 'simctl', 'list', 'devices']:
                    return json.dumps(devices)
                if args[0] == 'xcodebuild':
                    scheme = args[args.index('-scheme') + 1]
                    phone = scheme == 'LittleLift'
                    app = root / '.simulator-build/Build/Products' / ('Debug-iphonesimulator' if phone else 'Debug-watchsimulator') / (scheme + '.app')
                    app.mkdir(parents=True)
                    info = {'CFBundleIdentifier': 'com.example.lift' if phone else 'com.example.lift.watchapp'}
                    if not phone: info['WKCompanionAppBundleIdentifier'] = 'com.example.lift'
                    (app / 'Info.plist').write_bytes(plistlib.dumps(info))
                return ''
            with contextlib.redirect_stdout(io.StringIO()):
                build_and_launch(selected, root=root, runner=runner,
                                 verifier=lambda *args, **kwargs: verified.append(args))
        self.assertEqual(verified, [(selected, 'com.example.lift', 'com.example.lift.watchapp')])
        launches = [args for args in calls if args[:3] == ['xcrun', 'simctl', 'launch']]
        self.assertEqual([args[3] for args in launches], ['paired-phone', 'watch'])
        self.assertIn('--littlelift-demo', launches[0])
        self.assertNotIn('--littlelift-demo', launches[1])
        installs = [i for i, args in enumerate(calls) if args[:3] == ['xcrun', 'simctl', 'install']]
        first_launch = next(i for i, args in enumerate(calls) if args[:3] == ['xcrun', 'simctl', 'launch'])
        self.assertTrue(all(i < first_launch for i in installs))
        self.assertEqual(len(installs), 2)
        self.assertFalse(any(set(args) & {'erase', 'uninstall', 'delete', 'unpair'} for args in calls))
        builds = [args for args in calls if args[0] == 'xcodebuild']
        self.assertIn('platform=iOS Simulator,id=paired-phone', builds[0])
        self.assertIn('platform=watchOS Simulator,id=watch', builds[1])

    def test_build_failure_never_proceeds_to_install(self):
        pairs, devices = fixture()
        calls = []
        def runner(args, **options):
            calls.append(args)
            if args[:4] == ['xcrun', 'simctl', 'list', 'devices']: return json.dumps(devices)
            if args[0] == 'xcodebuild': raise RuntimeError('Compile failed')
            return ''
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(RuntimeError):
                build_and_launch(choose_pair(pairs, devices), root=Path(temp), runner=runner)
        self.assertFalse(any(args[:3] == ['xcrun', 'simctl', 'install'] for args in calls))

    def test_delivery_check_waits_for_saved_plan_and_does_not_log_private_content(self):
        selected = choose_pair(*fixture())
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            for device in ('paired-phone', 'watch'):
                (base / device / 'Library/Application Support/LittleLift').mkdir(parents=True)
            phone = base / 'paired-phone/Library/Application Support/LittleLift/phone-v1.json'
            watch = base / 'watch/Library/Application Support/LittleLift/watch-v1.json'
            plan = {'id': 'current', 'title': 'PRIVATE WORKOUT', 'exercises': [{'name': 'PRIVATE EXERCISE'}]}
            phone.write_text(json.dumps({'plan': plan}))
            watch.write_text('{')  # Atomic writes/relaunch are allowed to take time.
            calls, waits = [], []
            def runner(args, **kwargs):
                calls.append(args)
                return str(base / args[3])
            def pause(seconds):
                waits.append(seconds)
                watch.write_text(json.dumps({'plan': plan, 'lastSnapshotDate': 1_001_000}))
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                verify_plan_delivery(selected, 'phone.bundle', 'watch.bundle', issued_after=1000, runner=runner, pause=pause, attempts=2)
            self.assertEqual(waits, [0.5])
            self.assertNotIn('PRIVATE', output.getvalue())
            self.assertTrue(all(args[2] == 'get_app_container' for args in calls))

    def test_open_apps_with_stale_or_missing_plan_do_not_count_as_sync_success(self):
        selected = choose_pair(*fixture())
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            for device, plan in [('paired-phone', {'id': 'new', 'exercises': [1]}), ('watch', {'id': 'old'})]:
                folder = base / device / 'Library/Application Support/LittleLift'
                folder.mkdir(parents=True)
                (folder / ('phone-v1.json' if device == 'paired-phone' else 'watch-v1.json')).write_text(json.dumps({'plan': plan}))
            runner = lambda args, **kwargs: str(base / args[3])
            with self.assertRaisesRegex(RuntimeError, 'NOT confirmed'):
                verify_plan_delivery(selected, 'phone.bundle', 'watch.bundle', issued_after=1000, runner=runner, attempts=1)
            # A matching ID with mismatched contents is not sufficient either.
            (base / 'watch/Library/Application Support/LittleLift/watch-v1.json').write_text(json.dumps({'plan': {'id': 'new'}}))
            with self.assertRaises(RuntimeError):
                verify_plan_delivery(selected, 'phone.bundle', 'watch.bundle', issued_after=1000, runner=runner, attempts=1)
            (base / 'watch/Library/Application Support/LittleLift/watch-v1.json').write_text(json.dumps({'plan': {'id': 'new', 'exercises': [1]}, 'lastSnapshotDate': 999_000}))
            with self.assertRaises(RuntimeError):
                verify_plan_delivery(selected, 'phone.bundle', 'watch.bundle', issued_after=1000, runner=runner, attempts=1)

    def test_delivery_check_fails_when_container_lookup_is_empty(self):
        with self.assertRaisesRegex(RuntimeError, 'data container'):
            verify_plan_delivery(choose_pair(*fixture()), 'phone', 'watch', issued_after=1000, runner=lambda *args, **kwargs: '')


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Dependency-free structural checks. This does not replace an Xcode build."""
from pathlib import Path
import importlib.util
import json
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('generator', root / 'scripts/generate_project.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
project = root / 'LittleLift.xcodeproj/project.pbxproj'
original = project.read_bytes()
schemes = {p: p.read_bytes() for p in (root / 'LittleLift.xcodeproj/xcshareddata/xcschemes').glob('*.xcscheme')}
generator.main()
assert original == project.read_bytes(), 'Regenerate the checked-in project.'

def scheme_signature(data):
    # Xcode reformats XML, adds an empty Testables element, and removes the
    # optional display-only BlueprintName when opening a watch scheme.
    # Compare actual build/launch configuration, not editor serialization.
    tree = ET.fromstring(data)
    for node in tree.iter():
        if node.tag == 'BuildableReference': node.attrib.pop('BlueprintName', None)
        for child in list(node):
            if child.tag == 'Testables' and not child.attrib and not len(child):
                node.remove(child)
    return ET.canonicalize(ET.tostring(tree, encoding='unicode'), strip_text=True)

for path, data in schemes.items():
    assert scheme_signature(path.read_bytes()) == scheme_signature(data), 'Regenerate the checked-in schemes.'

objects = generator.OBJECTS
assert not any(obj['isa'] in {'XCLocalSwiftPackageReference', 'XCSwiftPackageProductDependency'}
               for obj in objects.values()), 'Native targets must compile shared engine sources without package dependencies.'
id_pattern = re.compile(r'^[A-F0-9]{24}$')
def check_refs(value):
    if isinstance(value, dict):
        for item in value.values(): check_refs(item)
    elif isinstance(value, list):
        for item in value: check_refs(item)
    elif isinstance(value, str) and id_pattern.fullmatch(value):
        assert value in objects, f'Dangling Xcode reference: {value}'
check_refs(objects)

for key, obj in objects.items():
    if obj['isa'] == 'PBXFileReference' and obj.get('sourceTree') == 'SOURCE_ROOT':
        assert (root / obj['path']).exists(), f'Missing file: {obj["path"]}'
    if obj['isa'] == 'PBXNativeTarget':
        phases = [objects[phase] for phase in obj['buildPhases']]
        phase = next(p for p in phases if p['isa'] == 'PBXSourcesBuildPhase')
        actual = {objects[objects[build]['fileRef']]['path'] for build in phase['files']}
        folder = 'iPhone' if obj['name'] == 'LittleLift' else 'Watch'
        expected = {str(p.relative_to(root)) for p in [*root.glob(f'Apps/{folder}/*.swift'), *root.glob('Apps/Shared/*.swift'),
                                                      *root.glob('Sources/WorkoutCore/*.swift')]}
        if obj["name"] == "LittleLiftLauncher": expected = {"Apps/WatchLauncher/WorkoutLauncher.swift"}
        assert actual == expected, f'Incorrect source membership for {obj["name"]}'
        assert len(actual) == len(phase['files']), 'Duplicate source build entry'
        for path in actual:
            assert not re.search(r'^\s*(?:@testable\s+)?import\s+WorkoutCore\b', (root / path).read_text(), re.MULTILINE), \
                f'{path} imports a separate engine module despite direct source compilation.'
        resources = next(p for p in phases if p['isa'] == 'PBXResourcesBuildPhase')
        paths = {objects[objects[build]['fileRef']]['path'] for build in resources['files']}
        assert 'Apps/Shared/PrivacyInfo.xcprivacy' in paths

for path in [*root.glob('Config/*.plist'), root / 'Apps/Shared/PrivacyInfo.xcprivacy']:
    with path.open('rb') as file: plistlib.load(file)
for path in root.glob('Apps/*/Assets.xcassets/AppIcon.appiconset/Contents.json'):
    contents = json.loads(path.read_text())
    assert len(contents['images']) == 1, 'Keep one assigned icon entry per platform.'
    assert contents['images'][0]['platform'] == ('watchos' if '/Watch/' in str(path) else 'ios')
    for entry in contents['images']:
        png = path.parent / entry['filename']
        data = png.read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n'
        assert int.from_bytes(data[16:20], 'big') == 1024
        assert int.from_bytes(data[20:24], 'big') == 1024
        assert data[25] == 2, 'Use opaque RGB artwork without an alpha channel.'
        assert data == (root / 'Design/Brand/AppIcon.png').read_bytes(), 'Both apps must use the current brand artwork.'
for path in schemes:
    scheme = ET.parse(path)
    for ref in scheme.findall('.//BuildableReference'):
        assert ref.attrib['BlueprintIdentifier'] in objects
print('Project references, source membership, reproducibility, plists, schemes, privacy resources, and icon assets passed.')

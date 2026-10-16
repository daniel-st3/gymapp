#!/usr/bin/env python3
"""Install the finished brand asset into both catalogs. Standard library only.

The original artwork and its 1024px production export are in Design/Brand.
This script copies the artwork without redrawing or modifying it.
"""
from pathlib import Path
import json
import shutil

root = Path(__file__).resolve().parents[1]
source = root / 'Design/Brand/AppIcon.png'
png = source.read_bytes()
assert png[:8] == b'\x89PNG\r\n\x1a\n'
assert int.from_bytes(png[16:20], 'big') == int.from_bytes(png[20:24], 'big') == 1024
assert png[25] == 2, 'App Store artwork must be opaque RGB.'
for folder, platform in [('iPhone', 'ios'), ('Watch', 'watchos')]:
    assets = root / 'Apps' / folder / 'Assets.xcassets'
    icon = assets / 'AppIcon.appiconset'
    icon.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, icon / 'AppIcon.png')
    (assets / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2)+'\n')
    entries = [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': platform, 'size': '1024x1024'}]
    (icon / 'Contents.json').write_text(json.dumps({'images': entries, 'info': {'author': 'xcode', 'version': 1}}, indent=2)+'\n')
print('Installed the Little Lift icon for iPhone and Watch.')

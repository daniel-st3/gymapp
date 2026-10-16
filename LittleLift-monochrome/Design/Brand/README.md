# Little Lift app icon

The mark combines an off-white barbell with inward-facing L-shaped brackets and a small gray end plate on black. It matches the current monochrome interface and supersedes the earlier blue/red artwork.

`Logo-master.png` is the original generated artwork, retained locally and excluded from Git. `AppIcon.png` is its opaque RGB production export at Apple's required 1024 × 1024 size. The export changes only dimensions and file metadata, preserving the artwork. There is no baked-in rounded app tile; Apple applies its platform mask.

Run `python3 scripts/generate_icons.py` from the project root to copy the production artwork to both catalogs. There are no imaging dependencies at build time.

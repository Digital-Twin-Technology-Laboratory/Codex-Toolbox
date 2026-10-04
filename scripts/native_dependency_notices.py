#!/usr/bin/env python3
"""Build redistribution notices from the exact resolved helper dependency tree."""
import hashlib
import pathlib
import re
import sys
import tomllib

root = pathlib.Path(__file__).resolve().parents[1]
tree = pathlib.Path(sys.argv[1]).read_text()
cargo_home = pathlib.Path(sys.argv[2])
packages = sorted(set(re.findall(r'^([A-Za-z0-9_-]+) v([^\s]+)', tree, re.MULTILINE)))
git_manifests = []
for path in (cargo_home / 'git' / 'checkouts').glob('*/*/**/Cargo.toml'):
    try:
        package = tomllib.loads(path.read_text()).get('package', {})
        if isinstance(package.get('name'), str):
            git_manifests.append((package['name'], path))
    except (OSError, ValueError):
        pass
parts = ['Third-party notices for Codex Toolbox native analytics\n\nOpenAI Codex source revision b741e480e203f037ca726bc2a76d99a8e8668e66.\nOpenAI workspace crates are covered by LICENSE-OpenAI.\nThe following resolved dependency declarations and accompanying license/notice files are included for redistribution.\n']
seen_texts = set()
missing = []
for name, version in packages:
    if name.startswith('codex-') or name == 'toolbox-native-analytics':
        continue
    candidates = list((cargo_home / 'registry' / 'src').glob(f'*/{name}-{version}/Cargo.toml'))
    candidates += [p for n, p in git_manifests if n == name]
    if not candidates:
        missing.append(f'{name} {version}')
        continue
    manifest = candidates[0]
    package = tomllib.loads(manifest.read_text()).get('package', {})
    parts.append(f'\n=== {name} {version} ===\nLicense: {package.get("license", "See included license file")}\nRepository: {package.get("repository", "Not specified")}\n')
    files = []
    if package.get('license-file'):
        files.append(manifest.parent / package['license-file'])
    for path in manifest.parent.rglob('*'):
        if path.is_file() and re.match(r'(?i)^(license|licence|copying|notice)([._-].*)?$', path.name):
            files.append(path)
    for path in sorted(set(files)):
        try:
            if path.stat().st_size > 128 * 1024:
                continue
            content = path.read_text()
        except (OSError, UnicodeDecodeError):
            continue
        digest = hashlib.sha256(content.encode()).hexdigest()
        if digest in seen_texts:
            parts.append(f'License text {digest[:16]} also included elsewhere in this document.\n')
            continue
        seen_texts.add(digest)
        parts.append(f'\nLicense text {digest[:16]}\n{content}\n')
if missing:
    raise SystemExit('Missing manifests: ' + ', '.join(missing))
(root / 'NativeAnalytics' / 'THIRD-PARTY-NOTICES.txt').write_text(''.join(parts))
print(f'Generated notices for {len(packages)} resolved packages; {len(seen_texts)} distinct license texts.')

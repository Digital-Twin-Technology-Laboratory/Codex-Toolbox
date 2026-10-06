#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import urllib.request

BASE = 'https://zjwspace.cn/api/codex-toolbox/v1/'


def mirror(kind, path, write=False):
    if kind == 'codex-rate-card':
        from update_rate_card import validate_manifest
    elif kind == 'api-price-card':
        from update_api_price_card import validate_manifest
    else: raise ValueError('unknown manifest')
    local = json.loads(path.read_text())
    request = urllib.request.Request(BASE + kind + '.json', headers={'Accept': 'application/json', 'User-Agent': 'CodexToolbox-CompatibilityMirror/1.4.1'})
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 200 or response.url != BASE + kind + '.json': raise ValueError('invalid owned feed response')
        data = response.read(8 * 1024 * 1024 + 1)
        if len(data) > 8 * 1024 * 1024: raise ValueError('manifest too large')
    remote = json.loads(data)
    validate_manifest(local); validate_manifest(remote)
    by_id = {v['id']: v for v in remote['versions']}
    if any(by_id.get(v['id']) != v for v in local['versions']): raise ValueError('owned feed does not preserve bundled history')
    if write and local != remote: path.write_text(json.dumps(remote, ensure_ascii=False, indent=2) + '\n')
    return local != remote


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('kind', choices=['codex-rate-card', 'api-price-card'])
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    changed = mirror(args.kind, args.manifest, args.write)
    print('owned-manifest-validated' + ('-newer' if changed else '-unchanged'))


if __name__ == '__main__': main()

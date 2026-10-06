#!/usr/bin/env python3
"""Verify two server adapters through one URL and one unchanged client binary.

Uses synthetic upstream fixtures and a temporary directory; never changes the
installed app, user settings, production feed, or local Radar cache.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from threading import Thread

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--website-root', type=Path, required=True)
parser.add_argument('--client', type=Path, required=True)
args = parser.parse_args()
sys.path.insert(0, str(args.website_root))
from server.toolbox_feed import Store, DEFAULT_CONFIG
from server.toolbox_public import Store as PublicStore, recommendations
from server.test_toolbox_public import recommendation
from server.test_toolbox_feed import table, binding_and_scores, NOW

before = hashlib.sha256(args.client.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory() as folder:
    store = Store(folder)
    store.sync(NOW, lambda url: (table(), {}), True)

    recommendation_store = PublicStore(folder, 'recommendations')
    recommendation_store.publish(recommendations(recommendation()), NOW)
    for feed in ('codex-rate-card', 'api-price-card'):
        PublicStore(folder, feed).seed([json.loads((args.website_root / 'server/toolbox-seeds' / (feed + '.json')).read_text())])

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            raw = (Path(folder) / 'public' / Path(self.path).name).read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers(); self.wfile.write(raw)
        def log_message(self, *args):
            pass

    http = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    worker = Thread(target=http.serve_forever, daemon=True); worker.start()
    url = f'http://127.0.0.1:{http.server_port}/radar.json'
    def read():
        return subprocess.run([str(args.client), '--live-radar', '--radar-endpoint', url],
                              text=True, capture_output=True, check=True).stdout.strip()
    try:
        legacy = read()
        base = f'http://127.0.0.1:{http.server_port}/'
        def public_read():
            return subprocess.run([str(args.client), '--public-feeds-base', base], text=True, capture_output=True, check=True).stdout.strip()
        public_before = public_read()
        binding, scores = binding_and_scores()
        config = {**DEFAULT_CONFIG, 'adapter': 'radar-bench'}
        candidate = store.preview(config, lambda url: (binding if url == config['bindingURL'] else scores[0], {}), NOW)
        store.activate(candidate['candidate'], NOW)
        modern = read()
        updated = recommendations(recommendation())
        updated['recommendations'][0]['items'][0]['model'] = 'gpt-server-adapted'
        recommendation_store.publish(updated, NOW)
        for feed in ('codex-rate-card', 'api-price-card'):
            PublicStore(folder, feed).rollback(1)
        public_after = public_read()
        assert 'costRows=1' in legacy and 'overallRows=1' in legacy, legacy
        assert 'scoreLabel=Radar Bench 分数' in modern and 'costRows=0' in modern and 'overallRows=0' in modern, modern
        assert hashlib.sha256(args.client.read_bytes()).hexdigest() == before
        print(json.dumps({'clientSHA256': before, 'sameBinary': True, 'sameURL': True,
                          'legacy': legacy, 'modern': modern, 'publicBefore': public_before, 'publicAfter': public_after}, ensure_ascii=False, indent=2))
    finally:
        http.shutdown(); http.server_close(); worker.join()

#!/usr/bin/python3

import hashlib
import json
from pathlib import Path
import sys
import tomllib


bundle = Path(sys.argv[1])
catalog = []
for directory in sorted(path for path in bundle.iterdir() if path.is_dir()):
  info = tomllib.loads((directory / 'template.toml').read_text())['catalog'][directory.name]
  files = [
    {'name': path.name, 'md5': hashlib.md5(path.read_bytes(), usedforsecurity=False).hexdigest(),
     'mode': f'{path.stat().st_mode & 0o777:04o}'}
    for path in sorted(directory.iterdir()) if path.is_file() and path.name != '.noctalia-cache.json'
  ]
  metadata = {'version': 1, 'files': {entry['name']: entry['md5'] for entry in files}}
  (directory / '.noctalia-cache.json').write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n')
  catalog.append({'name': directory.name, 'display_name': info['name'], 'category': info['category'], 'files': files})
(bundle / 'catalog.json').write_text(json.dumps({'templates': catalog}, indent=2, sort_keys=True) + '\n')

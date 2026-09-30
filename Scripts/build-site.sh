#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Publish only this explicit list of static files, never the whole repository.
python3 - <<'PY'
from pathlib import Path
import shutil
output = Path('build/site')
if output.exists():
    shutil.rmtree(output)
(output / 'demo').mkdir(parents=True)
home = Path('docs/site/index.html').read_text()
(output / 'index.html').write_text(home.replace('../ui/wireframes.html', 'demo/'))
shutil.copyfile('docs/site/style.css', output / 'style.css')
shutil.copyfile('docs/ui/wireframes.html', output / 'demo/index.html')
(output / '.nojekyll').touch()
print('Static site ready: build/site')
PY

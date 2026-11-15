"""Package editable source assets, leaving caches and large renders out."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
ROOT=Path(__file__).resolve().parents[1]
target=ROOT/'exports/iris-editable-project.zip'
with ZipFile(target,'w',ZIP_DEFLATED,compresslevel=3) as z:
    for folder in ['assets','flows','scripts','scenes']:
        for p in (ROOT/folder).rglob('*'):
            if not p.is_file() or '__pycache__' in p.parts or p.suffix=='.blend1':continue
            if p.name in ['film-mix-raw.wav','recording-mono.wav']:continue
            z.write(p,Path('IrisDemo')/p.relative_to(ROOT))
    for name in ['README.md','shot-manifest.json']:
        z.write(ROOT/name,Path('IrisDemo')/name)
    z.write(ROOT/'exports/iris-demo.srt',Path('IrisDemo/exports/iris-demo.srt'))
print(target)

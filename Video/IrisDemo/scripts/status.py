"""Print production progress without interfering with Blender."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'renders/production-status.json'
if not p.exists():
    print('Final render has not been started.');raise SystemExit(0)
s=json.loads(p.read_text());m=json.loads((ROOT/'shot-manifest.json').read_text())
print('State:',s['state'])
print('Completed shots:',len(s['completed_shots']),'/',len(m['shots']))
print('Current shot:',s.get('current_shot','—'))
if s['state']=='running':
    shot=next(sh for sh in m['shots'] if sh['id']==s['current_shot'])
    frames=len(list((ROOT/'renders/final'/shot['id']).glob('*.png')))
    print('Current shot frames:',frames,'/',1 if shot['id']=='04_real_demo' else shot['frames'])
if 'error' in s:print('Error:',s['error'])
if s['state']=='complete':print(ROOT/'exports/iris-demo-4k60.mp4')

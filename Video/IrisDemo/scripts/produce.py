"""Durable, disk-bounded final render. Records state and validates every encoded shot."""
import subprocess,json,time,sys,hashlib,shutil,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BLENDER='/Applications/Blender.app/Contents/MacOS/Blender'
manifest=json.loads((ROOT/'shot-manifest.json').read_text())
state_path=ROOT/'renders/production-status.json'
scene_sha=hashlib.sha256((ROOT/'scenes/iris-film.blend').read_bytes()).hexdigest()
state={'state':'running','scene_sha256':scene_sha,'completed_shots':[],'started_at':time.strftime('%Y-%m-%dT%H:%M:%S%z')}
if state_path.exists():
    old=json.loads(state_path.read_text())
    if old.get('scene_sha256')!=scene_sha:raise RuntimeError('Scene changed. Archive previous final outputs before starting a new render.')
    state=old;state['state']='running'
def save():
    temp=state_path.with_suffix('.tmp');temp.write_text(json.dumps(state,indent=2));temp.replace(state_path)
def run(args,logname):
    with (ROOT/'renders'/logname).open('a') as log:subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,check=True,cwd=ROOT,env={**os.environ,'PYTHONUNBUFFERED':'1'})
def media_info(path):
    return json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_type,width,height,r_frame_rate','-of','json',str(path)]))
def validate(path,duration):
    info=media_info(path);v=next(s for s in info['streams'] if s['codec_type']=='video')
    assert (v['width'],v['height'],v['r_frame_rate'])==(3840,2160,'60/1'),info
    assert abs(float(info['format']['duration'])-duration)<.15,info
    return info
try:
    save()
    for shot in manifest['shots']:
        sid=shot['id'];state['current_shot']=sid;save()
        encoded=ROOT/'renders/encoded-final'/f'{sid}.mov'
        if sid not in state['completed_shots']:
            if shutil.disk_usage(ROOT).free<12*1024**3:raise RuntimeError('Less than 12 GiB free; rendering paused before disk exhaustion.')
            run([BLENDER,'--factory-startup','-b',str(ROOT/'scenes/iris-film.blend'),'-P',str(ROOT/'scripts/render.py'),'--','--final',sid],f'{sid}.log')
            # An interrupted encoder may leave a partial file; verify it before reusing it.
            if encoded.exists():
                try:validate(encoded,shot['duration'])
                except Exception:encoded.unlink()
            run([sys.executable,str(ROOT/'scripts/assemble.py'),'final',sid],f'{sid}-encode.log')
            validate(encoded,shot['duration']);state['completed_shots'].append(sid);save()
        # Temporary frames are reproducible from the saved scene; preserve one review frame per shot.
        folder=ROOT/'renders/final'/sid
        frames=sorted(folder.glob('*.png'))
        if frames:
            (ROOT/'review/final').mkdir(exist_ok=True)
            shutil.copy2(frames[len(frames)//2],ROOT/'review/final'/f'{sid}.png')
            for frame in frames:frame.unlink()
    state['state']='assembling';save()
    run([sys.executable,str(ROOT/'scripts/assemble.py'),'final'],'final-assembly.log')
    state['validation']=validate(ROOT/'exports/iris-demo-4k60.mp4',120)
    # Full decode detects corrupt or incomplete exports, beyond the metadata check.
    run([sys.executable,str(ROOT/'scripts/verify.py'),'final'],'final-validation.log')
    state['state']='complete';state['finished_at']=time.strftime('%Y-%m-%dT%H:%M:%S%z');save()
except Exception as exc:
    state['state']='failed';state['error']=str(exc);save();raise

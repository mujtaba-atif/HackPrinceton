"""Resumable per-shot renderer: --stills, --preview, or --final."""
import bpy,sys,json,time,os
from pathlib import Path
print('SCRIPT_STARTED',flush=True)
ROOT=Path(__file__).resolve().parents[1]
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
mode=args[0] if args else '--stills'
manifest=json.loads((ROOT/'shot-manifest.json').read_text())
only=args[1] if len(args)>1 else None
for sh in manifest['shots']:
    if only and sh['id']!=only:continue
    print('SCENE',sh['id'],flush=True)
    sc=bpy.data.scenes[sh['id']];bpy.context.window.scene=sc
    print('CONFIGURING_GPU',flush=True)
    # Device settings are preferences, so explicitly restore them in each background process.
    try:
        prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='METAL';prefs.get_devices()
        for dev in prefs.devices:dev.use=(dev.type=='METAL')
        sc.cycles.device='GPU'
    except Exception:sc.cycles.device='CPU'
    print('GPU_READY',flush=True)
    if mode=='--stills':
        sc.render.resolution_percentage=25;sc.cycles.samples=24
        frames=[min(180,sh['frames'])];out=ROOT/'review/stills';out.mkdir(parents=True,exist_ok=True)
    elif mode=='--preview':
        sc.render.engine='BLENDER_EEVEE';sc.render.resolution_percentage=25;sc.eevee.taa_render_samples=8
        frames=[1] if sh['id']=='07_real_demo' else range(1,sh['frames']+1,5)
        out=ROOT/'renders/preview'/sh['id'];out.mkdir(parents=True,exist_ok=True)
    else:
        # Samples are set when the scene is built (IRIS_SAMPLES), sized to the render budget.
        sc.render.engine='BLENDER_EEVEE';sc.render.resolution_percentage=100
        frames=[1] if sh['id']=='07_real_demo' else range(1,sh['frames']+1)
        if mode=='--benchmark':frames=range(180,190)
        out=ROOT/('renders/benchmark' if mode=='--benchmark' else 'renders/final')/sh['id'];out.mkdir(parents=True,exist_ok=True)
    for n,f in enumerate(frames):
        path=out/(sh['id']+'.png' if mode=='--stills' else f'{n+1:06d}.png')
        if path.exists():continue
        print('FRAME',f,flush=True)
        sc.frame_set(f);sc.render.filepath=str(path)
        print('RENDERING',str(path),flush=True)
        start=time.time();bpy.ops.render.render(write_still=True,scene=sc.name)
        with (ROOT/'renders/timings.jsonl').open('a') as log:log.write(json.dumps({'mode':mode,'shot':sh['id'],'frame':f,'seconds':time.time()-start})+'\n')
print('IRIS_RENDER_PASS_COMPLETE',mode,flush=True)

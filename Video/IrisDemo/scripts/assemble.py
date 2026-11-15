"""Assemble Blender frames, original iPhone footage, score and captions."""
from pathlib import Path
import json,sys,subprocess,shutil
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
mode=sys.argv[1] if len(sys.argv)>1 else 'preview'
manifest=json.loads((ROOT/'shot-manifest.json').read_text())
final=mode=='final';only=sys.argv[2] if len(sys.argv)>2 else None
W,H=(1920,1080) if final else (960,540)
FPS=manifest['fps'] if final else 12
D=manifest['duration']
framesroot=ROOT/'renders'/mode
out=ROOT/'exports';out.mkdir(exist_ok=True)
parts=ROOT/'renders'/('encoded-'+mode);parts.mkdir(exist_ok=True)

def run(cmd):
    print(' '.join(map(str,cmd)),flush=True)
    subprocess.run(list(map(str,cmd)),check=True)

def encoder():
    # Near-lossless intermediates; the export is encoded once more from these.
    return ['-c:v','libx264','-preset','medium','-crf','10','-pix_fmt','yuv420p'] if final else ['-c:v','libx264','-preset','fast','-crf','21','-pix_fmt','yuv420p']

ext='.mp4'

for sh in manifest['shots']:
    if only and sh['id']!=only:continue
    target=parts/(sh['id']+ext)
    if target.exists():continue
    folder=framesroot/sh['id']
    if sh['id']=='07_real_demo':
        base=folder/'000001.png'
        p=manifest['demo_screen_pixels'];dur=manifest['demo']['duration']
        x,y,sw,shh=[round(p[k]*W/1920) for k in ('x','y','width','height')]
        # antialiased rounded aperture prevents source pixels covering the bezel.
        mask=Image.new('L',(sw*2,shh*2));ImageDraw.Draw(mask).rounded_rectangle((0,0,sw*2-1,shh*2-1),radius=round(24*W/1920)*2,fill=255)
        mask=mask.resize((sw,shh),Image.Resampling.LANCZOS);maskpath=parts/'screen-mask.png';mask.save(maskpath)
        filter=f'[0:v]scale={W}:{H}[bg];[1:v]trim=duration={dur},setpts=PTS-STARTPTS,fps={FPS},scale={sw}:{shh}:flags=lanczos,setsar=1,format=rgba[screen];[2:v]format=gray[mask];[screen][mask]alphamerge[cut];[bg][cut]overlay={x}:{y}:shortest=1,format=yuv420p[v]'
        # The plate is one rendered frame, so the timed side text is drawn here: beats on the left that
        # follow the recording, notes on the right. Positions match the scene (100 px per Blender unit).
        k=W/1920;bold=str(ROOT/'assets/fonts/Nunito-ExtraBold.ttf');semi=str(ROOT/'assets/fonts/Nunito-SemiBold.ttf')
        beats=[(0,4.2,'Say what\nyou need.'),(4.6,12.4,'Iris guides\nyour hand.'),(12.8,16.6,'Take hold.'),(17.0,22.0,'Bring it\nclose.'),(22.4,dur,'Hear what\nit is.')]
        notes=[(4.8,21.8,'Outline traced live\nfrom segmentation',1.9),(7.0,21.8,'Fingertip-to-object\ndistance with LiDAR',.45),(22.6,dur,'Label read on-device,\nexplained in Iris’s voice',1.9)]
        overlays=[]
        def card(i,body,fontpath,size,color,x,z):
            im=Image.new('RGBA',(W,H));d=ImageDraw.Draw(im);f=ImageFont.truetype(fontpath,round(size*100*k))
            # Blender places a text object's first baseline at its origin.
            d.multiline_text((round((960+x*100)*k),round((540-z*100)*k)),body,font=f,fill=color,anchor='ls',spacing=round(size*100*k*.3))
            path=parts/f'demo-text-{i}.png';im.save(path);return path
        for i,(a,b,body) in enumerate(beats):overlays.append((card(i,body,bold,.78,'#FAFCFF',-8.4,1.6),a+.15,b))
        for i,(a,b,body,z) in enumerate(notes):overlays.append((card(10+i,body,semi,.34,'#E7F5FF',4.15,z),a,b))
        inputs=[];chain='[base]'
        filter=filter.replace(',format=yuv420p[v]','[base]')
        for n,(path,a,b) in enumerate(overlays):
            inputs+=['-loop','1','-framerate',FPS,'-t',dur,'-i',path]
            fade_out=min(b,dur)-.3
            filter+=f';[{3+n}:v]format=rgba,fade=t=in:st={a:.3f}:d=0.35:alpha=1'+(f',fade=t=out:st={fade_out:.3f}:d=0.3:alpha=1' if b<dur else '')+f'[t{n}];{chain}[t{n}]overlay=0:0[o{n}]'
            chain=f'[o{n}]'
        filter+=f';{chain}format=yuv420p[v]'
        run(['ffmpeg','-y','-v','warning','-loop','1','-framerate',FPS,'-i',base,'-i',ROOT/'assets/source/iris-locate-cut.mp4','-loop','1','-framerate',FPS,'-i',maskpath,*inputs,'-filter_complex',filter,'-map','[v]','-an','-t',dur,'-r',FPS,*encoder(),target])
    else:
        expected=sh['frames'] if final else len(range(1,sh['frames']+1,5))
        actual=len(list(folder.glob('*.png')))
        if actual!=expected:raise RuntimeError(f'{sh["id"]}: expected {expected} frames, got {actual}')
        run(['ffmpeg','-y','-v','warning','-framerate',FPS,'-i',folder/'%06d.png','-vf',f'scale={W}:{H}:flags=lanczos,setsar=1','-an',*encoder(),target])
if only:
    print('IRIS_SHOT_ENCODED',only,flush=True)
    sys.exit(0)
concat=parts/'concat.txt'
concat.write_text(''.join("file '"+str(parts/(sh['id']+ext))+"'\n" for sh in manifest['shots']))
# Feed the concat demuxer directly; avoid a duplicate multi-gigabyte master.

# Burn captions using transparent image strips; also deliver the SRT separately.
caps=json.loads((ROOT/'assets/audio/captions.json').read_text())
font=ImageFont.truetype(str(ROOT/'assets/fonts/Nunito-SemiBold.ttf'),round(W*.0175))
# Build one alpha caption strip, rather than running dozens of full-4K overlays.
h=round(H*.085)
blank=parts/'caption-blank.png';Image.new('RGBA',(W,h)).save(blank)
entries=[];cursor=0.0
for i,c in enumerate(caps):
    if c['start']>cursor:entries.append((blank,c['start']-cursor))
    im=Image.new('RGBA',(W,h));d=ImageDraw.Draw(im)
    bbox=d.textbbox((0,0),c['text'],font=font);tw=bbox[2]-bbox[0]
    x=(W-tw)//2;pad=round(W*.009)
    d.rounded_rectangle((x-pad,0,x+tw+pad,h-round(H*.015)),radius=round(H*.012),fill=(6,27,55,230))
    d.text((W//2,round(h*.33)),c['text'],font=font,anchor='mm',fill='#FAFCFF')
    path=parts/f'caption-{i:02}.png';im.save(path)
    entries.append((path,c['end']-c['start']));cursor=c['end']
if cursor<D:entries.append((blank,D-cursor))
caplist=parts/'captions-concat.txt'
caplist.write_text(''.join("file '"+str(p)+"'\nduration "+str(d)+"\n" for p,d in entries)+"file '"+str(blank)+"'\n")
capmovie=parts/'captions.mov'
run(['ffmpeg','-y','-v','warning','-f','concat','-safe','0','-i',caplist,'-vf',f'fps={FPS},format=argb','-t',D,'-c:v','qtrle',capmovie])
args=['ffmpeg','-y','-v','warning','-f','concat','-safe','0','-i',concat,'-i',ROOT/'assets/audio/film-mix.wav','-i',capmovie]
name='iris-demo-1080p60.mp4' if final else 'iris-demo-preview.mp4'
video=['-c:v','libx264','-preset','slow','-crf','16','-profile:v','high','-pix_fmt','yuv420p'] if final else encoder()
args+=['-filter_complex','[0:v][2:v]overlay=0:H-h-12:shortest=1[v]','-map','[v]','-map','1:a','-t',D,'-r',FPS,*video,'-c:a','aac','-b:a','320k','-movflags','+faststart',out/name]
run(args)
print('IRIS_EXPORT_READY',out/name,flush=True)

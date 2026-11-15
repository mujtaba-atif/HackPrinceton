from pathlib import Path
import subprocess,json,time
R=Path(__file__).resolve().parents[1];O=R/'renders/deadline';O.mkdir(exist_ok=True)
m=json.loads((R/'shot-manifest.json').read_text())
def run(a):
 print(' '.join(map(str,a)),flush=True);subprocess.run(list(map(str,a)),check=True)
enc=['-c:v','h264_videotoolbox','-b:v','18M','-pix_fmt','yuv420p']
for s in m['shots']:
 out=O/(s['id']+'.mp4')
 if out.exists():continue
 if s['id']=='04_real_demo':
  from PIL import Image,ImageDraw
  mask=Image.new('L',(710,1548));ImageDraw.Draw(mask).rounded_rectangle((0,0,709,1547),radius=44,fill=255);mask.resize((355,774),Image.Resampling.LANCZOS).save(O/'mask.png')
  vf='[0:v]scale=1920:1080[bg];[1:v]fps=60,scale=355:774:flags=lanczos,format=rgba[screen];[2:v]format=gray[mask];[screen][mask]alphamerge[cut];[bg][cut]overlay=443:153:shortest=1,format=yuv420p[v]'
  run(['ffmpeg','-y','-v','error','-loop','1','-framerate','60','-i',R/'renders/preview/04_real_demo/000001.png','-i',R/'assets/source/iris-locate-clean.mp4','-loop','1','-framerate','60','-i',O/'mask.png','-filter_complex',vf,'-map','[v]','-an','-t','40',*enc,out])
 else:
  vf='minterpolate=fps=60:mi_mode=mci:mc_mode=obmc:me_mode=bidir:me=hexbs:search_param=8:vsbmc=0,scale=1920:1080:flags=lanczos,tpad=stop_mode=clone:stop_duration=0.3'
  run(['ffmpeg','-y','-v','error','-i',R/'renders/encoded-preview'/(s['id']+'.mp4'),'-vf',vf,'-t',s['duration'],'-an',*enc,out])
 (O/'status.json').write_text(json.dumps({'completed_shot':s['id'],'time':time.time()}))
concat=O/'concat.txt';concat.write_text(''.join("file '"+str(O/(s['id']+'.mp4'))+"'\n" for s in m['shots']))
final=R/'exports/iris-demo-1080p60.mp4'
run(['ffmpeg','-y','-v','error','-f','concat','-safe','0','-i',concat,'-i',R/'assets/audio/film-mix.wav','-i',R/'renders/encoded-preview/captions.mov','-filter_complex','[2:v]scale=1920:92:flags=lanczos,fps=60[c];[0:v][c]overlay=0:H-h-24:shortest=1[v]','-map','[v]','-map','1:a','-t','120',*enc,'-c:a','aac','-b:a','320k','-movflags','+faststart',final])
run(['ffmpeg','-y','-v','error','-i',final,'-vf','scale=3840:2160:flags=lanczos','-c:v','h264_videotoolbox','-b:v','45M','-pix_fmt','yuv420p','-c:a','copy','-movflags','+faststart',R/'exports/iris-demo-4k60-upscaled.mp4'])
for name in ['iris-demo-1080p60.mp4','iris-demo-4k60-upscaled.mp4']:
 p=R/'exports'/name
 info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_type,width,height,r_frame_rate','-of','json',str(p)]))
 assert abs(float(info['format']['duration'])-120)<.2,info
 assert next(s for s in info['streams'] if s['codec_type']=='video')['r_frame_rate']=='60/1'
 (O/(name+'.json')).write_text(json.dumps(info,indent=2))
print('DEADLINE_EXPORT_COMPLETE',flush=True)

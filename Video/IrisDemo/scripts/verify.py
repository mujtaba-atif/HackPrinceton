"""Validate a completed preview or final movie and extract evenly spaced review frames."""
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
mode=sys.argv[1] if len(sys.argv)>1 else 'preview'
name='iris-demo-4k60.mp4' if mode=='final' else 'iris-demo-preview.mp4'
file=ROOT/'exports'/name
info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_type,width,height,r_frame_rate','-of','json',str(file)]))
v=next(s for s in info['streams'] if s['codec_type']=='video')
assert (v['width'],v['height'],v['r_frame_rate'])==((3840,2160,'60/1') if mode=='final' else (960,540,'12/1'))
assert any(s['codec_type']=='audio' for s in info['streams'])
assert abs(float(info['format']['duration'])-120)<.15
subprocess.run(['ffmpeg','-v','error','-i',str(file),'-f','null','-'],check=True)
review=ROOT/'review'/('export-'+mode);review.mkdir(exist_ok=True)
for t in [1,6,18,27,33,45,55,65,76,91,104,116]:
 subprocess.run(['ffmpeg','-v','error','-ss',str(t),'-i',str(file),'-frames:v','1','-vf','scale=960:540','-y',str(review/f'{t:03}.jpg')],check=True)
(ROOT/'review'/f'{mode}-validation.json').write_text(json.dumps(info,indent=2))
print('Validated:',file)

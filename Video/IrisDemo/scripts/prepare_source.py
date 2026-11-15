"""The demo's picture edit: a held clean frame under "Locate object selected / What do you want to find?"
(recording 13.5–16.6 s; the first seconds carry OS overlays), then 22.4 s to the end of the answer.
The silent wait between the question and guidance starting is cut."""
import subprocess,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
m=json.loads((ROOT/'shot-manifest.json').read_text())
(a0,a1),(b0,b1)=m['demo']['segments']
src=str(ROOT/'assets/source/iris-locate-original.mov')
f=(f"[0:v]trim=start=19:duration=0.04,setpts=PTS-STARTPTS,fps=30,tpad=stop_mode=clone:stop_duration={a1-a0}[held];"
   f"[0:v]trim=start={b0}:end={b1},setpts=PTS-STARTPTS,fps=30[run];[held][run]concat=n=2:v=1:a=0[v]")
subprocess.run(['ffmpeg','-y','-v','warning','-i',src,'-filter_complex',f,'-map','[v]','-t',str(m['demo']['duration']),'-r','30',
                '-c:v','libx264','-preset','slow','-crf','14','-pix_fmt','yuv420p',str(ROOT/'assets/source/iris-locate-cut.mp4')],check=True)
print('Demo picture edit ready')

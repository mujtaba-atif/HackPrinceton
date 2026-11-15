"""Original 112 BPM electronic score, recorded app voice, and timed captions."""
from pathlib import Path
import numpy as np, json, subprocess
from scipy.io import wavfile
from scipy.signal import butter,sosfilt
ROOT=Path(__file__).resolve().parents[1];SR=48000
MAN=json.loads((ROOT/'shot-manifest.json').read_text())
D=MAN['duration'];ST=MAN['starts']
IRIS=ST['05_so_we_built_iris'];LOC=ST['06_locate'];DEMO=ST['07_real_demo'];DEMO_END=DEMO+MAN['demo']['duration']
(A0,A1),(B0,B1)=MAN['demo']['segments']
QUESTION=LOC+.6
def quiet(at):return DEMO-.5<at<DEMO_END or QUESTION-.3<at<QUESTION+3.6
rng=np.random.default_rng(24)
mix=np.zeros((int(D*SR),2),np.float32)
def add(sig,start,gain=1,pan=0):
    i=int(start*SR)
    if i<0:sig=sig[-i:];i=0
    n=min(len(sig),len(mix)-i)
    if n<=0:return
    if sig.ndim==1:mix[i:i+n,0]+=sig[:n]*gain*np.sqrt((1-pan)/2);mix[i:i+n,1]+=sig[:n]*gain*np.sqrt((1+pan)/2)
    else:mix[i:i+n]+=sig[:n]*gain

def note(m):return 440*2**((m-69)/12)
beat=60/112;bar=beat*4
chords=[[50,57,60,65],[46,53,57,60],[41,48,53,57],[48,55,58,62]]
for k,start in enumerate(np.arange(0,D,bar*2)):
    chord=chords[k%4];dur=bar*2+.8;t=np.arange(int(SR*dur))/SR
    env=np.minimum(t/.6,1)*np.minimum((dur-t)/.9,1)
    duck=.72+.28*(1-np.exp(-((t%beat)/.11)))
    pad=np.zeros((len(t),2))
    for j,m in enumerate(chord):
        f=note(m);pad[:,0]+=np.sin(2*np.pi*f*.999*t+.3*j)/len(chord);pad[:,1]+=np.sin(2*np.pi*f*1.001*t+.3*j)/len(chord)
        pad[:,0]+=.14*np.sin(4*np.pi*f*t)/len(chord);pad[:,1]+=.14*np.sin(4*np.pi*f*t+.4)/len(chord)
    add(pad*(env*(duck if start>=IRIS-.5 else 1))[:,None],start,.13 if start>=IRIS-2 else .09)
    # Arpeggiated bell/pluck, restrained during the real demonstration.
    for q in range(16):
        at=start+q*beat/2;f=note(chord[[0,2,1,3,2,1,3,0][q%8]]+12);tt=np.arange(int(SR*.8))/SR
        pluck=(np.sin(2*np.pi*f*tt)+.3*np.sin(2*np.pi*f*2*tt))*np.exp(-tt*7)*(1-np.exp(-tt*120))
        if at<IRIS:continue  # the story opens on the pad alone
        add(pluck,at,.018 if quiet(at) else .06,pan=.5*np.sin(q))
        add(pluck,at+beat*.75,.015,pan=-.5*np.sin(q))
for k,at in enumerate(np.arange(0,D,beat)):
    if at<IRIS or at>D-4:continue  # drums enter with Iris
    t=np.arange(int(SR*.4))/SR
    kick=np.sin(2*np.pi*(48*t+5*(1-np.exp(-t*35))))*np.exp(-t*15)
    add(kick,at,.07 if quiet(at) else .19)
    if k%2:
        t=np.arange(int(SR*.16))/SR;noise=rng.normal(size=len(t));clap=sosfilt(butter(2,1700,fs=SR,btype='high',output='sos'),noise)*np.exp(-t*34)
        add(clap,at,.035)
    for half in [0,.5]:
        t=np.arange(int(SR*.09))/SR;hat=sosfilt(butter(2,7500,fs=SR,btype='high',output='sos'),rng.normal(size=len(t)))*np.exp(-t*65)
        add(hat,at+half*beat,.018,pan=.25 if half else -.25)
# Sweeps and glass chimes at chapter transitions.
for at in [v-.6 for k,v in ST.items() if v>0]:
    t=np.arange(int(SR*.8))/SR;noise=rng.normal(size=len(t));sweep=sosfilt(butter(2,[600,4800],fs=SR,btype='band',output='sos'),noise)*np.sin(np.pi*t/.8)**2
    add(sweep,at,.035)
    t=np.arange(int(SR*1.8))/SR;bell=(np.sin(2*np.pi*1174.66*t)+.25*np.sin(2*np.pi*1760*t))*np.exp(-t*5)
    add(bell,at+.55,.045)
fade=np.minimum(np.arange(len(mix))/SR/1.5,1)*np.minimum((D-np.arange(len(mix))/SR)/3,1)
mix*=fade[:,None]
# Decode source independently; no recording is sent to a service.
raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(ROOT/'assets/source/iris-locate-original.mov'),'-f','f32le','-ar',str(SR),'-ac','2','-'])
voice=np.frombuffer(raw,dtype=np.float32).reshape(-1,2).copy()
voice=sosfilt(butter(2,90,fs=SR,btype='high',output='sos'),voice,axis=0)
# Instrumental is ducked for both live app speech passages.
for start,end in [(QUESTION-.2,QUESTION+3.6),(DEMO,DEMO_END)]:
    a=int(start*SR);b=int(end*SR);mix[a:b]*=.30
add(voice[int(4.8*SR):int(8.4*SR)],QUESTION-.2,1.10)
# The demo edit: the first segment, then the second straight after it (the wait between is cut).
seg1=voice[int(A0*SR):int(A1*SR)].copy();seg2=voice[int(B0*SR):int(B1*SR)].copy()
ramp=int(.03*SR);seg1[-ramp:]*=np.linspace(1,0,ramp)[:,None];seg2[:ramp]*=np.linspace(0,1,ramp)[:,None]
add(seg1,DEMO,1.10);add(seg2,DEMO+(A1-A0),1.10)
mix=np.tanh(mix*1.05)*.92
wavfile.write(ROOT/'assets/audio/film-mix-raw.wav',SR,(mix*32767).astype(np.int16))
subprocess.run(['ffmpeg','-y','-v','error','-i',str(ROOT/'assets/audio/film-mix-raw.wav'),'-af','loudnorm=I=-16:TP=-1.5:LRA=11','-ar',str(SR),'-c:a','pcm_s24le',str(ROOT/'assets/audio/film-mix.wav')],check=True)
# Captions are based on locally transcribed, source-timed phrases.
r=json.loads((ROOT/'assets/audio/transcript.json').read_text());caps=[]
for seg in r['segments']:
    if seg['start']<9:delta=QUESTION-.2-4.8
    elif A0<=seg['start']<A1:delta=DEMO-A0
    elif seg['start']>=B0:delta=DEMO+(A1-A0)-B0
    else:continue
    words=seg.get('words',[])
    for i in range(0,len(words),8):
        group=words[i:i+8]
        if not group:continue
        caps.append({'start':group[0]['start']+delta,'end':group[-1]['end']+delta+.12,'text':''.join(w['word'] for w in group).strip()})
for i,c in enumerate(caps):
    c['text']=c['text'].replace('Poland spring','Poland Spring')
    if i+1<len(caps):c['end']=min(c['end'],caps[i+1]['start']-.02)
def stamp(t):
    ms=round(t*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
(ROOT/'exports/iris-demo.srt').write_text('\n\n'.join(f'{i+1}\n{stamp(c["start"])} --> {stamp(c["end"])}\n{c["text"]}' for i,c in enumerate(caps))+'\n')
(ROOT/'assets/audio/captions.json').write_text(json.dumps(caps,indent=2))
(ROOT/'assets/audio/LICENSE.txt').write_text('Instrumental score and transition effects: original procedural composition created for Iris. No third-party music samples used. Recorded speech: original supplied Iris demonstration, using its configured voice. Font licenses are in assets/fonts.\n')
print('Audio and captions ready')

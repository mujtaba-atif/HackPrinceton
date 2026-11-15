const app=document.querySelector('#app'),controls=document.querySelector('#controls'),caption=document.querySelector('#caption');
const {art,tokens}=IRIS_ASSETS;for(const [k,v]of Object.entries(tokens))document.documentElement.style.setProperty('--'+k,v);
let screen='loading',timers=[],touchY=0,transitioning=false,reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
const cameraRoutes=new Set(['find','guidance','found','close','analyze','reading','speaking','listening']);
let cameraStarted=0,cameraMode='locate',motionController=null,handDistance=.8,lastHandDistance=null,handVisible=true,guidanceBearing=0,trackingFrame=0;
document.querySelector('#reduce').checked=reduced;document.body.classList.toggle('reduced',reduced);
const mic='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="8" y="2" width="8" height="13" rx="4" fill="currentColor" stroke="none"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3M9 22h6"/></svg>';
const chevron='<svg viewBox="0 0 30 38" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="m3 15 12-12 12 12" opacity=".45"/><path d="m3 33 12-12 12 12"/></svg>';
const brand='<h2 class="brand" aria-label="Iris">'+[...'Iris'].map((c,i)=>`<span style="--i:${i}" aria-hidden="true">${c}</span>`).join('')+'</h2>';
// One accessible phrase, with decorative glyphs for a restrained entry-only light sweep.
function prismText(text,breakBefore=-1){
 let index=0;
 const words=text.split(' ').map((word,i)=>`${i===breakBefore?'<br>':i?' ':''}<span class="prism-word">${[...word].map(char=>`<span class="prism-char" style="--char:${index++}">${char}</span>`).join('')}</span>`).join('');
 return `<span class="sr-only">${text}</span><span class="prism-flow" aria-hidden="true">${words}</span>`;
}
const prismBrand=`<h2 class="brand prism-text">${prismText('Iris')}</h2>`;
const back='<button class="back" aria-label="Go back" data-action="back">‹</button>';
function later(fn,ms){timers.push(setTimeout(fn,ms))}function clear(){timers.forEach(clearTimeout);timers=[];cancelAnimationFrame(trackingFrame);trackingFrame=0}
function pill(text='Listening…',speaking=false){return `<div class="pill" role="status">${speaking?'<span class="voice-bars">'+[0,1,2,3,4].map(i=>`<i style="--d:${i*.11}s"></i>`).join('')+'</span>':`<span class="mic">${mic}</span>`}<span>${text}</span></div>`}
function buttons(items){controls.innerHTML=items.map(([text,action])=>`<button data-action="${action}">${text}</button>`).join('')}
function blob(head,detail){return `<div class="status-blob" role="status"><strong>${head}</strong><small>${detail}</small></div>`}
function guidanceState(){return {distance:handDistance,handVisible,targetVisible:screen!=='find',direction:handDistance===0?'reached':undefined,bearing:guidanceBearing}}
function cameraGlass(){return IrisGuidance.render(guidanceState())}
function trackingOverlay(){
 if(screen==='find')return '';
 const measurementValid=Number.isFinite(handDistance)&&handDistance>=0;
 if(handVisible&&measurementValid)lastHandDistance=handDistance;
 return lastHandDistance===null?'':IrisTracking.render(lastHandDistance,{handVisible,measurementValid});
}
function camera(state,inner){return `<section class="screen camera ${state}"><img class="camera-bg" src="camera-demo.png" alt="Demo camera scene: a water bottle on a wooden table"><div class="camera-shade"></div>${cameraGlass()}${back}${inner}${trackingOverlay()}</section>`}
function objectOutline(mode='locate',label=''){
 const {sourceWidth,sourceHeight,path}=IRIS_ASSETS.objectContour;
 const scanning=mode==='explore'||mode==='reading';
 return `<div class="object-boundary ${mode}"><svg aria-hidden="true" viewBox="0 0 ${sourceWidth} ${sourceHeight}" preserveAspectRatio="xMidYMid slice" fill="none"><defs><clipPath id="object-silhouette-clip"><path d="${path}"/></clipPath></defs>${scanning?'<g clip-path="url(#object-silhouette-clip)"><g class="object-scan"><rect x="240" y="469" width="290" height="38" fill="#72C7F5" opacity=".16"/><path d="M240 507H530" stroke="#E7F5FF" stroke-width="2.5"/></g></g>':''}<path class="object-tint" d="${path}"/><path class="contour-halo" d="${path}" pathLength="1"/><path class="contour-stroke" d="${path}" pathLength="1"/></svg>${label?`<span class="object-label">${label}</span>`:''}</div>`;
}
function miniCrew(){return `<div class="mini-crew" role="img" aria-label="Four Iris characters: Skye with ears, Pip with glasses, Nova in a lab coat, and Echo with headphones and a scarf">${Object.entries(IRIS_ASSETS.heroCrew).map(([name,svg],i)=>`<div class="mini-friend friend-${name}" style="--crew-i:${i}" aria-hidden="true"><div class="mini-idle">${svg}</div></div>`).join('')}</div>`}

// Decorative elements never intercept the app's controls or announce to screen readers.
function sprinkles(count=18,quiet=false){return `<div class="sprinkles ${quiet?'quiet':''}" aria-hidden="true">${Array.from({length:count},(_,i)=>{const x=quiet?(i%2?94:4):(i*47+13)%96;const y=quiet?18+i*10:(i*71+29)%94;return `<i class="sprinkle s${i%4}" style="--x:${x}%;--y:${y}%;--r:${i*41}deg;--delay:${-i*.63}s;--duration:${6+i%5}s;--drift:${i%2?-22:22}px;--ink:${['#72C7F5','#B5DEFA','#FAFCFF','#3299E3'][i%4]}"></i>`}).join('')}</div>`}
function glassFloat(){return '<div class="glass-float glass-float-a" aria-hidden="true"><i></i><b>✦</b></div><div class="glass-float glass-float-b" aria-hidden="true"><i></i></div>'}
function celebrate(){if(reduced)return;const layer=document.createElement('div');layer.className='celebration';layer.setAttribute('aria-hidden','true');layer.innerHTML=Array.from({length:32},(_,i)=>`<i style="--dx:${Math.cos(i*2.4)*(85+i%6*19)}px;--dy:${-130-Math.sin(i*1.7)*140}px;--r:${i*57}deg;--delay:${i%5*.045}s;--ink:${['#72C7F5','#B5DEFA','#FAFCFF','#3299E3'][i%4]}"></i>`).join('');app.append(layer);later(()=>layer.remove(),2300)}
function polish(route){if(route==='home')return;const surface=app.querySelector('.screen');const quiet=!['loading','home','options'].includes(route);surface.insertAdjacentHTML('beforeend',sprinkles(quiet?6:20,quiet));if(!quiet)surface.insertAdjacentHTML('beforeend',glassFloat());if(route==='home')surface.insertAdjacentHTML('beforeend',miniCrew());if(route==='found')celebrate()}

function render(route){clear();transitioning=false;if(route==='find'||!cameraRoutes.has(route))lastHandDistance=null;if(cameraRoutes.has(route)){const mode=['find','guidance','found','close'].includes(route)?'locate':'explore';if(!cameraRoutes.has(screen)||cameraMode!==mode)cameraStarted=performance.now();cameraMode=mode}screen=route;document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('active',b.dataset.route===route||b.dataset.route==='loading'&&route==='home'||b.dataset.route==='find'&&['guidance','found','close'].includes(route)||b.dataset.route==='analyze'&&['reading','speaking','listening'].includes(route)));
 if(route==='loading'){app.innerHTML=`<section class="screen loading">${brand}<div class="loading-status"><div class="spinner"></div><span role="status">Getting ready</span></div></section>`;buttons([['Skip to welcome','home']]);caption.textContent='Loading → welcome · side-swept title · four-character entrance';later(()=>render('home'),1600)}
 if(route==='home'){app.innerHTML=`<section class="screen home iris-landing">${IrisLanding.renderAtmosphere(IRIS_LANDING_IMAGE)}<h2 class="sr-only">Iris</h2><p class="sr-only">See Beyond the Surface</p><button class="landing-start" data-action="continue" aria-label="Swipe up to continue"><span class="sr-only">Swipe up</span></button></section>`;buttons([['Say “continue”','continue'],['Replay intro','loading']]);caption.textContent='Your original artwork · floating characters · flowing waves · white star streaks · purple text shimmer'}
 if(route==='options'){app.innerHTML=`<section class="screen options split-options">${back}<div class="water-well" aria-hidden="true">${[0,.8,1.6].map(d=>`<i style="--d:${d}s"></i>`).join('')}</div><button class="option find" data-action="find" aria-label="Locate an object">${IRIS_ASSETS.splitPanels.locate}<div class="face-art">${art.locateContent}<div class="motion-response map-response" aria-hidden="true"><div class="treasure-map-wrap">${IRIS_ASSETS.treasureMap}</div></div></div></button><button class="option analyze" data-action="analyze" aria-label="Explore an object">${IRIS_ASSETS.splitPanels.explore}<div class="face-art">${art.exploreContent}<div class="motion-response lens-response" aria-hidden="true"><div class="explore-optic"><i></i></div></div></div></button>${pill()}</section>`;buttons([['Say “locate”','find'],['Say “explore”','analyze'],['Replay entrance','options']]);caption.textContent='Locate above · Explore below · an equal split with a diagonal glass edge'}
 if(route==='find'){handDistance=.8;handVisible=true;guidanceBearing=0;app.innerHTML=camera('searching',blob('Looking…','Tell Iris what to locate'));buttons([['Say “locate my bottle”','guidance'],['No object found','missing'],['Back','options']]);caption.textContent='Locate · two luminous chevron trails guide your hand once a target is found'}
 if(route==='guidance'){app.innerHTML=camera('',`${objectOutline('locate','Bottle')}${pill('Say “go back” to finish')}`);buttons([['Move hand closer','near'],['Move hand away','far'],['Guide left','guide-left'],['Guide right','guide-right'],['Reach forward','guide-forward'],['Overshot — move back','guide-back'],[handVisible?'Hide hand':'Show hand','toggle-hand'],['Reach the object','found'],['Back','options']]);controls.insertAdjacentHTML('afterbegin',`<label class="distance-demo"><span>Demo hand distance</span><output id="demo-distance-value">${Math.round(handDistance*100)} cm</output><input type="range" id="demo-distance" aria-label="Demo hand distance in centimeters" min="0" max="80" step="1" value="${Math.round(handDistance*100)}"></label><label class="distance-demo"><span>Demo target direction</span><output id="demo-bearing-value">${bearingLabel(guidanceBearing)}</output><input type="range" id="demo-bearing" aria-label="Demo target direction in degrees" min="-180" max="180" step="1" value="${guidanceBearing}"></label>`);caption.textContent='Distance above the dotted line · two blue chevron trails react to direction and proximity'}
 if(route==='found'){handDistance=0;handVisible=true;app.innerHTML=camera('',`${objectOutline('success','Bottle found')}${pill('Got it! Bring it closer to read')}`);buttons([['Bring closer','close'],['Locate another','find'],['Back','options']]);caption.textContent='Success · the same object silhouette brightens for confirmation'}
 if(route==='close'){handDistance=.1;handVisible=true;guidanceBearing=0;app.innerHTML=camera('',`${objectOutline('success','Ready to read')}${pill('Close enough. Ready to explore')}`);buttons([['Explore this bottle','analyze'],['Back','options']]);caption.textContent='Reached reading distance · continue into exploration'}
 if(route==='analyze'){handDistance=.3;handVisible=true;guidanceBearing=0;app.innerHTML=camera('',`${objectOutline('explore')}${pill('Looking for text…')}`);buttons([['Text detected','reading'],['Back','options']]);caption.textContent='Explore · green object mask, distance above the connector and blue guidance chevrons'}
 if(route==='reading'){app.innerHTML=camera('',`${objectOutline('reading')}${pill('Reading live…')}`);buttons([['Result ready','speaking'],['Text lost','analyze'],['Back','options']]);caption.textContent='Live reading · updates when recognition is ready'}
 if(route==='speaking'){app.innerHTML=camera('',objectOutline('settled')+pill('Iris is speaking…',true));buttons([['Show spoken summary','summary'],['Ask a question','listening'],['Scan again','analyze'],['Back','options']]);caption.textContent='Simulated spoken result: “This is a 500 ml bottle of water.”'}
 if(route==='listening'){app.innerHTML=camera('',objectOutline('settled')+pill());buttons([['Ask “how much?”','answer'],['Scan again','analyze'],['Back','options']]);caption.textContent='Conversation · simulated voice follow-up'}
 polish(route);fitPreview();motionController?.setActive(route==='options');
}
function moveHand(next,animate=true){
 if(!Number.isFinite(next))return;
 next=Math.max(0,Math.min(.8,next));
 if(!handVisible){handVisible=true;render('guidance')}
 cancelAnimationFrame(trackingFrame);const start=handDistance,begin=performance.now();
 function step(now){
  const t=reduced||!animate?1:Math.min(1,(now-begin)/650),e=1-Math.pow(1-t,3);
  handDistance=start+(next-start)*e;lastHandDistance=handDistance;
  IrisTracking.update(app.querySelector('.hand-tracking'),handDistance);
  IrisGuidance.update(app,guidanceState());
  const slider=document.querySelector('#demo-distance'),value=document.querySelector('#demo-distance-value');
  if(slider)slider.value=Math.round(handDistance*100);if(value)value.textContent=Math.round(handDistance*100)+' cm';
  if(t<1)trackingFrame=requestAnimationFrame(step);else trackingFrame=0;
 }
 trackingFrame=requestAnimationFrame(step);
}

function bearingLabel(value){return value===0?'Straight ahead':Math.abs(value)===180?'Behind':`${Math.abs(value)}° ${value<0?'left':'right'}`}
function steerTarget(bearing){
 if(!Number.isFinite(bearing))return;
 guidanceBearing=Math.max(-180,Math.min(180,bearing));
 IrisGuidance.update(app,guidanceState());
 const slider=document.querySelector('#demo-bearing'),value=document.querySelector('#demo-bearing-value');
 if(slider)slider.value=guidanceBearing;if(value)value.textContent=bearingLabel(guidanceBearing);
}

function action(a){if(a==='continue'){if(screen!=='home'||transitioning)return;transitioning=true;celebrate();const wave=document.createElement('div');wave.className='pour';app.append(wave);later(()=>render('options'),reduced?0:850)}else if(a==='back'){render(['loading','home','options'].includes(screen)?'home':'options')}else if(a==='near'||a==='far'){moveHand(a==='near'?handDistance-.15:handDistance+.15)}else if(a.startsWith('guide-')){steerTarget({left:-90,right:90,forward:0,back:180}[a.slice(6)])}else if(a==='toggle-hand'){handVisible=!handVisible;render('guidance')}else if(a==='missing'){app.querySelector('.status-blob strong').textContent='Keep looking';app.querySelector('.status-blob small').textContent='Slowly move your phone around'}else if(a==='summary'){const old=app.querySelector('.summary');if(old){old.remove();return}const d=document.createElement('div');d.className='summary';d.innerHTML='<h3>A bottle of water</h3><p>The label says “WATER”, 500 ml.</p>';app.querySelector('.screen').append(d)}else if(a==='answer'){render('speaking');caption.textContent='Simulated spoken answer: “The bottle holds 500 millilitres.”'}else render(a)}
document.addEventListener('input',e=>{if(e.target.id==='demo-distance')moveHand(Number(e.target.value)/100,false);if(e.target.id==='demo-bearing')steerTarget(Number(e.target.value))});
document.addEventListener('click',e=>{const b=e.target.closest('[data-action],[data-route]');if(b)action(b.dataset.action||b.dataset.route)});
app.addEventListener('pointerdown',e=>touchY=e.clientY);app.addEventListener('pointerup',e=>{if(screen==='home'&&touchY-e.clientY>60)action('continue')});
app.addEventListener('pointermove',e=>{if(screen!=='home')return;const r=app.getBoundingClientRect();app.style.setProperty('--look-x',((e.clientX-r.left)/r.width-.5)*24+'px');app.style.setProperty('--look-y',((e.clientY-r.top)/r.height-.5)*16+'px')});
app.addEventListener('keydown',e=>{if(screen==='home'&&['ArrowUp','Enter',' '].includes(e.key)){e.preventDefault();action('continue')}if(e.key==='Escape')action('back')});
document.querySelector('#reduce').addEventListener('change',e=>{reduced=e.target.checked;document.body.classList.toggle('reduced',reduced);motionController?.setReduced(reduced)});const startRoute=new URLSearchParams(location.search).get('screen');render(startRoute==='home'||cameraRoutes.has(startRoute)?startRoute:'loading');
function fitPreview(){const height=screen==='home'?360*1846/852:800;const scale=innerWidth>760?Math.max(.5,Math.min(1,(innerHeight-140)/height)):1;document.documentElement.style.setProperty('--phone-height',height+'px');document.documentElement.style.setProperty('--phone-scale',scale);document.documentElement.style.setProperty('--phone-shrink',(height*(1-scale))+'px')}
addEventListener('resize',fitPreview);fitPreview();

motionController=IrisMotion.createController({surface:app,enableButton:document.querySelector('#enable-phone-motion'),gentleButton:document.querySelector('#gentle-shake'),quickButton:document.querySelector('#quick-shake'),status:document.querySelector('#motion-status'),reduced,onPreview:()=>{if(screen!=='options')render('options')}});
const motionPreference=matchMedia('(prefers-reduced-motion: reduce)');
motionPreference.addEventListener('change',e=>{reduced=e.matches;document.querySelector('#reduce').checked=reduced;document.body.classList.toggle('reduced',reduced);motionController.setReduced(reduced)});

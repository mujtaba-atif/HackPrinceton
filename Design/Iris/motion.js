/* Shared, bounded motion response. Sensor samples stay on this device. */
(function(root){
 'use strict';
 const clamp=(v,min,max)=>Math.max(min,Math.min(max,v));
 class MotionResponse{
  constructor(){this.reset()}
  reset(){this.target=0;this.value=0;this.sampleAt=-Infinity;this.gravity=null;this.angle=null}
  sample(event,angle,now){
   if(!Number.isFinite(angle)||!Number.isFinite(now))return false;
   if(angle!==this.angle){this.gravity=null;this.angle=angle}
   const radians=angle*Math.PI/180;
   const project=a=>a&&Number.isFinite(a.x)&&Number.isFinite(a.y)?a.x*Math.cos(radians)+a.y*Math.sin(radians):null;
   let x=project(event.acceleration);
   if(x===null){
    const total=project(event.accelerationIncludingGravity);
    if(total===null)return false;
    if(this.gravity===null){this.gravity=total;this.sampleAt=now;return true}
    const dt=clamp((now-this.sampleAt)/1000,0,.1);
    this.gravity+=(total-this.gravity)*(1-Math.exp(-dt/.45));
    x=total-this.gravity;
   }
   this.target=-clamp((Math.abs(x)<.2?0:x)/10,-1,1);
   this.sampleAt=now;
   return true;
  }
  step(dt,now){
   if(now-this.sampleAt>180)this.target=0;
   this.value+=(this.target-this.value)*(1-Math.exp(-clamp(dt,0,.05)/.065));
   if(Math.abs(this.value)<.0001&&this.target===0)this.value=0;
   return this.value;
  }
 }
 function createController({surface,enableButton,gentleButton,quickButton,status,reduced=false,onPreview=()=>{}}){
  const model=new MotionResponse();
  let active=false,enabled=false,requesting=false,frame=0,lastTime=0,demo=null,watchdog=0,observed=false;
  const write=v=>{
   surface.style.setProperty('--map-shake-x',(v*14).toFixed(3)+'px');
   surface.style.setProperty('--map-shake-r',(v*2.2).toFixed(3)+'deg');
   surface.style.setProperty('--lens-shake-x',(v*22).toFixed(3)+'px');
   surface.style.setProperty('--lens-shake-r',(v*3.5).toFixed(3)+'deg');
  };
  const announce=text=>{status.textContent=text};
  function reset(){model.reset();demo=null;write(0)}
  function tick(now){
   frame=0;
   if(!active||reduced||document.hidden){reset();return}
   const dt=lastTime?Math.min((now-lastTime)/1000,.05):1/60;lastTime=now;
   if(demo){
    const t=(now-demo.start)/1000;
    if(t<1.5)model.sample({acceleration:{x:Math.sin(t*Math.PI*2*demo.hz)*demo.strength*Math.sin(Math.PI*t/1.5),y:0}},0,now);
    else demo=null;
   }
   write(model.step(dt,now));
   if(demo||Math.abs(model.value)>.0001||Math.abs(model.target)>.0001)frame=requestAnimationFrame(tick);
  }
  function wake(){if(!frame&&active&&!reduced&&!document.hidden){lastTime=0;frame=requestAnimationFrame(tick)}}
  function onMotion(event){
   if(!enabled||!active||reduced||document.hidden)return;
   const angle=window.screen?.orientation?.angle??window.orientation??0;
   if(model.sample(event,angle,performance.now())){
    if(!observed){observed=true;clearTimeout(watchdog);announce('Phone motion is on — shake left and right.')}
    wake();
   }
  }
  function stopSensor(){
   window.removeEventListener('devicemotion',onMotion);clearTimeout(watchdog);enabled=false;
   enableButton.textContent='Enable phone motion';enableButton.setAttribute('aria-pressed','false');
  }
  async function toggleSensor(){
   if(requesting)return;
   if(enabled){stopSensor();reset();announce('Phone motion is off. The gentle sway continues.');return}
   onPreview();
   if(reduced){announce('Turn off Reduce motion to enable phone movement.');return}
   if(!window.isSecureContext){announce('Open the HTTPS preview to enable phone motion.');return}
   const api=window.DeviceMotionEvent;
   if(!api){announce('Phone sensors are unavailable here. Try the shake previews below.');return}
   const policy=document.permissionsPolicy||document.featurePolicy;
   if(policy&&(!policy.allowsFeature('accelerometer')||!policy.allowsFeature('gyroscope'))){announce('Open this preview in its own browser tab to enable phone motion.');return}
   requesting=true;enableButton.disabled=true;
   try{
    if(typeof api.requestPermission==='function'&&await api.requestPermission()!=='granted'){
     announce('Motion access was not allowed. The gentle sway and shake previews still work.');return;
    }
    enabled=true;observed=false;window.addEventListener('devicemotion',onMotion,{passive:true});
    enableButton.textContent='Disable phone motion';enableButton.setAttribute('aria-pressed','true');
    announce('Move your phone left and right to start.');
    watchdog=window.setTimeout(()=>{if(!observed)announce('No phone movement received yet. Use a supported phone or try the shake previews.');},5000);
   }catch(error){announce('Phone motion could not be enabled. You can still try the shake previews.')}
   finally{requesting=false;enableButton.disabled=false}
  }
  function simulate(strength,hz){
   onPreview();if(reduced){announce('Turn off Reduce motion to try the shake preview.');return}
   reset();demo={start:performance.now(),strength,hz};announce(strength>5?'Previewing a quick shake.':'Previewing a gentle shake.');wake();
  }
  enableButton.addEventListener('click',toggleSensor);
  gentleButton.addEventListener('click',()=>simulate(4,1.6));
  quickButton.addEventListener('click',()=>simulate(13,3.4));
  document.addEventListener('visibilitychange',()=>{if(document.hidden){cancelAnimationFrame(frame);frame=0;reset()}});
  window.addEventListener('pagehide',()=>{stopSensor();cancelAnimationFrame(frame);frame=0;reset()});
  return {
   setActive(value){active=value;if(!active){cancelAnimationFrame(frame);frame=0;reset()}},
   setReduced(value){reduced=value;if(reduced){stopSensor();cancelAnimationFrame(frame);frame=0;reset();announce('Reduced motion is on. Illustrations stay still.')}else announce('Gentle sway is on. Try a shake preview or enable phone motion.')}
  };
 }
 if(typeof module==='object'&&module.exports)module.exports={MotionResponse};
 else root.IrisMotion={MotionResponse,createController};
})(typeof window==='undefined'?globalThis:window);

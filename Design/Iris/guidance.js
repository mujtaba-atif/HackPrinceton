/* Browser-only guidance demo. Distances are supplied in meters, never inferred from pixels. */
(function(root){
 'use strict';
 const directions={forward:0,back:180,left:-18,right:18,reached:0};
 const instructions={forward:'Reach forward',back:'Ease your hand back',left:'Move your hand left',right:'Move your hand right',reached:'Object reached'};
 const arrowPath='M22 4L41 45L29 39L29 228L22 240L15 228L15 39L3 45Z';
 const palette=[[0,[237,249,255]],[.35,[151,222,255]],[.7,[34,93,221]],[1,[20,157,255]]];

 function reading(distance){
  if(!Number.isFinite(distance)||distance<0)return {available:false,meters:null,inches:null,value:'—',unit:'',secondary:'Distance unavailable'};
  const inches=distance/0.0254;
  return {available:true,meters:distance,inches,value:inches.toFixed(1),unit:'in',secondary:(distance*100).toFixed(0)+' cm away'};
 }

 function colorAt(progress){
  let a=palette[0],b=palette[palette.length-1];
  for(let i=1;i<palette.length;i++)if(progress<=palette[i][0]){a=palette[i-1];b=palette[i];break}
  const t=(progress-a[0])/(b[0]-a[0]);
  return `rgb(${a[1].map((value,i)=>Math.round(value+(b[1][i]-value)*t)).join(',')})`;
 }

 function state(options={}){
  const {distance=.8,handVisible=true,targetVisible=true}=options;
  let direction=Object.hasOwn(directions,options.direction)?options.direction:'forward';
  const result=reading(distance);
  const mode=!targetVisible?'searching':!handVisible?'lost':!result.available?'unavailable':distance===0||direction==='reached'?'reached':'tracking';
  if(mode==='reached')direction='reached';
  const active=mode==='tracking'||mode==='reached';
  const progress=active?Math.max(0,Math.min(1,1-distance/.8)):0;
  const instruction=mode==='searching'?'Locate an object to begin':mode==='lost'?'Bring your hand into view':mode==='unavailable'?'Waiting for a measurement':instructions[direction];
  const value=active?result.value:'—';
  const unit=active?'in':'';
  const secondary=mode==='searching'?'No target selected':mode==='lost'?'Hand not visible':mode==='unavailable'?'Distance unavailable':mode==='reached'?'Ready to pick up':result.secondary;
  return {mode,direction,progress,angle:directions[direction],color:colorAt(progress),value,unit,secondary,instruction,
   description:active?`Demo distance from hand to object: ${result.value} inches. ${instruction}.`:`Demo hand-to-object distance unavailable. ${instruction}.`};
 }

 function arrow(side,s){
  const id='iris-guidance-'+side;
  const height=s.progress*240;
  return `<div class="guidance-arrow ${side}"><svg class="guidance-arrow-core" viewBox="0 0 44 244" fill="none" aria-hidden="true">
   <defs><clipPath id="${id}-clip"><path d="${arrowPath}"/></clipPath><linearGradient id="${id}-fill" x1="22" y1="240" x2="22" y2="0" gradientUnits="userSpaceOnUse"><stop stop-color="#159FFF"/><stop offset=".42" stop-color="#245FE8"/><stop offset=".77" stop-color="#8CD9FF"/><stop offset="1" stop-color="#F4FCFF"/></linearGradient></defs>
   <path class="guidance-aura" d="${arrowPath}" stroke="currentColor" stroke-width="10" opacity=".16"/>
   <path class="guidance-base" d="${arrowPath}" fill="currentColor" fill-opacity=".12" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>
   <g clip-path="url(#${id}-clip)"><rect class="guidance-fill" x="0" y="${244-height}" width="44" height="${height}" fill="url(#${id}-fill)"/><path class="guidance-sweep" d="M0 215H44V244H0Z" fill="#EDFAFF" opacity=".7"/></g>
   <path class="guidance-shine" d="M8 38L22 10L36 38M19 55V220" stroke="#F1FCFF" stroke-opacity=".8" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>
  </svg></div>`;
 }

 function render(options={}){
  const s=state(options);
  return `<div class="guidance-arrows" data-mode="${s.mode}" data-direction="${s.direction}" style="--guidance-progress:${s.progress};--guidance-angle:${s.angle}deg;--guidance-color:${s.color}" aria-hidden="true">${arrow('left',s)}${arrow('right',s)}</div>
   <section class="distance-hud" data-mode="${s.mode}" aria-label="${s.description}"><span class="distance-heading"><i></i>HAND → OBJECT</span><div class="distance-reading"><strong class="distance-value">${s.value}</strong><span class="distance-unit">${s.unit}</span></div><span class="distance-secondary">${s.secondary}</span><span class="distance-instruction">${s.instruction}</span></section>`;
 }

 function update(container,options={}){
  if(!container)return;
  const s=state(options),arrows=container.querySelector('.guidance-arrows'),hud=container.querySelector('.distance-hud');
  if(arrows){
   arrows.dataset.mode=s.mode;arrows.dataset.direction=s.direction;
   arrows.style.setProperty('--guidance-progress',s.progress);
   arrows.style.setProperty('--guidance-angle',s.angle+'deg');
   arrows.style.setProperty('--guidance-color',s.color);
   for(const fill of arrows.querySelectorAll('.guidance-fill')){fill.setAttribute('y',244-s.progress*240);fill.setAttribute('height',s.progress*240)}
  }
  if(hud){
   hud.dataset.mode=s.mode;hud.setAttribute('aria-label',s.description);
   for(const [key,value] of Object.entries({value:s.value,unit:s.unit,secondary:s.secondary,instruction:s.instruction})){
    const element=hud.querySelector('.distance-'+key);if(element)element.textContent=value;
   }
  }
 }

 const api={reading,render,update};
 if(typeof module==='object'&&module.exports)module.exports=api;else root.IrisGuidance=api;
})(typeof window==='undefined'?globalThis:window);

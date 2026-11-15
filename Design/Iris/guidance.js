/* Browser-only guidance demo. Distances are supplied in meters, never inferred from pixels. */
(function(root){
 'use strict';
 const directions={forward:0,back:180,left:-90,right:90,reached:0};
 const instructions={forward:'Reach forward',back:'Ease your hand back',left:'Move your hand left',right:'Move your hand right',reached:'Object reached'};
 const chevronPath='M-32 18L0 0L32 18L32 30L0 12L-32 30Z';
 const steps=[
  {y:24,scale:.44,curve:1,base:[188,238,255],bright:[240,252,255]},
  {y:78,scale:.62,curve:.68,base:[109,191,247],bright:[189,238,255]},
  {y:142,scale:.8,curve:.34,base:[52,122,216],bright:[89,190,255]},
  {y:220,scale:1,curve:0,base:[32,76,175],bright:[25,158,255]}
 ];
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
  // Signed target bearing: left is negative, straight ahead is zero, right is positive.
  const bearing=Number.isFinite(options.bearing)?Math.max(-180,Math.min(180,options.bearing)):directions[direction];
  if(direction!=='reached')direction=Math.abs(bearing)>135?'back':bearing<-.5?'left':bearing>.5?'right':'forward';
  const result=reading(distance);
  const mode=!targetVisible?'searching':!handVisible?'lost':!result.available?'unavailable':distance===0||direction==='reached'?'reached':'tracking';
  if(mode==='reached')direction='reached';
  const active=mode==='tracking'||mode==='reached';
  const progress=active?Math.max(0,Math.min(1,1-distance/.8)):0;
  const instruction=mode==='searching'?'Locate an object to begin':mode==='lost'?'Bring your hand into view':mode==='unavailable'?'Waiting for a measurement':instructions[direction];
  const value=active?result.value:'—';
  const unit=active?'in':'';
  const secondary=mode==='searching'?'No target selected':mode==='lost'?'Hand not visible':mode==='unavailable'?'Distance unavailable':mode==='reached'?'Ready to pick up':result.secondary;
  return {mode,direction,progress,angle:mode==='tracking'?bearing:0,color:colorAt(progress),value,unit,secondary,instruction,
   description:active?`Demo distance from hand to object: ${result.value} inches. ${instruction}.`:`Demo hand-to-object distance unavailable. ${instruction}.`};
 }

 function chevronStep(index,s){
  const step=steps[index];
  const color=`rgb(${step.base.map((value,i)=>Math.round(value+(step.bright[i]-value)*s.progress)).join(',')})`;
  return {transform:`translate(40 ${step.y}) scale(${step.scale})`,color};
 }

 function arrow(side,s){
  return `<div class="guidance-arrow ${side}"><svg class="guidance-arrow-core" viewBox="0 0 80 260" fill="none" aria-hidden="true">${steps.map((_,index)=>{
   const step=chevronStep(index,s);
   return `<g class="guidance-chevron" data-step="${index}" transform="${step.transform}" style="--step-color:${step.color};--step-index:${index}">
    <g class="guidance-chevron-heading">
    <path class="guidance-chevron-aura" d="${chevronPath}" stroke="var(--step-color)" stroke-width="6" stroke-linejoin="round" opacity=".18"/>
    <path class="guidance-chevron-face" d="${chevronPath}" fill="var(--step-color)" stroke="#D7F6FF" stroke-opacity=".22" stroke-width=".8" stroke-linejoin="round"/>
    <path class="guidance-chevron-rim" d="M-32 18L0 0L32 18" stroke="#EDFBFF" stroke-opacity=".72" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>
    </g></g>`;
  }).join('')}</svg></div>`;
 }

 function render(options={}){
  const s=state(options);
  return `<div class="guidance-arrows" data-mode="${s.mode}" data-direction="${s.direction}" style="--guidance-progress:${s.progress};--guidance-angle:${s.angle}deg;--guidance-color:${s.color}" aria-hidden="true">${arrow('left',s)}${arrow('right',s)}</div>`;
 }

 function update(container,options={}){
  if(!container)return;
  const s=state(options),arrows=container.querySelector('.guidance-arrows');
  if(arrows){
   arrows.dataset.mode=s.mode;arrows.dataset.direction=s.direction;
   arrows.style.setProperty('--guidance-progress',s.progress);
   const current=parseFloat(arrows.style.getPropertyValue('--guidance-angle'))||0;
   const turn=((s.angle-current)%360+540)%360-180;
   arrows.style.setProperty('--guidance-angle',(current+turn)+'deg');
   arrows.style.setProperty('--guidance-color',s.color);
   for(const chevron of arrows.querySelectorAll('.guidance-chevron')){
    const step=chevronStep(Number(chevron.dataset.step),s);
    chevron.setAttribute('transform',step.transform);
    chevron.style.setProperty('--step-color',step.color);
   }
  }

 }

 const api={reading,render,update};
 if(typeof module==='object'&&module.exports)module.exports=api;else root.IrisGuidance=api;
})(typeof window==='undefined'?globalThis:window);

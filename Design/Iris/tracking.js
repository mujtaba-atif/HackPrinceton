/* Editable camera-overlay geometry for the simulated design preview. */
(function(root){
 'use strict';
 const anchor={x:244,y:420};
 const points=[[337,641],[316,601],[300,592],[290,578],[280,568],[314,578],[312,539],[308,510],[304,486],[330,575],[334,533],[335,506],[334,481],[345,582],[352,544],[354,520],[352,502],[352,596],[358,574],[358,553],[356,539]];
 const chains=[[0,1,2,3,4],[0,5,6,7,8],[5,9,10,11,12],[9,13,14,15,16],[13,17,18,19,20],[0,17],[5,9,13,17]];
 const silhouette='M321 648L309 614Q305 603 297 595L278 578Q270 573 275 566Q279 561 287 566L305 579L299 493Q298 482 305 482Q312 483 313 492L318 551L327 559L329 486Q329 477 336 477Q343 478 342 488L341 555L346 560L347 507Q347 498 354 499Q361 500 360 509L356 569L360 570L354 544Q353 537 360 536Q367 537 367 545L365 603Q362 621 352 648Z';
 function geometry(distance){
  const d=Math.max(0,Math.min(.8,Number.isFinite(distance)?distance:.8));
  const t=d/.8,tx=-60*(1-t),ty=-66*(1-t);
  const tip={x:points[8][0]+tx,y:points[8][1]+ty};
  return {distance:d,tx,ty,tip,anchor,label:{x:(anchor.x+tip.x)/2-29,y:(anchor.y+tip.y)/2-15}};
 }
 function vectors(distance=.8){
  const g=geometry(distance);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 800" fill="none" aria-hidden="true">
   <g id="handDistanceConnector"><path id="handDistanceGlow" d="M244 420L${g.tip.x} ${g.tip.y}" stroke="#72E6CE" stroke-width="6" opacity=".18"/><path id="handDistanceLine" d="M244 420L${g.tip.x} ${g.tip.y}" stroke="#ADFFE1" stroke-width="1.7" stroke-dasharray="3 4"/><circle cx="244" cy="420" r="5.5" fill="#0B3035" stroke="#6FF1B1" stroke-width="2"/></g>
   <g id="handPose" transform="translate(${g.tx} ${g.ty})">
    <path id="handGhost" d="${silhouette}" fill="#72C7F5" fill-opacity=".07" stroke="#E7F5FF" stroke-opacity=".35" stroke-width="1.2" stroke-linejoin="round"/>
    <g id="handBones" stroke-linecap="round" stroke-linejoin="round">${chains.map(chain=>`<polyline points="${chain.map(i=>points[i].join(',')).join(' ')}" stroke="#72C7F5" stroke-opacity=".2" stroke-width="6"/><polyline points="${chain.map(i=>points[i].join(',')).join(' ')}" stroke="#BDEEFF" stroke-width="1.8"/>`).join('')}</g>
    <g id="handLandmarks">${points.map(([x,y],i)=>`<circle cx="${x}" cy="${y}" r="${i===8?4.5:2.8}" fill="${i===8?'#6FF1B1':'#FAFCFF'}" stroke="#248DB2" stroke-width="1.3"/>`).join('')}</g>
    <circle id="handTipPulse" cx="304" cy="486" r="9" stroke="#6FF1B1" stroke-width="1.5" opacity=".65"/>
   </g>
  </svg>`;
 }
 function render(distance=.8){
  return `<div class="hand-tracking" role="img" aria-label="Simulated hand landmarks and fingertip-to-object connector">${vectors(distance)}<span class="hand-tracked"><i></i>Hand tracked</span></div>`;
 }
 function update(element,distance){
  if(!element)return;
  const g=geometry(distance);
  element.querySelector('#handPose')?.setAttribute('transform',`translate(${g.tx} ${g.ty})`);
  for(const id of ['handDistanceGlow','handDistanceLine'])element.querySelector('#'+id)?.setAttribute('d',`M244 420L${g.tip.x} ${g.tip.y}`);
 }
 const api={anchor,points,chains,silhouette,geometry,vectors,render,update};
 if(typeof module==='object'&&module.exports)module.exports=api;else root.IrisTracking=api;
})(typeof window==='undefined'?globalThis:window);

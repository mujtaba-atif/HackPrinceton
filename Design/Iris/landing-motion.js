/* Preserve the supplied landing artwork; animate only softly masked copies of its pixels. */
(function(root){
 'use strict';
 const starPath='M0-12C1.9-3.2 3.2-1.9 12 0C3.2 1.9 1.9 3.2 0 12C-1.9 3.2-3.2 1.9-12 0C-3.2-1.9-1.9-3.2 0-12Z';
 const stars=[
  {x:741,y:185,scale:2.45,trail:1,delay:'-.4s'},
  {x:160,y:365,scale:.58,trail:.75,delay:'-2s'},
  {x:760,y:775,scale:.55,trail:.8,delay:'-3.6s'}
 ];
 function attribute(value){return String(value).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}
 function renderAtmosphere(imageUrl='landing-reference.png'){
  return `<div class="landing-atmosphere" aria-hidden="true"><svg class="landing-atmosphere-svg" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 852 1846" preserveAspectRatio="none" fill="none" focusable="false">
   <defs>
    <image id="landing-artwork" href="${attribute(imageUrl)}" x="0" y="0" width="852" height="1846" preserveAspectRatio="none"/>
    <filter id="irisLandingMaskFeather" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="10"/></filter>
    <filter id="irisLandingWaveFeather" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="19"/></filter>
    <filter id="irisLandingRimGlow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="8"/></filter>
    <filter id="irisLandingTextAlpha" filterUnits="userSpaceOnUse" x="145" y="260" width="565" height="240" color-interpolation-filters="sRGB">
     <feColorMatrix type="luminanceToAlpha"/>
     <feComponentTransfer><feFuncA type="linear" slope="5" intercept="-3.4"/></feComponentTransfer>
    </filter>
    <clipPath id="irisLandingInteriorClip"><rect x="14" y="14" width="824" height="1818" rx="94"/></clipPath>
    <clipPath id="irisLandingSourceClip"><rect x="22" y="22" width="808" height="1802" rx="94"/></clipPath>
    <clipPath id="irisLandingTextClip"><rect x="145" y="260" width="565" height="240"/></clipPath>
    <linearGradient id="irisLandingSceneFade" x1="0" y1="590" x2="0" y2="1570" gradientUnits="userSpaceOnUse"><stop stop-color="white" stop-opacity="0"/><stop offset=".07" stop-color="white"/><stop offset=".93" stop-color="white"/><stop offset="1" stop-color="white" stop-opacity="0"/></linearGradient>
    <linearGradient id="irisLandingTrail" x1="-190" y1="0" x2="12" y2="0" gradientUnits="userSpaceOnUse"><stop stop-color="#FFFFFF" stop-opacity="0"/><stop offset=".35" stop-color="#DCEFFF" stop-opacity=".3"/><stop offset=".76" stop-color="#FFFFFF"/><stop offset="1" stop-color="#FFFFFF"/></linearGradient>
    <linearGradient id="irisLandingRibbon" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#8E7CFF" stop-opacity="0"/><stop offset=".45" stop-color="#8495FF" stop-opacity=".23"/><stop offset=".7" stop-color="#80D9FF" stop-opacity=".34"/><stop offset="1" stop-color="#3177FF" stop-opacity="0"/></linearGradient>
    <linearGradient id="irisLandingRibbonEdge"><stop stop-color="#A0CFFF" stop-opacity="0"/><stop offset=".4" stop-color="#BCE9FF" stop-opacity=".7"/><stop offset=".75" stop-color="#81A8FF" stop-opacity=".5"/><stop offset="1" stop-color="#AE8BFF" stop-opacity="0"/></linearGradient>
    <filter id="irisLandingTrailGlow" x="-40%" y="-300%" width="180%" height="700%"><feGaussianBlur stdDeviation="4"/></filter>
    <mask id="irisLandingTopMask" maskUnits="userSpaceOnUse" x="0" y="0" width="852" height="1846">
     <path d="M-35-35H570C463 68 377 136 265 185C154 231 63 279-35 392Z" fill="white" filter="url(#irisLandingWaveFeather)"/>
    </mask>
    <mask id="irisLandingBottomMask" maskUnits="userSpaceOnUse" x="0" y="0" width="852" height="1846">
     <rect x="-30" y="1460" width="912" height="430" fill="white" filter="url(#irisLandingWaveFeather)"/>
     <rect x="285" y="1558" width="280" height="234" rx="30" fill="black" filter="url(#irisLandingMaskFeather)"/>
    </mask>
    <mask id="irisLandingCrewMask" maskUnits="userSpaceOnUse" x="0" y="0" width="852" height="1846">
     <rect x="0" y="590" width="852" height="980" fill="url(#irisLandingSceneFade)"/>
     <circle cx="760" cy="775" r="46" fill="black" filter="url(#irisLandingMaskFeather)"/>
    </mask>
    <mask id="irisLandingRimMask" maskUnits="userSpaceOnUse" x="0" y="0" width="852" height="1846">
     <rect x="0" y="0" width="852" height="1846" fill="white"/>
     <rect x="90" y="710" width="692" height="775" rx="40" fill="black" filter="url(#irisLandingWaveFeather)"/>
    </mask>
    <mask id="irisLandingTextMask" maskUnits="userSpaceOnUse" x="145" y="260" width="565" height="240" style="mask-type:alpha">
     <use href="#landing-artwork" filter="url(#irisLandingTextAlpha)"/>
    </mask>
    <linearGradient id="irisLandingPurplePass"><stop stop-color="#FFFFFF" stop-opacity="0"/><stop offset=".2" stop-color="#FFFFFF" stop-opacity=".1"/><stop offset=".42" stop-color="#AE8BFF" stop-opacity=".86"/><stop offset=".62" stop-color="#7959F2"/><stop offset=".8" stop-color="#C9AEFF" stop-opacity=".65"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>
    <linearGradient id="irisLandingRimLight" x1="82" y1="1020" x2="778" y2="1020" gradientUnits="userSpaceOnUse"><stop stop-color="#5B9EFF" stop-opacity="0"/><stop offset=".35" stop-color="#AEF8FF"/><stop offset=".65" stop-color="#B3F9FF"/><stop offset="1" stop-color="#70ACFF" stop-opacity="0"/></linearGradient>
   </defs>
   <use class="landing-original-image" href="#landing-artwork"/>
   <g clip-path="url(#irisLandingInteriorClip)">
    <g mask="url(#irisLandingTopMask)"><use class="landing-wave-top-image" href="#landing-artwork" clip-path="url(#irisLandingSourceClip)"/></g>
    <g mask="url(#irisLandingBottomMask)"><use class="landing-wave-bottom-image" href="#landing-artwork" clip-path="url(#irisLandingSourceClip)"/></g>
    <g mask="url(#irisLandingTopMask)">
     <g class="landing-flow-ribbon landing-flow-top"><path d="M-70 400C135 170 320 210 600-60L-70-60Z" fill="url(#irisLandingRibbon)"/><path d="M-55 363C140 172 335 185 600-50" stroke="url(#irisLandingRibbonEdge)" stroke-width="3"/></g>
     <g class="landing-flow-ribbon landing-flow-top-secondary"><path d="M-65 390C140 245 325 235 630-45" stroke="url(#irisLandingRibbonEdge)" stroke-width="2"/></g>
    </g>
    <g mask="url(#irisLandingBottomMask)">
     <g class="landing-flow-ribbon landing-flow-bottom"><path d="M-70 1700C165 1935 480 1780 925 1450L925 1900H-70Z" fill="url(#irisLandingRibbon)"/><path d="M-70 1710C165 1920 480 1770 925 1460" stroke="url(#irisLandingRibbonEdge)" stroke-width="3"/></g>
     <g class="landing-flow-ribbon landing-flow-bottom-secondary"><path d="M-60 1820C230 1970 480 1640 920 1650" stroke="url(#irisLandingRibbonEdge)" stroke-width="3"/></g>
    </g>
    <g mask="url(#irisLandingCrewMask)"><use class="landing-crew-image" href="#landing-artwork" clip-path="url(#irisLandingSourceClip)"/></g>
    <g clip-path="url(#irisLandingTextClip)" mask="url(#irisLandingTextMask)"><rect class="landing-title-sheen" x="-280" y="260" width="270" height="240" fill="url(#irisLandingPurplePass)"/></g>
    ${stars.map(star=>`<g class="landing-star" transform="translate(${star.x} ${star.y})" style="--streak-delay:${star.delay}">
     <g transform="rotate(-16) scale(${star.trail})"><g class="landing-star-streak">
      <path d="M-190 0H8" stroke="url(#irisLandingTrail)" stroke-width="12" stroke-linecap="round" filter="url(#irisLandingTrailGlow)"/>
      <path d="M-190 0H8" stroke="url(#irisLandingTrail)" stroke-width="3.5" stroke-linecap="round"/>
      <circle cx="8" cy="0" r="4" fill="#FFFFFF"/>
     </g></g>
     <path class="landing-star-flash" d="${starPath}" transform="scale(${star.scale})" fill="#FFFFFF"/>
    </g>`).join('')}
   </g>
  </svg></div>`;
 }
 const api={renderAtmosphere};
 if(typeof module==='object'&&module.exports)module.exports=api;else root.IrisLanding=api;
})(typeof window==='undefined'?globalThis:window);

/* Rebuild portable SVG states from the same generators used by the live preview. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const guidance = require('../guidance.js');
const tracking = require('../tracking.js');
const landing = require('../landing-motion.js');
const read = name => fs.readFileSync(path.join(root, name));
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const assets = [];
const xml = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const style = css => `<style><![CDATA[${css}]]></style>`;
const font = `@font-face{font-family:Nunito;font-style:normal;font-weight:800;src:url(data:font/ttf;base64,${read('fonts/iris-3.ttf').toString('base64')}) format('truetype')}`;
function save(file, svg, description, width, height) {
  const data = '<?xml version="1.0" encoding="UTF-8"?>\n' + svg.trim() + '\n';
  fs.writeFileSync(path.join(__dirname, file), data);
  assets.push({file, description, width, height, sha256:hash(data)});
}
function contents(svg) { return svg.slice(svg.indexOf('>') + 1, svg.lastIndexOf('</svg>')); }
function wrap(content, title, css = '') {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="360" height="800" viewBox="0 0 360 800" fill="none"><title>${xml(title)}</title>${style(css)}${content}</svg>`;
}
const arrowCSS = `.guidance-chevron{color:var(--step-color)}
.guidance-chevron-aura{fill:currentColor;stroke:currentColor;stroke-width:5px;opacity:.2;filter:blur(3px)}
.guidance-chevron-face{fill:currentColor;fill-opacity:.88}
.guidance-chevron-rim{fill:none;stroke:#C1EDFF;stroke-width:.8;stroke-opacity:.45;stroke-linejoin:round}`;
for (const [direction,bearing] of [['forward',0],['left',-90],['right',90],['back',180]]) {
  const markup = guidance.render({distance:.8, bearing});
  const svgs = [...markup.matchAll(/<svg\b[\s\S]*?<\/svg>/g)].map(match=>match[0]);
  if (svgs.length !== 2) throw new Error('Expected exactly two guidance trails');
  const trails = svgs.map((svg,index) => `<g transform="translate(${index ? 284 : 4} 230) scale(.9)" style="filter:drop-shadow(0 0 7px #279FFF55)">${contents(svg).replaceAll('<g class="guidance-chevron-heading">', `<g class="guidance-chevron-heading" transform="rotate(${bearing} 0 15)">`)}</g>`).join('');
  save(`guidance-${direction}.svg`, wrap(trails, `Iris guidance arrows: ${direction}`, arrowCSS), `Two four-chevron trails at ${bearing} degrees, 0.8 meter proximity palette; animations paused.`,360,800);
}
const labelCSS = `${font}\n#handDistanceLabel{font-family:Nunito,ui-rounded,sans-serif;font-size:13px;font-weight:800;letter-spacing:.1px;font-variant-numeric:tabular-nums;fill:#F5FFFC;stroke:#061B37B3;stroke-width:2.5px;stroke-linejoin:round;paint-order:stroke fill}`;
for (const distance of [.8,.3,0]) {
  const value = (distance/.0254).toFixed(1);
  save(`hand-distance-${distance}m.svg`,wrap(contents(tracking.vectors(distance)),`Iris hand-to-object measurement: ${value} inches`,labelCSS),`Production tracking geometry with bare ${value} in label and embedded Nunito font.`,360,800);
}
save('hand-distance-held.svg',wrap(contents(tracking.vectors(.3,{handVisible:false})),'Iris retained hand-to-object measurement: 11.8 inches',labelCSS),'Last valid 0.3 m sample held during hand loss: number and connector remain; skeleton is hidden.',360,800);
const image = 'data:image/png;base64,' + read('landing-reference.png').toString('base64');
let landingSVG = landing.renderAtmosphere(image).match(/<svg\b[\s\S]*?<\/svg>/)?.[0];
if (!landingSVG) throw new Error('Expected landing SVG');
landingSVG = landingSVG.replace('viewBox="0 0 852 1846"','width="852" height="1846" viewBox="0 0 852 1846"');
const stillCSS = '.landing-star-streak,.landing-star-flash,.landing-title-sheen,.landing-flow-ribbon{opacity:0}';
landingSVG = landingSVG.replace(/(<svg[^>]*>)/,`$1<title>Iris landing: exact supplied artwork, still state</title>${style(stillCSS)}`);
save('landing-static.svg',landingSVG,'Still/reduced-motion state from the landing generator. The original artwork is embedded PNG pixels, not redrawn vector characters.',852,1846);
const sourceFiles = ['guidance.js','tracking.js','landing-motion.js','landing-motion.css','style.css','landing-reference.png','fonts/iris-3.ttf'];
fs.writeFileSync(path.join(__dirname,'manifest.json'),JSON.stringify({
  revision:25,
  provenance:'Generated from local runtime modules; these are not direct Figma node exports.',
  livePreview:'https://app-vv74nvdykzsio2xxoy5pgrvgmdczd43ramggdbyipubmjv56i7pp.makeproxy-c.figma.site/?screen=guidance',
  sourceFiles:sourceFiles.map(file=>({file:'../'+file,sha256:hash(read(file))})),
  assets
},null,2)+'\n');
console.log(`Generated ${assets.length} self-contained SVG states.`);

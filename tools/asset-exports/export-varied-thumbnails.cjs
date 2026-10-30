const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('C:/Users/drews/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = 'C:/Users/drews/Development/Roblox Dev/Get Funded!';
const sourceFolder = 'C:/Users/drews/.codex/generated_images/01a0ea4e-7a65-7f90-84ea-54df3ed9428a';
const assets = [
 ['exec-924a12a2-20d8-4d39-9ba2-d1cd974c8cb4.png','04-climb-the-charts.png'],
 ['exec-dcbdb601-1f4b-4400-8320-6f2761c2aabd.png','05-bull-or-bear.png'],
 ['exec-4a6f222f-9144-453c-8ba8-0f81a70f1610.png','06-next-level.png'],
];
async function main() {
 const checks = [];
 const previews = [];
 for (const [source,name] of assets) {
  const out = path.join(root,'thumbnails',name);
  try { await fs.access(out); throw new Error('Destination already exists: '+out); } catch(e) { if(e.code !== 'ENOENT') throw e; }
  await sharp(path.join(sourceFolder,source)).resize(1920,1080,{fit:'fill',kernel:'lanczos3'}).removeAlpha().toColourspace('srgb').png({compressionLevel:9,adaptiveFiltering:true,palette:false}).toFile(out);
  const meta = await sharp(out).metadata();
  const {size} = await fs.stat(out);
  checks.push({name,width:meta.width,height:meta.height,format:meta.format,space:meta.space,channels:meta.channels,palette:meta.isPalette,bytes:size,under3MB:size<3000000});
  previews.push({input:await sharp(out).resize(320,180).png().toBuffer(),left:previews.length*336,top:0});
 }
 await sharp({create:{width:992,height:180,channels:3,background:'#15182b'}}).composite(previews).png().toFile(path.join(__dirname,'varied-thumbnails-small-size-qa.png'));
 await fs.writeFile(path.join(root,'assets/imagegen/get-funded-thumbnails-varied/export-verification.json'),JSON.stringify(checks,null,2));
 console.log(JSON.stringify(checks,null,2));
 if(checks.some(c=>c.width!==1920||c.height!==1080||!c.under3MB||c.format!=='png'))process.exitCode=1;
}
main().catch(e=>{console.error(e);process.exitCode=1;});

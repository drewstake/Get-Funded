const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('C:/Users/drews/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = 'C:/Users/drews/Development/Roblox Dev/Get Funded!/assets/thumbnails';
async function main() {
 const names = (await fs.readdir(root,{withFileTypes:true})).filter(x=>x.isFile()&&x.name.endsWith('.png')).map(x=>x.name).sort();
 const checks=[];
 for(let i=0;i<names.length;i++){
  const name=names[i];
  const destFolder=path.join(root,'jpeg-upload','batch-'+(Math.floor(i/5)+1));
  await fs.mkdir(destFolder,{recursive:true});
  const dest=path.join(destFolder,name.replace(/\.png$/i,'.jpeg'));
  try{await fs.access(dest);throw new Error('Destination exists: '+dest);}catch(e){if(e.code!=='ENOENT')throw e;}
  let buffer,quality;
  for(quality=92;quality>=80;quality-=2){
   buffer=await sharp(path.join(root,name)).removeAlpha().toColourspace('srgb').jpeg({quality,progressive:false,chromaSubsampling:'4:2:0',optimiseCoding:true,mozjpeg:false}).toBuffer();
   if(buffer.length<500000)break;
  }
  if(buffer.length>=3000000)throw new Error('JPEG exceeds upload size');
  await fs.writeFile(dest,buffer,{flag:'wx'});
  const meta=await sharp(buffer,{failOn:'warning'}).metadata();
  await sharp(buffer,{failOn:'warning'}).raw().toBuffer();
  if(meta.format!=='jpeg'||meta.width!==1920||meta.height!==1080||meta.isProgressive||meta.hasAlpha)throw new Error('JPEG validation failed');
  checks.push({file:path.relative(root,dest),quality:Math.max(quality,80),bytes:buffer.length,format:meta.format,width:meta.width,height:meta.height,progressive:meta.isProgressive,channels:meta.channels,space:meta.space,hasProfile:meta.hasProfile,pass:true});
 }
 await fs.writeFile(path.join(root,'jpeg-upload','verification.json'),JSON.stringify(checks,null,2));
 await fs.writeFile(path.join(root,'jpeg-upload','README.md'),'# JPEG upload test\n\nThese are smaller baseline RGB JPEG copies of the nine finished PNGs. All are 1920 x 1080, 16:9, and below 3 MB. No artwork, title, or cropping changes were made; JPEG compression can introduce small quality differences.\n\nTry uploading a single JPEG first to isolate the PNG or batch upload path. This is a diagnostic alternative, not a confirmed fix for the Roblox error.\n\nBatch 1 contains 5 images; batch 2 contains 4. Original PNGs are unchanged.\n');
 console.log(JSON.stringify(checks,null,2));
}
main().catch(e=>{console.error(e);process.exitCode=1;});


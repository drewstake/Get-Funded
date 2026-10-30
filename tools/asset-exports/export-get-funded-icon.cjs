const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/drews/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root = 'C:/Users/drews/Development/Roblox Dev/Get Funded!';
const source = 'C:/Users/drews/.codex/generated_images/01a0ea4e-7a65-7f90-84ea-54df3ed9428a/exec-e5c43168-717d-40ee-b32b-adef4cc960a0.png';
const icons = path.join(root, 'icons');
const archive = path.join(root, 'assets/imagegen/get-funded-game-icon');
(async()=>{
 fs.mkdirSync(icons,{recursive:true}); fs.mkdirSync(archive,{recursive:true});
 let base='get-funded-icon', n=1;
 while(fs.existsSync(path.join(icons,base+'.png')) || fs.existsSync(path.join(icons,base+'.jpeg')) || fs.existsSync(path.join(archive,base+'-master.png'))){n++;base='get-funded-icon-v'+n;}
 const meta=await sharp(source).metadata();
 if(meta.width!==meta.height) throw new Error('Generated icon is not square');
 fs.copyFileSync(source,path.join(archive,base+'-master.png'),fs.constants.COPYFILE_EXCL);
 const png=path.join(icons,base+'.png'), jpeg=path.join(icons,base+'.jpeg');
 await sharp(source).resize(512,512,{kernel:'lanczos3'}).removeAlpha().toColourspace('srgb').png({compressionLevel:9,adaptiveFiltering:true}).toFile(png);
 await sharp(source).resize(512,512,{kernel:'lanczos3'}).removeAlpha().toColourspace('srgb').jpeg({quality:93,progressive:false,chromaSubsampling:'4:4:4'}).toFile(jpeg);
 const preview=path.join(archive,base+'-150px-preview.png');
 await sharp(png).resize(150,150).png().toFile(preview);
 const files=[];
 for(const p of [png,jpeg]){
  const m=await sharp(p).metadata(); await sharp(p).raw().toBuffer();
  const bytes=fs.statSync(p).size;
  if(m.width!==512||m.height!==512||m.channels!==3||m.hasAlpha||bytes>=3000000) throw new Error('Icon validation failed: '+p);
  files.push({path:p,bytes,format:m.format,width:m.width,height:m.height,channels:m.channels,hasAlpha:m.hasAlpha,space:m.space,progressive:m.isProgressive||false});
 }
 fs.writeFileSync(path.join(archive,base+'-prompt.txt'),"Use case: ads-marketing.\nAsset type: finished square Roblox experience icon for the simulated trading game \"Get Funded!\".\nCreate one original polished, colorful stylized 3D game icon, square 1:1 composition targeting 1024x1024. A strong, simple trading-chart emblem rather than a room scene: five chunky beveled candlestick bars with clearly defined vertical wicks, mostly luminous emerald green with one coral-red pullback candle, moving coherently upward across the upper half. One bold warm-gold rising arrow integrated behind the candles. Toy-like blocky materials and appealing dimensional form matching a playful Roblox game. Deep cobalt blue and rich purple background with restrained radial screen glow, dramatic cyan rim light, warm gold highlights, strong depth and clean separated silhouettes. A little soft shadow grounds the emblem.\nVery prominent professional bold extruded game title across the lower half, two centered lines with exact text:\n\"GET\"\n\"FUNDED!\"\nGET is large warm white; FUNDED! is bigger golden yellow. Heavy dark navy outline and shallow 3D depth make the text exceptionally readable at 150x150. Clean correctly spelled type, balanced tight kerning, do not bend or obscure letters. The chart and title form one cohesive composition. Keep the complete title and arrow inside a generous 8% safe margin. Full-bleed square artwork with no rounded-corner app frame.\nNo people, no desk, no computer-room scene, no tiny interface text, no extra copy, no dollar amounts, no currency symbols, no coins, no real-money claims, no Roblox logos, no watermark. The chart represents simulated gameplay. Crisp high-end stylized game artwork, restrained detail for small-size recognition.",{flag:'wx'});
 const report={tool:'built-in image_gen',source,original:{width:meta.width,height:meta.height},files,preview,requirementsSource:'https://create.roblox.com/docs/production/publishing/experience-icons',requirements:'Square, at least 512x512; exported at 512x512 and additionally kept below 3 MB.'};
 fs.writeFileSync(path.join(archive,base+'-verification.json'),JSON.stringify(report,null,2),{flag:'wx'});
 console.log(JSON.stringify(report,null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});


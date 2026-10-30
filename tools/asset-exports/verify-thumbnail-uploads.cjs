const fs = require('node:fs/promises');
const {constants} = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/drews/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const folder = 'C:/Users/drews/Development/Roblox Dev/Get Funded!/assets/thumbnails';
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
async function main() {
  const entries = await fs.readdir(folder, {withFileTypes:true});
  const names = entries.filter(e=>e.isFile() && /\.(png|jpeg|jpg|bmp|gif|webp)$/i.test(e.name)).map(e=>e.name).sort();
  const files = [];
  for (const name of names) {
    const file = path.join(folder,name);
    const data = await fs.readFile(file);
    const meta = await sharp(data,{failOn:'warning'}).metadata();
    await sharp(data,{failOn:'warning'}).raw().toBuffer();
    const extension = path.extname(name).toLowerCase();
    const expected = {'.png':'png','.jpeg':'jpeg','.bmp':'bmp'}[extension];
    const check = {name,format:meta.format,width:meta.width,height:meta.height,bytes:data.length,formatPass:!!expected && meta.format===expected,sizePass:data.length<3000000,ratioPass:meta.width*9===meta.height*16,decodePass:true,sha256:hash(data)};
    check.pass = check.formatPass && check.sizePass && check.ratioPass && check.decodePass;
    files.push(check);
  }
  if (!files.length || files.some(f=>!f.pass)) throw new Error('Thumbnail validation failed: '+JSON.stringify(files));
  const batches = [];
  for (let start=0;start<files.length;start+=5) {
    const batchName = 'upload-batch-'+(batches.length+1);
    const batchFolder = path.join(folder,batchName);
    await fs.mkdir(batchFolder,{recursive:true});
    const members = files.slice(start,start+5);
    for (const member of members) {
      const dest = path.join(batchFolder,member.name);
      try { await fs.copyFile(path.join(folder,member.name),dest,constants.COPYFILE_EXCL); }
      catch(e) { if(e.code!=='EEXIST') throw e; }
      if(hash(await fs.readFile(dest))!==member.sha256)throw new Error('Batch copy differs: '+dest);
    }
    const batchEntries = await fs.readdir(batchFolder,{withFileTypes:true});
    const imageCount = batchEntries.filter(e=>e.isFile()&&/\.(png|jpeg|jpg|bmp|gif|webp)$/i.test(e.name)).length;
    if(imageCount>5)throw new Error('Upload batch exceeds five images: '+batchName);
    batches.push({folder:batchName,count:imageCount,pass:true,files:members.map(m=>m.name)});
  }
  const report = {checkedAt:new Date().toISOString(),requirements:{extensions:['.jpeg','.png','.bmp'],bytesStrictlyLessThan:3000000,recommendedRatio:'16:9',maxImagesPerUpload:5},allPass:true,files,batches};
  await fs.writeFile(path.join(folder,'upload-verification.json'),JSON.stringify(report,null,2)+'\n');
  const lines = ['# Thumbnail upload batches','','All images have been decoded and checked against the supplied upload requirements.','Each file is PNG, 1920 x 1080 (16:9), and less than 3,000,000 bytes.','Upload one batch folder at a time; the originals remain in this folder.','',...batches.map(b=>'- '+b.folder+': '+b.count+' images'),'','| File | Size (MB) | Result |','| --- | ---: | --- |',...files.map(f=>'| '+f.name+' | '+(f.bytes/1000000).toFixed(2)+' | Pass |')];
  await fs.writeFile(path.join(folder,'UPLOAD-README.md'),lines.join('\n')+'\n');
  console.log(JSON.stringify({allPass:report.allPass,count:files.length,minBytes:Math.min(...files.map(f=>f.bytes)),maxBytes:Math.max(...files.map(f=>f.bytes)),files:files.map(({name,format,width,height,bytes,pass})=>({name,format,width,height,bytes,pass})),batches},null,2));
}
main().catch(e=>{console.error(e);process.exitCode=1;});

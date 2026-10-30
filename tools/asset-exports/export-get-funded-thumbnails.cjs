const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('C:/Users/drews/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const sourceFolder = 'C:/Users/drews/.codex/generated_images/01a0ea4e-7a65-7f90-84ea-54df3ed9428a';
const targetFolder = 'C:/Users/drews/Development/Roblox Dev/Get Funded!/assets/thumbnails';
const assets = [
  ['exec-7b007d98-7f81-461b-b75d-6d30570604dd.png', '01-the-focused-trader.png'],
  ['exec-451d8a86-deba-4072-a947-2d36d2c2c090.png', '02-the-big-win.png'],
  ['exec-80d168ac-eb41-4189-951b-bf3082f9ce35.png', '03-the-market-challenge.png'],
];
async function main() {
  const checks = [];
  const previews = [];
  for (const [source, name] of assets) {
    const output = path.join(targetFolder, name);
    if (!process.argv[2] || process.argv[2] === name) await sharp(path.join(sourceFolder, source))
      .resize(1920, 1080, { fit: 'fill', kernel: 'lanczos3' })
      .removeAlpha().toColourspace('srgb')
      .png({ compressionLevel: 9, adaptiveFiltering: true, palette: false })
      .toFile(output);
    const meta = await sharp(output).metadata();
    const {size} = await fs.stat(output);
    checks.push({ name, width: meta.width, height: meta.height, format: meta.format, space: meta.space, channels: meta.channels, palette: meta.isPalette, bytes: size, under3MB: size < 3000000 });
    previews.push({ input: await sharp(output).resize(320,180).png().toBuffer(), left: previews.length * 336, top: 0 });
  }
  await sharp({create:{width:992,height:180,channels:3,background:'#15182b'}}).composite(previews).png().toFile(path.join(__dirname,'get-funded-small-size-qa.png'));
  await fs.writeFile(path.join(targetFolder, 'export-verification.json'), JSON.stringify(checks,null,2));
  console.log(JSON.stringify(checks,null,2));
  if (checks.some(c => c.width !== 1920 || c.height !== 1080 || !c.under3MB || c.format !== 'png')) process.exitCode = 1;
}
main().catch(e => { console.error(e); process.exitCode = 1; });

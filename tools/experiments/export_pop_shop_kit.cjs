const path=require('node:path');
const fs=require('node:fs/promises');
const {pathToFileURL}=require('node:url');
const deps='C:/Users/drews/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp=require(path.join(deps,'sharp'));
const {chromium}=require(path.join(deps,'playwright'));
const root=path.resolve(__dirname,'../../assets/ui-kits/Collections/04 - Pop Shop');

(async()=>{
  const names=(await fs.readdir(path.join(root,'assets/svg'))).filter(n=>n.endsWith('.svg'));
  for(const name of names){
    const input=path.join(root,'assets/svg',name);
    const isIcon=!name.startsWith('card-')&&!name.startsWith('button-')&&!['panel.svg','currency-chip.svg'].includes(name);
    const metadata=await sharp(input).metadata();
    await sharp(input,{density:192}).resize({width:isIcon?512:metadata.width*2}).png().toFile(path.join(root,'assets/png',name.replace('.svg','.png')));
  }
  const icons=JSON.parse(await fs.readFile(path.join(root,'icons.json'),'utf8'));
  const atlas={image:'icons-atlas.png',width:2048,height:2048,cellSize:512,icons:{}};
  const layers=[];
  for(const [i,icon]of icons.entries()){
    const x=i%4*512,y=Math.floor(i/4)*512;
    layers.push({input:path.join(root,icon.png),left:x,top:y});atlas.icons[icon.name]={x,y,width:512,height:512};
  }
  await sharp({create:{width:2048,height:2048,channels:4,background:'#00000000'}}).composite(layers).png().toFile(path.join(root,'assets/icons-atlas.png'));
  await fs.writeFile(path.join(root,'assets/icons-atlas.json'),JSON.stringify(atlas,null,2));
  const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
  const page=await browser.newPage({viewport:{width:1600,height:1100},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.join(root,'index.html')).href);await page.evaluate(()=>document.fonts.ready);
  await page.locator('.icon-tile').last().scrollIntoViewIfNeeded();await page.evaluate(()=>scrollTo(0,0));
  await page.screenshot({path:path.join(root,'00-kit-board.png'),fullPage:true});
  await page.locator('.game-stage').screenshot({path:path.join(root,'01-shop-preview.png')});
  const checks=[];
  async function check(name,fn){try{await fn();checks.push({name,passed:true})}catch(e){checks.push({name,passed:false,error:e.message})}}
  await check('27 SVG/PNG asset pairs',async()=>{if(names.length!==27)throw Error('Unexpected asset count');for(const n of names){const m=await sharp(path.join(root,'assets/png',n.replace('.svg','.png'))).metadata();if(!m.hasAlpha)throw Error(n+' has no alpha channel')}});
  await check('Close and reopen shop',async()=>{await page.locator('#close-shop').click();await page.locator('#reopen').waitFor({state:'visible'});await page.locator('#reopen').click();await page.locator('#shop-panel').waitFor({state:'visible'})});
  await check('Purchase confirmation and owned state',async()=>{await page.locator('[data-product="cash"]').click();await page.locator('#confirm').waitFor({state:'visible'});await page.locator('#buy').click();if(!(await page.locator('[data-product="cash"]').innerText()).includes('OWNED'))throw Error('Missing owned state')});
  await check('Cancel leaves card unchanged',async()=>{await page.locator('[data-product="speed"]').click();await page.locator('#cancel').click();if((await page.locator('[data-product="speed"]').innerText()).includes('OWNED'))throw Error('Canceled item purchased')});
  await check('All five shop cards accessible by scrolling',async()=>{await page.locator('[data-product="luck"]').click();await page.locator('#confirm').waitFor({state:'visible'});await page.keyboard.press('Escape')});
  await check('Reward progress and motion toggle',async()=>{await page.locator('#progress').click();if(await page.locator('#progress-label').innerText()!=='4 / 5')throw Error('Bad progress');await page.locator('#motion').click();if(await page.locator('#motion').getAttribute('aria-checked')!=='false')throw Error('Bad toggle')});
  await check('Reset restores initial state',async()=>{await page.locator('#reset').click();if(await page.locator('.owned').count())throw Error('Owned state persisted');if(await page.locator('#progress-label').innerText()!=='3 / 5')throw Error('Progress persisted')});
  await check('All image files load',async()=>{const broken=await page.locator('img').evaluateAll(imgs=>imgs.filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src));if(broken.length)throw Error(broken.join(', '))});
  await page.setViewportSize({width:390,height:844});await page.evaluate(()=>scrollTo(0,0));
  await page.screenshot({path:path.join(root,'02-mobile-preview.png'),fullPage:true});
  await page.locator('.game-stage').screenshot({path:path.join(root,'03-mobile-shop.png')});
  await check('Mobile has no horizontal overflow',async()=>{if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth))throw Error('Horizontal overflow')});
  await check('Mobile sidebar receives pointer input',async()=>{await page.locator('[data-action="potion"]').click({timeout:3000});if(!(await page.locator('#toast').innerText()).includes('Boosts'))throw Error('Sidebar covered')});
  await check('Mobile purchase flow',async()=>{await page.locator('[data-product="rebirth"]').click();await page.locator('#buy').click();if(!(await page.locator('[data-product="rebirth"]').innerText()).includes('OWNED'))throw Error('Missing owned state')});
  await check('No JavaScript errors',async()=>{if(errors.length)throw Error(errors.join('\n'))});
  await fs.writeFile(path.join(root,'validation-results.json'),JSON.stringify({checks,errors},null,2));
  console.log(JSON.stringify(checks,null,2));await browser.close();
  if(checks.some(c=>!c.passed))process.exitCode=1;
})().catch(e=>{console.error(e);process.exitCode=1});

const path=require('node:path'),fs=require('node:fs/promises'),{pathToFileURL}=require('node:url');
const deps='C:/Users/drews/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp=require(path.join(deps,'sharp')),{chromium}=require(path.join(deps,'playwright'));
const root=path.resolve(__dirname,'../../../assets/ui-kits/Collections/06 - Polished Stats Pieces');
const assert=(ok,msg)=>{if(!ok)throw Error(msg)};
(async()=>{
 const manifest=JSON.parse(await fs.readFile(path.join(root,'assets.json'),'utf8'));
 for(const a of manifest)await sharp(path.join(root,a.svg),{density:192}).resize(a.width,a.height).png().toFile(path.join(root,a.png));
 const icons=manifest.filter(a=>a.kind==='icon'),atlas={image:'icons-atlas.png',width:1024,height:1024,icons:{}},layers=[];
 icons.forEach((a,i)=>{const x=i%4*256,y=Math.floor(i/4)*256;atlas.icons[a.name]={x,y,width:256,height:256};layers.push({input:path.join(root,a.png),left:x,top:y})});
 await sharp({create:{width:1024,height:1024,channels:4,background:'#00000000'}}).composite(layers).png().toFile(path.join(root,'assets/icons-atlas.png'));
 await fs.writeFile(path.join(root,'assets/icons-atlas.json'),JSON.stringify(atlas,null,2));
 const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 const page=await browser.newPage({viewport:{width:1672,height:1100},deviceScaleFactor:1});const errors=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('requestfailed',r=>errors.push(r.url()));
 await page.goto(pathToFileURL(path.join(root,'index.html')).href);await page.evaluate(()=>document.fonts.ready);
 await page.locator('.stage-host').screenshot({path:path.join(root,'01-assembled.png')});
 await page.locator('#component-board').screenshot({path:path.join(root,'02-components.png')});
 await page.locator('.assets-section').screenshot({path:path.join(root,'04-artwork.png')});
 const checks=[];
 async function check(name,fn){try{await fn();checks.push({name,passed:true})}catch(e){checks.push({name,passed:false,error:e.message})}}
 const gui=n=>page.locator('#stage [data-name="'+n+'"]');
 await check('Original aggregate and six metric labels',async()=>{
  for(const [k,v]of Object.entries({TotalValue:'-$56,808.75',TradeValue:'29.27%',AverageValue:'0.45',FactorValue:'0.18',DayValue:'—',BestValue:'—'}))assert(await gui(k).innerText()===v,k);
 });
 await check('Account dropdown opens and exposes four options',async()=>{
  await gui('FundedDropdown').click();assert(await page.getByRole('option').count()===4,'Option count');
  await page.locator('.stage-host').screenshot({path:path.join(root,'03-dropdown-open.png')});
 });
 await check('Keyboard selection changes scope and matching stats',async()=>{
  await page.keyboard.press('ArrowDown');await page.keyboard.press('Enter');
  assert(await gui('FundedDropdownLabel').innerText()==='$5K accounts','Selection missing');
  assert(await gui('TotalValue').innerText()!=='-$56,808.75','Stats not updated');assert(await gui('FundedDropdown').getAttribute('aria-expanded')==='false','Menu did not close');
 });
 await check('Scope dropdown has independent current and dated modes',async()=>{
  await gui('ScopeDropdown').click();await page.getByRole('option',{name:'Usable accounts',exact:true}).click();
  assert((await gui('ScopeSummary').innerText()).startsWith('1 attempts · 0 blown'),'Current aggregate mismatch');
  await gui('DatedButton').click();assert(await gui('ScopeDropdownLabel').innerText()==='Dated history','Dated mode absent');
  assert(await gui('DayValue').innerText()!=='—','Daily metric unavailable');
 });
 await check('Escape closes dropdown and restores trigger focus',async()=>{
  await gui('FundedDropdown').click();await page.keyboard.press('Escape');
  assert(await page.locator('.dropdown-popup').count()===0,'Menu left open');assert(await gui('FundedDropdown').evaluate(e=>e===document.activeElement),'Focus not restored');
 });
 await check('Help opens and closes',async()=>{await gui('FactorHelp').click();assert(await page.locator('#help').isVisible(),'Missing help');await page.keyboard.press('Escape');assert(!await page.locator('#help').isVisible(),'Escape failed')});
 await page.locator('#reset').click();
 await check('Reset restores original full scope',async()=>{assert(await gui('TotalValue').innerText()==='-$56,808.75','Net');assert(await gui('FundedDropdownLabel').innerText()==='All funded accounts','Account');assert(await gui('ScopeDropdownLabel').innerText()==='Lifetime · all attempts','Period')});
 await check('31 separate transparent assets with valid slice rectangles',async()=>{
  assert(manifest.length===31,'Wrong count');
  for(const a of manifest){
   const m=await sharp(path.join(root,a.png)).metadata(),stats=await sharp(path.join(root,a.png)).stats();
   assert(m.width===a.width&&m.height===a.height&&m.hasAlpha,'Dimensions/alpha '+a.name);
   assert(stats.channels[3].min===0,'No transparent pixels '+a.name);
   if(a.sliceCenter){const [l,t,r,b]=a.sliceCenter;assert(l>=0&&t>=0&&r>l&&b>t&&r<=a.width&&b<=a.height,'Slice rect '+a.name)}
  }
 });
 await check('Every image loads locally',async()=>{const broken=await page.locator('img').evaluateAll(xs=>xs.filter(x=>!x.complete||!x.naturalWidth).map(x=>x.src));assert(!broken.length,broken.join('\n'))});
 await check('Assembled labels stay inside the reference canvas',async()=>{
  const bad=await page.locator('#stage .label').evaluateAll(xs=>xs.filter(x=>x.scrollWidth>x.clientWidth+2||x.scrollHeight>x.clientHeight+2).map(x=>x.dataset.name+': '+x.textContent));
  assert(!bad.length,bad.join('\n'));
 });
 await check('Catalog scales to phone without document overflow',async()=>{await page.setViewportSize({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Document overflow')});
 await check('No JavaScript errors',async()=>assert(!errors.length,errors.join('\n')));
 await fs.writeFile(path.join(root,'validation-results.json'),JSON.stringify({checks,errors,scope:'Browser example, asset exports, dropdown interactions and layout checks.'},null,2));
 console.log(JSON.stringify(checks,null,2));await browser.close();if(checks.some(c=>!c.passed))process.exitCode=1;
})().catch(e=>{console.error(e);process.exitCode=1});


const path=require('node:path');
const fs=require('node:fs/promises');
const {pathToFileURL}=require('node:url');
const deps='C:/Users/drews/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp=require(path.join(deps,'sharp'));
const {chromium}=require(path.join(deps,'playwright'));
const root=path.resolve(__dirname,'../../../assets/ui-kits/Collections/05 - Stats Collection');
function luminance(hex){const c=hex.slice(1).match(/../g).map(x=>parseInt(x,16)/255).map(x=>x<=.04045?x/12.92:((x+.055)/1.055)**2.4);return c[0]*.2126+c[1]*.7152+c[2]*.0722}
function contrast(a,b){const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05)}
function assert(ok,msg){if(!ok)throw Error(msg)}
(async()=>{
 const themes=JSON.parse(await fs.readFile(path.join(root,'themes.json'),'utf8'));
 const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 let failed=false;
 for(const theme of themes){
  const dir=path.join(root,theme.folder),manifest=JSON.parse(await fs.readFile(path.join(dir,'assets.json'),'utf8'));
  for(const asset of manifest) await sharp(path.join(dir,asset.svg),{density:192}).resize(asset.size[0],asset.size[1]).png().toFile(path.join(dir,asset.png));
  const atlas={image:'icons-atlas.png',width:1024,height:1024,cellSize:256,icons:{}},layers=[];
  manifest.filter(a=>a.kind==='icon').forEach((a,i)=>{const x=i%4*256,y=Math.floor(i/4)*256;atlas.icons[a.name]={x,y,width:256,height:256};layers.push({input:path.join(dir,a.png),left:x,top:y})});
  await sharp({create:{width:1024,height:1024,channels:4,background:'#00000000'}}).composite(layers).png().toFile(path.join(dir,'assets/icons-atlas.png'));
  await fs.writeFile(path.join(dir,'assets/icons-atlas.json'),JSON.stringify(atlas,null,2));
  const page=await browser.newPage({viewport:{width:1600,height:1150},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('requestfailed',r=>errors.push(r.url()+' '+r.failure()?.errorText));
  await page.goto(pathToFileURL(path.join(dir,'index.html')).href);await page.evaluate(()=>document.fonts.ready);
  await page.locator('.app').screenshot({path:path.join(dir,'01-desktop.png')});
  await page.locator('.components').screenshot({path:path.join(dir,'03-components.png')});
  const checks=[];
  async function check(name,fn){try{await fn();checks.push({name,passed:true})}catch(e){checks.push({name,passed:false,error:e.message});failed=true}}
  const val=id=>page.locator('[data-value="'+id+'"]').innerText();
  await check('All six original aggregate values',async()=>{assert(await page.locator('.metric').count()===6,'Wrong card count');for(const [k,v] of Object.entries({total:'-$56,808.75',trade:'29.27%',average:'0.45',factor:'0.18',day:'—',best:'—'}))assert(await val(k)===v,k+' was '+await val(k))});
  await check('Tier and usable-account filters use matching fills',async()=>{
   await page.locator('[data-tier="5K"]').click();
   const expected=await page.evaluate(()=>window.STATS_FIXTURE.filter(r=>r.tier==='5K').reduce((s,r)=>s+r.pnl,0));
   assert(await val('total')=== (expected<0?'-':'')+'$'+Math.abs(expected).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2}),'Tier aggregate mismatch');
   await page.locator('#period').selectOption('Current');assert((await page.locator('#scope-summary').innerText()).includes('1 attempts · 0 blown'),'Usable account scope mismatch');
   await page.locator('[data-reset]').click();
  });
  await check('Dated scope recomputes every metric consistently',async()=>{
   await page.locator('[data-dated]').click();
   assert(await page.locator('#period').inputValue()==='Dated','Period not updated');
   const expected=await page.evaluate(()=>{const r=window.STATS_FIXTURE.filter(r=>r.date);return{net:r.reduce((s,r)=>s+r.pnl,0),wins:r.filter(r=>r.pnl>0).length,count:r.length}});
   assert(await val('total')===(expected.net<0?'-':'')+'$'+Math.abs(expected.net).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2}),'Dated net incorrect');
   assert(await val('trade')===(expected.wins/expected.count*100).toFixed(2)+'%','Dated trade rate incorrect');
   assert(await val('day')!=='—','Dated day rate missing');assert(await val('best')==='—','Negative total must not have best-day share');
   await page.locator('[data-reset]').click();
  });
  await check('Partial history retains net and hides unsupported ratios',async()=>{await page.locator('#scenario').selectOption('partial');assert(await val('total')==='-$56,808.75','Net lost');for(const k of ['trade','average','factor'])assert(await val(k)==='—','Unsupported '+k);await page.locator('[data-reset]').click()});
  await check('Infinity and zero denominators are distinct',async()=>{
   await page.locator('#scenario').selectOption('no-loss');assert(await val('average')==='∞'&&await val('factor')==='∞','No-loss infinity absent');
   await page.locator('#scenario').selectOption('even');assert(await val('average')==='—'&&await val('factor')==='—','Zero denominators misrepresented');
   assert(await val('trade')==='0.00%'&&await val('day')==='0.00%','Break-even denominator incorrect');
   await page.locator('[data-reset]').click();
  });
  await check('Profitable-day example shows meaningful daily stats',async()=>{await page.locator('#scenario').selectOption('positive');assert(await val('best')==='50.00%','Best day incorrect');assert(await val('day')==='100.00%','Daily rate incorrect');await page.locator('[data-reset]').click()});
  await check('Loading, empty and retryable error states',async()=>{for(const [s,title] of [['loading','Loading your stats'],['empty','No closed trades yet'],['error','Stats unavailable']]){await page.locator('#scenario').selectOption(s);assert(await page.locator('.state-card h2').innerText()===title,'Wrong '+s+' state')}await page.locator('[data-retry]').click();assert(await val('total')==='-$56,808.75','Retry did not restore')});
  await check('Metric help keyboard dismissal restores focus',async()=>{await page.locator('[data-help="best"]').click();assert(await page.locator('#help-dialog').isVisible(),'Help missing');await page.keyboard.press('Escape');assert(!await page.locator('#help-dialog').isVisible(),'Escape failed');assert(await page.locator('[data-help="best"]').evaluate(e=>e===document.activeElement),'Focus not restored')});
  await check('Reduced motion control changes preview behavior',async()=>{await page.locator('#motion').check();assert(await page.locator('body').evaluate(e=>e.classList.contains('no-motion')),'Motion preference ignored');await page.locator('#motion').uncheck()});
  await check('No broken local assets',async()=>{const broken=await page.locator('img').evaluateAll(imgs=>imgs.filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src));assert(!broken.length,broken.join(', '))});
  await check('All 25 transparent exports have correct dimensions',async()=>{assert(manifest.length===25,'Wrong asset count');for(const asset of manifest){const m=await sharp(path.join(dir,asset.png)).metadata();assert(m.width===asset.size[0]&&m.height===asset.size[1]&&m.hasAlpha,'Bad PNG '+asset.name)}});
  await check('Normal data text meets 4.5:1 contrast on cards',async()=>{for(const k of ['text','muted','gain','loss'])assert(contrast(theme[k],theme.card)>=4.5,k+' contrast '+contrast(theme[k],theme.card));assert(contrast('#ffffff',theme.accent)>=4.5,'Selected label contrast')});
  await check('Responsive layouts have no document overflow or clipped values',async()=>{
   for(const width of [1600,1024,768,390]){
    await page.setViewportSize({width,height:1000});await page.evaluate(()=>scrollTo(0,0));
    const detail=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>innerWidth,
     clipped:[...document.querySelectorAll('.metric .value,.metric .breakdown strong,.metric h3')].filter(e=>e.scrollWidth>e.clientWidth+1).map(e=>e.textContent)}));
    assert(!detail.overflow,'Horizontal overflow at '+width);assert(!detail.clipped.length,'Clipped at '+width+': '+detail.clipped.join(','));
   }
  });
  await page.setViewportSize({width:390,height:844});await page.evaluate(()=>scrollTo(0,0));
  await page.locator('.app').screenshot({path:path.join(dir,'02-mobile.png')});
  await check('Phone controls and help remain operable',async()=>{await page.locator('[data-tier="10K"]').click();assert(await page.locator('[data-tier="10K"]').getAttribute('aria-pressed')==='true','Tier not selected');await page.locator('[data-help="trade"]').click();assert(await page.locator('#help-dialog').isVisible(),'Help absent');await page.locator('[data-close]').click();await page.locator('[data-reset]').click()});
  await check('No browser JavaScript or local resource errors',async()=>assert(!errors.length,errors.join('\n')));
  await fs.writeFile(path.join(dir,'validation-results.json'),JSON.stringify({theme:theme.name,checks,errors,contrast:Object.fromEntries(['text','muted','gain','loss'].map(k=>[k,Number(contrast(theme[k],theme.card).toFixed(2))]))},null,2));
  console.log(JSON.stringify({theme:theme.name,passed:checks.filter(c=>c.passed).length,failed:checks.filter(c=>!c.passed)}));
  await page.close();
 }
 await browser.close();
 const panels=[];
 for(let i=0;i<themes.length;i++){
  const label=Buffer.from('<svg width="1200" height="78"><rect width="1200" height="78" fill="#0b1220"/><text x="24" y="48" fill="#f1f5fc" font-size="28" font-family="Segoe UI">'+themes[i].id+' / '+themes[i].name+'</text></svg>');
  const preview=await sharp(path.join(root,themes[i].folder,'01-desktop.png')).resize(1200,638,{fit:'contain',background:'#0b1220'}).png().toBuffer();
  panels.push({input:label,left:0,top:i*740},{input:preview,left:0,top:i*740+78});
 }
 await sharp({create:{width:1200,height:2220,channels:4,background:'#0b1220'}}).composite(panels).png().toFile(path.join(root,'00-comparison.png'));
 if(failed)process.exitCode=1;
})().catch(e=>{console.error(e);process.exitCode=1});


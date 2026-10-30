const products=[
  {id:'cash',title:'X2 CASH',description:'Double the money you earn<br>per second!',price:99,color:'#52e83e'},
  {id:'rebirth',title:'X2 REBIRTH',description:'Double the rebirths you earn<br>each time!',price:99,color:'#ff505f'},
  {id:'speed',title:'X2 SPEED',description:'Double your base speed!',price:49,color:'#60f1e9'},
  {id:'time',title:'X2 TIME',description:'Double your overall time!',price:99,color:'#ffe04b'},
  {id:'luck',title:'X2 LUCK',description:'A little extra luck<br>on every adventure!',price:149,color:'#8aef43'}
];
const robux='<svg class="robux" viewBox="0 0 28 28" aria-hidden="true"><path d="m14 2 10 6v12l-10 6-10-6V8Z" fill="white" stroke="#171436" stroke-width="2.8"/><path d="m14 8 5 3v6l-5 3-5-3v-6Z" fill="#989ac2" stroke="#171436" stroke-width="2"/></svg>';
const cards=document.querySelector('#shop-cards');
for(const product of products){
  const card=document.createElement('article');card.className='upgrade-card';card.style.setProperty('--card',product.color);
  card.innerHTML=`<img class="upgrade-art" src="assets/svg/${product.id}.svg" alt=""><div class="upgrade-copy"><h4>${product.title}</h4><p>${product.description}</p></div><button class="price-button" data-product="${product.id}" aria-label="Preview ${product.title} purchase for ${product.price} Robux">${robux}${product.price}</button>`;
  cards.append(card);
}
const iconNames=['shop','potion','wheel','pet','codes','settings','rebirth','gift','upgrade','boost','cash','speed','time','luck','gem','coin'];
for(const name of iconNames){
  const tile=document.createElement('article');tile.className='icon-tile';
  tile.innerHTML=`<img src="assets/svg/${name}.svg" alt="${name} icon" loading="lazy"><strong>${name[0].toUpperCase()+name.slice(1)}</strong><div class="icon-links"><a href="assets/svg/${name}.svg" download aria-label="Download ${name} SVG">SVG ↓</a><a href="assets/png/${name}.png" download aria-label="Download ${name} PNG">PNG ↓</a></div>`;
  document.querySelector('#icon-grid').append(tile);
}
for(const [name,color] of [['Ink','#171436'],['Cherry','#f33443'],['Lemon','#ffda2c'],['Lime','#52e83e'],['Aqua','#60f1e9'],['Paper','#fffef8']]){
  const swatch=document.createElement('div');swatch.className='swatch';swatch.innerHTML=`<div style="background:${color}"></div><b>${name}</b><small>${color.toUpperCase()}</small>`;document.querySelector('#swatches').append(swatch);
}
const panel=document.querySelector('#shop-panel'),reopen=document.querySelector('#reopen'),confirm=document.querySelector('#confirm'),toast=document.querySelector('#toast');
let toastTimer,pending=null,returnFocus=null,progress=3;
function notify(message){clearTimeout(toastTimer);toast.textContent=message;toast.hidden=false;toastTimer=setTimeout(()=>toast.hidden=true,3200)}
function setShop(open){panel.hidden=!open;reopen.hidden=open;if(open)document.querySelector('#close-shop').focus();else reopen.focus()}
document.querySelector('#close-shop').addEventListener('click',()=>setShop(false));
reopen.addEventListener('click',()=>setShop(true));
document.querySelectorAll('.icon-button').forEach(button=>button.addEventListener('click',()=>{
  document.querySelectorAll('.icon-button').forEach(other=>other.classList.remove('active'));button.classList.add('active');
  const action=button.dataset.action;
  if(action==='shop'){setShop(true);return}
  const messages={potion:'Boosts icon selected — ready for your boost menu.',wheel:'Daily spin icon selected — 15:00 timer sample.',pet:'Pets icon selected — ready for your pet inventory.',codes:'Codes icon selected — ready for your redeem screen.',settings:'Settings icon selected — try the animation toggle below.',rebirth:'Rebirth icon selected — ready for your progression menu.',gift:'Rewards icon selected — try the daily reward bar below.',upgrade:'Upgrades icon selected — ready for your upgrade menu.'};
  notify(messages[action]);
}));
cards.addEventListener('click',event=>{
  const button=event.target.closest('[data-product]');if(!button||button.classList.contains('owned'))return;
  pending=products.find(p=>p.id===button.dataset.product);returnFocus=button;
  document.querySelector('#confirm-title').textContent=`UNLOCK ${pending.title}?`;
  document.querySelector('#confirm-icon').src=`assets/svg/${pending.id}.svg`;
  document.querySelector('#buy').textContent=`UNLOCK · ${pending.price}`;
  confirm.hidden=false;setBackgroundInert(true);document.querySelector('#cancel').focus();
});
function setBackgroundInert(value){for(const child of document.querySelector('#game-stage').children){if(child!==confirm)child.inert=value}for(const element of document.querySelectorAll('.topbar,.intro,.section-line,.section-footnote,.components,.icon-section,.foundations,footer'))element.inert=value}
function dismiss(){confirm.hidden=true;setBackgroundInert(false);pending=null;returnFocus?.focus()}
document.querySelector('#cancel').onclick=dismiss;document.querySelector('#cancel-x').onclick=dismiss;
document.querySelector('#buy').onclick=()=>{if(!pending)return;const title=pending.title;returnFocus.innerHTML='✓ OWNED';returnFocus.classList.add('owned');returnFocus.setAttribute('aria-label',`${title} owned`);returnFocus.setAttribute('aria-disabled','true');dismiss();notify(`${title} unlocked! Purchase state previewed.`)};
confirm.addEventListener('click',event=>{if(event.target===confirm)dismiss()});
document.addEventListener('keydown',event=>{
  if(!confirm.hidden){
    if(event.key==='Escape'){event.preventDefault();dismiss()}
    if(event.key==='Tab'){const focusable=[...confirm.querySelectorAll('button')];const first=focusable[0],last=focusable.at(-1);if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus()}else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus()}}
  }else if(event.key==='Escape'&&!panel.hidden)setShop(false);
});
function updateProgress(){document.querySelector('#progress-label').textContent=`${progress} / 5`;document.querySelector('#progress-fill').style.width=`${progress*20}%`;document.querySelector('#progress').setAttribute('aria-label',`Daily reward progress ${progress} of 5; activate to advance`)}
document.querySelector('#progress').onclick=()=>{progress=progress===5?0:progress+1;updateProgress()};updateProgress();
const motion=document.querySelector('#motion');
function setMotion(enabled){motion.setAttribute('aria-checked',String(enabled));document.body.classList.toggle('no-motion',!enabled)}
setMotion(!matchMedia('(prefers-reduced-motion: reduce)').matches);
motion.onclick=()=>setMotion(motion.getAttribute('aria-checked')!=='true');
document.querySelectorAll('.sample-button').forEach(button=>button.onclick=()=>{button.textContent='NICE!';setTimeout(()=>button.textContent=button.classList.contains('success')?'✓ OWNED':'BUY NOW',750)});
document.querySelector('#reset').onclick=()=>{for(const button of cards.querySelectorAll('[data-product]')){const product=products.find(p=>p.id===button.dataset.product);button.innerHTML=robux+product.price;button.classList.remove('owned');button.removeAttribute('aria-disabled');button.setAttribute('aria-label',`Preview ${product.title} purchase for ${product.price} Robux`)}cards.scrollTop=0;panel.hidden=false;reopen.hidden=true;toast.hidden=true;clearTimeout(toastTimer);progress=3;updateProgress();setMotion(!matchMedia('(prefers-reduced-motion: reduce)').matches);document.querySelectorAll('.icon-button').forEach(button=>button.classList.toggle('active',button.dataset.action==='shop'))};

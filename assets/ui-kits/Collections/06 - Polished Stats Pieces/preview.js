'use strict';
const spec=window.PIECES,stage=document.getElementById('stage');
function render(n){
 const el=document.createElement(n.kind==='TextButton'?'button':'div');el.className='gui'+(n.kind==='TextLabel'?' label':n.kind==='TextButton'?' button':'');el.dataset.name=n.name;
 Object.assign(el.style,{left:n.x+'px',top:n.y+'px',width:n.w+'px',height:n.h+'px',borderRadius:(n.radius||0)+'px',background:n.top?'linear-gradient('+n.top+','+n.bottom+')':n.bg||'transparent',boxShadow:n.edge?'inset 0 0 0 '+(n.stroke||1)+'px '+n.edge:'none',overflow:n.clip?'hidden':'visible'});
 if(n.rotation)el.style.transform='rotate('+n.rotation+'deg)';
 if(n.transparency)el.style.opacity=1-n.transparency;
 if(n.kind==='TextLabel'||n.kind==='TextButton'&&n.text){
  el.textContent=n.text||'';Object.assign(el.style,{fontFamily:n.font==='body'?'"Segoe UI",Arial,sans-serif':'Display,Arial,sans-serif',fontSize:(n.size||20)+'px',color:n.color||spec.colors.text,textAlign:n.align||'left',justifyContent:n.align==='right'?'flex-end':n.align==='center'?'center':'flex-start'});
 }
 if(n.kind==='ImageLabel'){const img=document.createElement('img');img.src='assets/svg/icon-'+n.asset+'.svg';img.alt='';el.append(img)}
 (n.children||[]).forEach(c=>el.append(render(c)));
 if(n.kind==='TextButton'){el.setAttribute('aria-label',n.name.replace(/([a-z])([A-Z])/g,'$1 $2'));el.type='button'}
 return el;
}
const scene=render(spec.templates.Assembled);stage.append(scene);
const $=name=>scene.querySelector('[data-name="'+name+'"]');
const text=(name,v)=>{$(name).textContent=v};
const money=v=>v==null?'—':(v<0?'-':'')+'$'+Math.abs(v).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
const percent=v=>v==null?'—':(v*100).toFixed(2)+'%';
const ratio=(v,infinite)=>infinite?'∞':v==null?'—':v.toFixed(2);
let currentScope='All',currentPeriod='Life',popup,trigger;
const scopes=[['All','All funded accounts'],['5K','$5K accounts'],['10K','$10K accounts'],['25K','$25K accounts']];
const periods=[['Life','Lifetime · all attempts'],['Current','Usable accounts'],['Dated','Dated history']];
function close(){if(popup)popup.remove();popup=null;if(trigger){trigger.setAttribute('aria-expanded','false');trigger.focus()}}
function bar(name,values){const el=$(name),total=values.reduce((s,n)=>s+n,0);el.replaceChildren();let x=0;values.forEach((v,i)=>{if(v>0&&total){const part=document.createElement('div');Object.assign(part.style,{position:'absolute',left:x/total*100+'%',width:v/total*100+'%',height:'100%',borderRadius:'11px',background:['linear-gradient(#29f9ba,#0ad59e)','linear-gradient(#ff85b9,#f65096)','#85a8db'][i]});el.append(part);x+=v}})}
function update(){
 const a=window.FIXTURES[currentScope][currentPeriod];
 text('FundedDropdownLabel',scopes.find(r=>r[0]===currentScope)[1]);text('ScopeDropdownLabel',periods.find(r=>r[0]===currentPeriod)[1]);
 text('TotalValue',money(a.Net));$('TotalValue').style.color=a.Net<0?spec.colors.loss:a.Net>0?spec.colors.gain:spec.colors.text;
 text('TradeValue',percent(a.WinRate));text('AverageValue',ratio(a.WinLossRatio,a.NoLosses));text('FactorValue',ratio(a.ProfitFactor,a.NoLosses));
 text('DayValue',percent(a.DayWinRate));text('BestValue',percent(a.BestDayShare));text('TradeCaption',a.Wins+' wins / '+a.Trades+' trades');
 text('AverageDetail0',money(a.AvgWin));text('AverageDetail1',a.AvgLoss==null?'—':money(-a.AvgLoss));text('FactorDetail0',money(a.Gains));text('FactorDetail1',money(-a.Loss));
 text('AttemptsLabel',a.Attempts+' attempts');text('ClosedTradesLabel',a.Trades+' closed trades');
 text('ScopeSummary',a.Attempts+' attempts · '+a.Blown+' blown · '+(currentPeriod==='Life'?'Includes restarts':currentPeriod==='Dated'?'Dated trades only':'Usable accounts only'));
 text('CoverageCopy',!a.DailyComplete?'Some trades have no dates.\nDaily stats need dated history.':a.Net<=0?'UTC days. Best-day share needs\npositive total net profit.':'All six stats use the same scope.\nTrading days use UTC.');
 bar('TradeBar',[a.Wins,a.Losses,a.Even]);bar('AverageBar',[a.AvgWin||0,a.AvgLoss||0]);bar('FactorBar',[a.Gains,a.Loss]);
}
function dropdown(name,items,scope){
 const button=$(name);button.setAttribute('aria-haspopup','listbox');button.setAttribute('aria-expanded','false');
 button.addEventListener('click',()=>{
  if(popup&&trigger===button){close();return}
  close();trigger=button;button.setAttribute('aria-expanded','true');
  popup=document.createElement('div');popup.className='dropdown-popup';popup.setAttribute('role','listbox');popup.setAttribute('aria-label',scope?'Funded accounts':'Stats scope');
  const n=spec.templates[scope?'FundedDropdown':'ScopeDropdown'],place=spec.templates.Assembled.children.find(c=>c.name===name);
  Object.assign(popup.style,{left:place.x+'px',top:(place.y+place.h+8)+'px',width:n.w+'px'});
  items.forEach(([key,label])=>{const row=document.createElement('button');row.textContent=label;row.dataset.key=key;row.setAttribute('role','option');row.setAttribute('aria-selected',String(key===(scope?currentScope:currentPeriod)));row.addEventListener('click',()=>{if(scope)currentScope=key;else currentPeriod=key;close();update()});popup.append(row)});
  stage.append(popup);popup.querySelector('[aria-selected=true]').focus();
 });
}
dropdown('FundedDropdown',scopes,true);dropdown('ScopeDropdown',periods,false);
document.addEventListener('click',e=>{if(popup&&!popup.contains(e.target)&&!trigger.contains(e.target))close()});
document.addEventListener('keydown',e=>{
 if(!popup)return;
 if(e.key==='Escape'){e.preventDefault();close()}
 if(['ArrowDown','ArrowUp','Home','End'].includes(e.key)){
  e.preventDefault();const items=[...popup.querySelectorAll('button')],i=items.indexOf(document.activeElement);
  items[e.key==='Home'?0:e.key==='End'?items.length-1:(i+(e.key==='ArrowDown'?1:-1)+items.length)%items.length].focus();
 }
});
$('DatedButton').addEventListener('click',()=>{currentPeriod='Dated';update()});
const dialog=document.getElementById('help');
function showHelp(title,body){dialog.querySelector('h2').textContent=title;dialog.querySelector('p').textContent=body;dialog.showModal()}
const explanations={Total:['Total P&L','Net realized P&L from closed trades. Open positions and starting capital are excluded.'],
Trade:['Trade win rate','Winning closing fills divided by all closing fills. Break-even fills remain in the denominator.'],
Average:['Avg win / avg loss','Average winning P&L divided by the absolute average losing P&L. Infinity means positive gains with no losses.'],
Factor:['Profit factor','Gross positive P&L divided by absolute gross negative P&L. The bar shows their shares of the combined magnitude.'],
Daily:['Daily stats','Daily metrics require complete calendar dates. Best-day share also requires positive total net profit. All daily calculations use UTC days.']};
Object.entries(explanations).forEach(([key,v])=>$(key+'Help').addEventListener('click',()=>showHelp(...v)));
$('AccountPicker').addEventListener('click',()=>showHelp('Active account picker','This is the separate active-account component. Connect it to your existing account switcher when integrating.'));
document.getElementById('close-help').addEventListener('click',()=>dialog.close());
document.getElementById('reset').addEventListener('click',()=>{close();currentScope='All';currentPeriod='Life';update()});
const chosen=['HeroCard','TradeCard','AverageCard','FactorCard','FundedMenuOpen','DailyStats','FundedDropdown','ScopeDropdown','InfoButton','OutcomeBar'];
const grid=document.createElement('div');grid.className='component-grid';document.getElementById('component-board').append(grid);
const mini=[];
chosen.forEach(name=>{
 const n=spec.templates[name],card=document.createElement('article');card.className='component-card'+(['HeroCard','DailyStats'].includes(name)?' wide':'');
 const heading=document.createElement('header');heading.innerHTML='<h3>'+name+'</h3><p>'+n.w+' × '+n.h+' reference pixels · editable native hierarchy</p>';card.append(heading);
 const host=document.createElement('div');host.className='mini-host';const s=document.createElement('div');s.className='mini-stage';s.style.width=n.w+'px';s.style.height=n.h+'px';s.append(render(n));host.append(s);card.append(host);grid.append(card);mini.push({host,stage:s,n});
});
window.ASSETS.forEach(a=>{
 const el=document.createElement('article');el.className='asset';el.innerHTML='<div class="picture checker"><img src="'+a.png+'" alt="'+a.name+' asset"></div><div class="info"><strong>'+a.name+'</strong><p class="dim">'+a.width+' × '+a.height+' · '+(a.kind==='surface'?'9-slice background':'transparent icon')+'</p><div class="links"><a href="'+a.png+'" download>PNG ↓</a><a href="'+a.svg+'" download>SVG ↓</a></div></div>';document.getElementById('asset-grid').append(el)
});
function resize(){const s=document.querySelector('.stage-host').clientWidth/1672;stage.style.transform='scale('+s+')';stage.parentElement.style.height=941*s+'px';mini.forEach(m=>{const s=Math.min(1,m.host.clientWidth/m.n.w);m.stage.style.transform='scale('+s+')';m.host.style.height=m.n.h*s+'px'})}
new ResizeObserver(resize).observe(document.body);update();resize();
window.PiecesPreview={update,reset:()=>{currentScope='All';currentPeriod='Life';update()},getScope:()=>[currentScope,currentPeriod]};

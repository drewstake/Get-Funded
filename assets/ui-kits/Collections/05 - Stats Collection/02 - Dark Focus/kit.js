'use strict';
// Demonstration fixtures are synthetic. Only the initial aggregate matches the supplied screenshot.
// Production should use the server aggregate adapter in roblox/StatsKit.luau.
const seed = window.STATS_FIXTURE;
const state = {tier:'All', period:'Life', scenario:'snapshot'};
const money = v => (v<0?'-':'')+'$'+Math.abs(v).toLocaleString('en-US',{minimumFractionDigits:2,maximumFractionDigits:2});
const pct = v => v==null?'—':(v*100).toFixed(2)+'%';
const ratio = v => v==null?'—':v===Infinity?'∞':v.toFixed(2);
const help = {
total:['Total P&L','Net realized profit or loss from closed trades. Open positions and starting capital are excluded. Lifetime retains previous attempts, including blown accounts.'],
trade:['Trade win rate','Winning closing fills divided by all closing fills. Break-even fills remain in the denominator. Partial closes count per closing fill, matching Trade History.'],
average:['Avg win / avg loss','Average winning P&L divided by the absolute average losing P&L. ∞ means positive wins with no losses. — means no usable denominator or an incomplete trade breakdown.'],
day:['Day win rate','Profitable UTC days divided by days with closed trades, including losing and break-even days. All accounts in the selected scope are combined by date.'],
factor:['Profit factor','Gross wins divided by absolute gross losses. ∞ means positive gains with no losses. The bar shows gross wins and gross losses as shares of their combined magnitude; it is not the numeric profit factor itself.'],
best:['Best day % of total profit','Highest daily net profit divided by total net realized profit in this scope. This can exceed 100%. It requires complete dates and positive total net profit.']
};
const icons = name => 'assets/svg/icon-'+name+'.svg';
function aggregate(rows) {
 const wins=rows.filter(r=>r.pnl>0), losses=rows.filter(r=>r.pnl<0);
 const gains=wins.reduce((s,r)=>s+r.pnl,0), loss=-losses.reduce((s,r)=>s+r.pnl,0), net=gains-loss;
 const days={};rows.filter(r=>r.date).forEach(r=>days[r.date]=(days[r.date]||0)+r.pnl);
 const daily=rows.length>0&&rows.every(r=>r.date), vals=Object.values(days);
 const avgWin=wins.length?gains/wins.length:null,avgLoss=losses.length?loss/losses.length:null;
 const noLoss=gains>0&&loss===0;
 return {net,gains,loss,trades:rows.length,wins:wins.length,losses:losses.length,even:rows.length-wins.length-losses.length,
 avgWin,avgLoss,winRate:rows.length?wins.length/rows.length:null,winLossRatio:noLoss?Infinity:avgWin!=null&&avgLoss?avgWin/avgLoss:null,
 profitFactor:noLoss?Infinity:loss?gains/loss:null,daily,dayCount:vals.length,winningDays:vals.filter(x=>x>0).length,
 dayWinRate:daily?vals.filter(x=>x>0).length/vals.length:null,bestDayShare:daily&&net>0?Math.max(...vals)/net:null,
 attempts:new Set(rows.map(r=>r.account)).size,blown:new Set(rows.filter(r=>!r.current).map(r=>r.account)).size};
}
function fixture() {
 let rows=seed;
 if(state.scenario==='positive')rows=[800,-200,600,300,-100,400].map((pnl,i)=>({pnl,account:7,tier:'5K',current:true,date:'2026-09-'+(20+Math.floor(i/2))}));
 if(state.scenario==='no-loss')rows=[600,400,500].map((pnl,i)=>({pnl,account:7,tier:'5K',current:true,date:'2026-09-'+(20+i)}));
 if(state.scenario==='even')rows=[0,0,0].map((pnl,i)=>({pnl,account:7,tier:'5K',current:true,date:'2026-09-'+(20+i)}));
 if(state.scenario==='empty')rows=[];
 return rows.filter(r=>(state.tier==='All'||r.tier===state.tier)&&(state.period!=='Current'||r.current)&&(state.period!=='Dated'||r.date));
}
function bar(win,loss,even=0) {
 const total=win+loss+even;
 if(total<=0)return '';
 return '<div class="bar" aria-hidden="true"><span class="win" style="width:'+(win/total*100)+'%"></span><span class="lose" style="width:'+(loss/total*100)+'%"></span><span class="even" style="width:'+(even/total*100)+'%"></span></div>';
}
function breakdown(a,av,b,bv) {
 return '<div class="breakdown"><div><span>'+a+'</span><strong class="gain">'+av+'</strong></div><div><span>'+b+'</span><strong class="loss">'+bv+'</strong></div></div>';
}
function metric(id,title,value,details,caption,cls='') {
 return '<article class="metric metric-'+id+'"><div class="metric-head"><h3>'+title+'</h3><button class="help" data-help="'+id+'" aria-label="About '+title+'">ⓘ</button></div><div class="value '+cls+'" data-value="'+id+'">'+value+'</div>'+details+'<p class="metric-caption">'+caption+'</p></article>';
}
function unavailable(id,title,reason) {
 return '<article class="metric metric-'+id+'"><div class="metric-head"><h3>'+title+'</h3><button class="help" data-help="'+id+'" aria-label="About '+title+'">ⓘ</button></div><div class="empty-symbol"><img src="'+icons('calendar')+'" alt=""><div class="value" data-value="'+id+'">—</div></div><p class="metric-caption">'+reason+'</p></article>';
}
function stateCard(title,body,icon,button) {
 return '<div class="state-card"><img src="'+icons(icon)+'" alt=""><h2>'+title+'</h2><p>'+body+'</p>'+(button?'<button class="primary" data-retry>'+button+'</button>':'')+'</div>';
}
function render() {
 const a=aggregate(fixture()), partial=state.scenario==='partial';
 document.querySelectorAll('[data-tier]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.tier===state.tier)));
 document.getElementById('period').value=state.period;
 document.getElementById('scope-summary').textContent=a.attempts+' attempts · '+a.blown+' blown · '+(state.period==='Life'?'Includes restarts':state.period==='Dated'?'Dated trades only · UTC days':'Current usable accounts only');
 const notice=document.getElementById('coverage');
 const note=partial?'Earlier trades have no full breakdown. Ratios are unavailable.':!a.daily?'Some trades have no dates. Daily stats need dated history.':'All six cards use the same '+(state.period==='Dated'?'dated ':'')+'trade scope. UTC days.';
 notice.querySelector('p').textContent=note;
 notice.querySelector('button').hidden=a.daily&&!partial;
 const wrap=document.getElementById('metric-content');
 if(state.scenario==='loading'){wrap.innerHTML=stateCard('Loading your stats','Fetching your saved results from the exchange.','clock',null)+'<div class="skeleton" aria-hidden="true"></div>';return}
 if(state.scenario==='error'){wrap.innerHTML=stateCard('Stats unavailable','The exchange could not be reached. Your saved results are safe.','warning','Retry');return}
 if(!a.trades){wrap.innerHTML=stateCard('No closed trades yet','Your results will appear after a trade closes in this scope. Try another account size or time scope.','stats','Reset preview');return}
 const avgDetails=partial?'':bar(a.avgWin||0,a.avgLoss||0)+breakdown('Avg win',a.avgWin==null?'—':money(a.avgWin),'Avg loss',a.avgLoss==null?'—':money(-a.avgLoss));
 const totalDetails=document.body.dataset.layout==='dark'?breakdown('Gross wins',money(a.gains),'Gross losses',money(-a.loss)):'<div class="hero-context"><div><strong>'+a.attempts+' attempts</strong>Includes selected accounts</div><div><strong>'+a.trades+' closed trades</strong>Realized results</div></div>';
 const tradeDetails=partial?'':bar(a.wins,a.losses,a.even);
 const factorDetails=partial?'':bar(a.gains,a.loss)+breakdown('Gross wins',money(a.gains),'Gross losses',money(-a.loss));
 let cards=metric('total','Total P&L',money(a.net),totalDetails,'Closed trades only',a.net<0?'loss':a.net>0?'gain':'');
 cards+=metric('trade','Trade win rate',partial?'—':pct(a.winRate),tradeDetails,partial?'Earlier breakdown unavailable':a.wins+' wins / '+a.trades+' trades'+(a.even?' · '+a.even+' even':''));
 cards+=metric('average','Avg win / avg loss',partial?'—':ratio(a.winLossRatio),avgDetails,partial?'Earlier breakdown unavailable':a.winLossRatio===Infinity?'No losing trades':'Average win ÷ absolute average loss');
 cards+=a.daily?metric('day','Day win rate',pct(a.dayWinRate),bar(a.winningDays,a.dayCount-a.winningDays),a.winningDays+' profitable / '+a.dayCount+' UTC days'):unavailable('day','Day win rate','Needs dated history');
 cards+=metric('factor','Profit factor',partial?'—':ratio(a.profitFactor),factorDetails,partial?'Earlier breakdown unavailable':a.profitFactor===Infinity?'No gross losses':'Gross wins ÷ absolute gross losses');
 cards+=a.bestDayShare!=null?metric('best','Best day % of total profit',pct(a.bestDayShare),'','Highest daily net ÷ total net profit'):unavailable('best','Best day % of total profit',a.daily?'Requires positive total net profit':'Needs dated history');
 wrap.innerHTML='<div class="metric-grid">'+cards+'</div>';
}
const dialog=document.getElementById('help-dialog');
function showDialog(title,body){dialog.querySelector('h2').textContent=title;dialog.querySelector('p').textContent=body;dialog.showModal()}
let toastTimer;
function toast(message){const el=document.getElementById('toast');el.textContent=message;el.hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>el.hidden=true,3000)}
function reset(){state.tier='All';state.period='Life';state.scenario='snapshot';document.getElementById('scenario').value='snapshot';render()}
document.addEventListener('click',e=>{
 const tier=e.target.closest('[data-tier]');if(tier){state.tier=tier.dataset.tier;render();return}
 const info=e.target.closest('[data-help]');if(info){showDialog(...help[info.dataset.help]);return}
 if(e.target.closest('[data-dated]')){state.period='Dated';state.scenario='snapshot';document.getElementById('scenario').value='snapshot';render();return}
 if(e.target.closest('[data-close]')){dialog.close();return}
 if(e.target.closest('[data-retry]')||e.target.closest('[data-reset]')){reset();return}
 const nav=e.target.closest('[data-nav]');if(nav){if(nav.dataset.nav==='Stats')toast('You are viewing Stats.');else toast(nav.dataset.nav+' navigation component · connect your game route.');return}
 if(e.target.closest('[data-account]'))showDialog('Funded account selector','Reusable account switcher. Connect this control to your active funded accounts in Roblox.');
 if(e.target.closest('[data-settings]'))showDialog('Settings','This is the settings entry component. The Reduced motion switch in the kit controls the preview transitions.');
 const demo=e.target.closest('[data-demo]');if(demo)toast(demo.dataset.demo);
});
dialog.addEventListener('click',e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close()}});
document.getElementById('period').addEventListener('change',e=>{state.period=e.target.value;render()});
document.getElementById('scenario').addEventListener('change',e=>{state.scenario=e.target.value;state.tier='All';state.period='Life';render()});
document.getElementById('motion').addEventListener('change',e=>document.body.classList.toggle('no-motion',e.target.checked));
document.getElementById('motion').checked=matchMedia('(prefers-reduced-motion: reduce)').matches;
window.StatsKitDemo={aggregate,fixture,state,render,reset};
render();
function revealActiveNavigation(){
 const nav=document.querySelector('.sidebar nav'),active=nav.querySelector('[aria-current="page"]');
 if(innerWidth<=760)nav.scrollLeft=active.offsetLeft-nav.offsetLeft-(nav.clientWidth-active.clientWidth)/2;
 else nav.scrollLeft=0;
}
addEventListener('resize',revealActiveNavigation);
requestAnimationFrame(revealActiveNavigation);

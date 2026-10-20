const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const norm = s => s.replace(/\r\n/g, '\n');
const hash = s => crypto.createHash('sha256').update(norm(s)).digest('hex');
const local = fs.readdirSync(path.join(root,'src')).filter(n=>n.endsWith('.luau')).map(file=>({file,name:file.replace(/\.(server|client)\.luau$/, '').replace(/\.luau$/, ''),className:file.endsWith('.server.luau')?'Script':file.endsWith('.client.luau')?'LocalScript':'ModuleScript',source:norm(fs.readFileSync(path.join(root,'src',file),'utf8'))}));
const server = http.createServer((req,res)=>{
  if(req.method!=='POST' || !['/compare','/verify'].includes(req.url)){res.writeHead(404);res.end();return;}
  let body='';req.on('data',c=>{body+=c;if(body.length>10000000)req.destroy();});req.on('end',()=>{try{
    const snapshot=JSON.parse(body);
    if(snapshot.PlaceId!==137759823569682)throw Error('Unexpected place');
    const records=local.map(item=>{
      const matches=snapshot.Scripts.filter(s=>s.Name===item.name && s.Class===item.className);
      if(matches.length!==1)return {file:item.file,status:'unmapped',matches:matches.map(s=>s.Path)};
      const s=matches[0];return {file:item.file,path:s.Path,status:norm(s.Source)===item.source?'match':'different',localHash:hash(item.source),studioHash:hash(s.Source)};
    });
    const report={placeId:snapshot.PlaceId,localCount:local.length,studioCount:snapshot.Scripts.length,matched:records.filter(r=>r.status==='match').length,records,studioOnly:snapshot.Scripts.filter(s=>!local.some(l=>l.name===s.Name&&l.className===s.Class)).map(s=>s.Path)};
    fs.writeFileSync(path.join(__dirname,req.url==='/compare'?'studio-before.json':'studio-after.json'),JSON.stringify(snapshot,null,2),{flag:req.url==='/compare'?'wx':'w'});
    fs.writeFileSync(path.join(__dirname,req.url==='/compare'?'comparison.json':'verification.json'),JSON.stringify(report,null,2));
    if(req.url==='/compare')fs.writeFileSync(path.join(__dirname,'local-before.json'),JSON.stringify(local,null,2));
    res.setHeader('Content-Type','application/json');res.end(JSON.stringify(report));
  }catch(e){res.writeHead(500);res.end(String(e));}});
});
server.listen(0,'127.0.0.1',()=>console.log(JSON.stringify({port:server.address().port,localCount:local.length})));

"""Deterministic staged trade edit. Does not connect to or modify the game.

Run using the bundled Codex Python (Pillow + numpy), with ../tools on sys.path.
Visual language: src/shared/TerminalUI.luau, current Studio preview, Fredoka game font.
Market: src/shared/MarketConfig.luau, BX $50/point, 0.25 tick, one contract.
"""
from pathlib import Path
from functools import lru_cache
import math, json, sys, wave, subprocess, argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
OUT = HERE.parent
sys.path.insert(0, str(OUT / 'tools'))
import imageio_ffmpeg

W, H, FPS, DURATION = 1080, 1920, 30, 16.0
GREEN = (46, 249, 160)
PINK = (255, 81, 127)
CYAN = (0, 220, 255)
WHITE = (245, 249, 255)
MUTED = (159, 210, 248)
INK = (2, 14, 39)
FONTS = Path('C:/Windows/Fonts')
GAME_FONT = next(Path('C:/Users/drews/AppData/Local/Roblox/Versions').glob('*/content/fonts/FredokaOne-Regular.ttf'))
ENTRY, MULTIPLIER, CLOSE_AT = 5825.0, 50, 12.8
# Prices are expressed as profit for one BX contract. Every displayed tick is $12.50.
KEYS = [(0,37.5),(.8,62.5),(1.6,100),(2.4,137.5),(3.2,187.5),
        (4,287.5),(4.8,400),(5.2,325),(5.6,262.5),(6.0,325),
        (6.4,400),(7.2,612.5),(8,800),(8.8,750),(9.6,950),
        (10.4,1125),(11.2,1087.5),(12,1312.5),(12.6,1500),(16,1500)]
BASE_HISTORY = [-275,-250,-312.5,-237.5,-212.5,-262.5,-225,-175,-150,-212.5,
                -162.5,-137.5,-187.5,-125,-100,-137.5,-75,-50,-100,-62.5,-25,0]
BEAT = .4

@lru_cache(None)
def font(size, kind='game'):
    return ImageFont.truetype(str(GAME_FONT if kind == 'game' else FONTS / {'bold':'arialbd.ttf','regular':'arial.ttf','mono':'consolab.ttf'}[kind]), size)

def clamp(v,a=0,b=1): return max(a,min(b,v))
def smooth(v):
    v=clamp(v); return v*v*(3-2*v)
def profit(t):
    val = np.interp(min(t,CLOSE_AT), [x for x,y in KEYS], [y for x,y in KEYS])
    wiggle = 12.5*math.sin(t*12.7)*math.sin(t*3.1) if t<12.5 else 0
    return round((val+wiggle)/12.5)*12.5
def money(v, signed=False): return ('+' if signed and v>=0 else '') + ('$' if v>=0 else '-$') + f'{abs(v):,.2f}'

def txt(im, xy, s, size, color=WHITE, kind='game', anchor='la', stroke=0):
    ImageDraw.Draw(im).text(xy,s,font=font(size,kind),fill=color,anchor=anchor,
        stroke_width=stroke,stroke_fill=INK)

def rr(im,box,fill,r=20,outline=None,width=1):
    ImageDraw.Draw(im).rounded_rectangle(tuple(int(v) for v in box),radius=r,fill=fill,outline=outline,width=width)

@lru_cache(None)
def gradient_panel(w,h,top,bottom,r,border,width):
    a=np.linspace(0,1,h)[:,None,None]
    arr=np.broadcast_to(np.array(top)[None,None,:]*(1-a)+np.array(bottom)[None,None,:]*a,(h,w,3)).astype('uint8').copy()
    layer=Image.fromarray(arr).convert('RGBA')
    mask=Image.new('L',(w,h));ImageDraw.Draw(mask).rounded_rectangle((0,0,w-1,h-1),r,fill=255)
    layer.putalpha(mask)
    if border: ImageDraw.Draw(layer).rounded_rectangle((width//2,width//2,w-1-width//2,h-1-width//2),r,outline=border,width=width)
    return layer

def panel(im,box,top,bottom,r=22,border=(27,92,196),width=2,shine=False):
    x,y,x2,y2=map(int,box)
    im.paste(gradient_panel(x2-x,y2-y,top,bottom,r,border,width),(x,y),gradient_panel(x2-x,y2-y,top,bottom,r,border,width))
    if shine:
        ImageDraw.Draw(im).line((x+20,y+10,x2-20,y+10),fill=tuple(min(255,int(c*.5+125)) for c in top),width=3)

def pill(im,box,s,selected=False,size=25):
    panel(im,box,(150,76,250) if selected else (17,52,117),(79,25,215) if selected else (3,24,66),r=13,
          border=(191,140,255) if selected else (33,93,179),width=2,shine=selected)
    txt(im,((box[0]+box[2])/2,(box[1]+box[3])/2),s,size,anchor='mm',stroke=1)

# Background is cached; all moving elements are native graphics, not generated images.
y,x=np.mgrid[0:H,0:W]
glow=np.exp(-((x-500)/750)**2-((y-830)/1000)**2)
bgarr=np.zeros((H,W,3),dtype=np.uint8)
for i,(base,amp) in enumerate([(2,6),(9,12),(25,38)]): bgarr[:,:,i]=base+glow*amp
BG=Image.fromarray(bgarr)
del bgarr,glow,x,y
bd=ImageDraw.Draw(BG)
for gy in range(0,H,84): bd.line((0,gy,W,gy),fill=(8,22,46),width=1)
for gx in range(0,W,84): bd.line((gx,0,gx,H),fill=(8,22,46),width=1)

def static_terminal():
    im=Image.new('RGBA',(W,H))
    panel(im,(60,426,962,1584),(6,37,92),(3,20,55),r=32,border=(0,112,255),width=3)
    txt(im,(92,456),'Get',36)
    txt(im,(163,456),'Funded!',36,(255,217,60))
    pill(im,(728,451,925,495),'TRADE',True,23)
    # The two cards and chart use the game's exact palette and font family.
    panel(im,(86,517,486,636),(0,183,240),(0,80,216),r=22,border=(75,229,255),width=3,shine=True)
    panel(im,(500,517,936,636),(0,214,137),(0,125,87),r=22,border=(81,255,179),width=3,shine=True)
    txt(im,(108,537),'BALANCE',22,stroke=1)
    txt(im,(522,537),'OPEN PROFIT',22,stroke=1)
    panel(im,(86,659,936,1233),(5,32,83),(3,24,64),r=24,border=(0,116,255),width=3)
    pill(im,(105,679,255,741),'BX  v',False,30)
    txt(im,(273,686),'Blox 500',27)
    txt(im,(273,722),'SIMULATED MARKET',17,MUTED,kind='bold')
    for i,label in enumerate(['1m','5m','15m','1h','1D']):
        pill(im,(106+i*110,763,204+i*110,810),label,i==0,25)
    pill(im,(782,763,914,810),'Auto',True,23)
    d=ImageDraw.Draw(im)
    for gy in range(851,1151,60): d.line((109,gy,810,gy),fill=(20,55,104),width=1)
    for gx in range(110,811,116): d.line((gx,832,gx,1152),fill=(15,43,87),width=1)
    txt(im,(458,1004),'GET FUNDED!',48,(14,49,102),anchor='mm')
    for xx,label in [(133,'00:10'),(357,'00:20'),(589,'00:30')]: txt(im,(xx,1201),label,18,MUTED,kind='mono')
    panel(im,(86,1250,936,1468),(11,46,111),(4,23,63),r=22,border=(0,111,245),width=3)
    pill(im,(105,1269,402,1316),'Open positions',True,23)
    pill(im,(417,1269,634,1316),'Orders',False,23)
    txt(im,(750,1285),'History',23,MUTED)
    panel(im,(86,1488,495,1558),(27,245,161),(0,166,111),r=17,border=(135,255,209),width=3,shine=True)
    panel(im,(511,1488,936,1558),(255,108,158),(224,38,98),r=17,border=(255,172,203),width=3,shine=True)
    txt(im,(290,1526),'↑ BUY',32,anchor='mm',stroke=1)
    txt(im,(723,1526),'↓ SELL',32,anchor='mm',stroke=1)
    return im

STATIC=static_terminal()

def draw_candle(im,xx,op,cl,hi,lo,py,width=17,active=False):
    color=GREEN if cl>=op else PINK
    d=ImageDraw.Draw(im)
    d.line((xx,py(hi),xx,py(lo)),fill=color,width=2)
    top,bot=sorted((py(op),py(cl)))
    if bot-top<3: bot=top+3
    if active:
        d.rectangle((xx-width/2-3,top-3,xx+width/2+3,bot+3),fill=tuple(int(v*.25) for v in color))
    d.rectangle((xx-width/2,top,xx+width/2,bot),fill=color)
    if bot-top>7: d.line((xx-width/2+1,top+1,xx+width/2-1,top+1),fill=(161,255,211) if cl>=op else (255,167,193),width=2)

def chart(im,t,p):
    history=BASE_HISTORY[:]
    nfull=int(min(t,12.6)/.4)
    history.extend(profit(k*.4) for k in range(1,nfull+1))
    series=history[-25:]+[p]
    peak=max(420,max(series)+180)
    floor=min(-180,min(series)-130)
    span=peak-floor
    def py(v): return 1140-(v-floor)/span*288
    d=ImageDraw.Draw(im)
    # Dollar-aware price axis: P&L stays consistent with BX's $50 point multiplier.
    for yy in range(861,1150,60):
        pv=floor+(1140-yy)/288*span
        price=round((ENTRY+pv/50)*4)/4
        txt(im,(922,yy),f'{price:,.2f}',18,MUTED,kind='mono',anchor='rm')
    ey=py(0)
    if 836<ey<1145 and t<CLOSE_AT:
        for lx in range(110,810,15):d.line((lx,ey,lx+7,ey),fill=(63,153,221),width=2)
        rr(im,(117,ey-25,307,ey+3),(6,59,94),r=6)
        txt(im,(128,ey-12),'BUY 1 @ 5,825.00',16,MUTED,kind='bold',anchor='lm')
    for i,cl in enumerate(series):
        op=series[i-1] if i else cl-25
        wick=18+(i*17%44)
        xx=125+i*25.6
        draw_candle(im,xx,op,cl,max(op,cl)+wick,min(op,cl)-wick*.7,py,width=17,active=i==len(series)-1)
        vol=11+min(35,abs(cl-op)*.14)+(i*7%12)
        d.rectangle((xx-8,1190-vol,xx+8,1190),fill=(23,124,106) if cl>=op else (136,44,90))
    yy=py(p)
    for xx in range(110,819,15):d.line((xx,yy,xx+7,yy),fill=(0,172,197),width=1)
    rr(im,(817,yy-18,928,yy+18),CYAN,r=7)
    txt(im,(873,yy),f'{ENTRY+p/50:,.2f}',18,INK,kind='mono',anchor='mm')
    txt(im,(910,695),f'{ENTRY+p/50:,.2f}',33,anchor='ra',stroke=1)
    txt(im,(907,732),f'+{(ENTRY+p/50-(ENTRY-5))/(ENTRY-5)*100:.2f}% DAY',17,GREEN,kind='bold',anchor='ra')

def cursor(im,pos,click=0):
    x,y=pos
    d=ImageDraw.Draw(im)
    if click>0:
        r=15+click*58
        d.ellipse((x-r,y-r,x+r,y+r),outline=(157,255,211),width=4)
    points=[(x,y),(x+4,y+37),(x+14,y+28),(x+24,y+45),(x+32,y+40),(x+22,y+24),(x+38,y+21)]
    d.polygon(points,fill=WHITE,outline=INK,width=3)

def captions(im,t):
    # Fixed, readable safe-area subtitles, edited on the 150 BPM grid.
    if t<3.2:
        lines=[('me: “I’ll close',WHITE),('at +$100”',GREEN)]
        start=0
    elif t<4.8:
        lines=[('also me:',WHITE),('let it cook.',GREEN)]; start=3.2
    elif t<6.4:
        lines=[('wait.',WHITE),('don’t do this.',PINK)];start=4.8
    elif t<9.6:
        lines=[('ONE MORE',WHITE),('CANDLE.',GREEN)];start=6.4
    elif t<12.8:
        lines=[('okay this is',WHITE),('getting stupid.',GREEN)];start=9.6
    elif t<15.2:
        lines=[('yeah I’m',WHITE),('logging off.',WHITE)];start=12.8
    else:
        lines=[('…after',WHITE),('one more.',GREEN)];start=15.2
    # Pop-in on each cut, resolving in 5 frames; no slow title lead-in.
    dt=t-start
    bump=1+.07*math.exp(-dt*15)*math.sin(dt*29)
    size=int(75*bump)
    for i,(s,c) in enumerate(lines):
        txt(im,(495,257+i*83),s,size,c,kind='bold',anchor='mm',stroke=4)

def make_frame(t):
    im=BG.copy().convert('RGBA')
    # Small context, same placement throughout; brand remains part of the game UI.
    rr(im,(75,137,267,180),(11,35,62),r=19,outline=(36,73,107),width=1)
    txt(im,(171,158),'ROBLOX',21,MUTED,kind='bold',anchor='mm')
    txt(im,(918,158),'sound on',21,(121,154,183),kind='regular',anchor='rm')
    terminal=STATIC.copy()
    p=profit(t)
    closed=t>=CLOSE_AT
    txt(terminal,(108,578),money(11500 if closed else 10000),43,stroke=1)
    txt(terminal,(522,578),money(0 if closed else p,True),47,stroke=1)
    chart(terminal,t,p)
    if not closed:
        txt(terminal,(112,1343),'BX',33)
        rr(terminal,(184,1342,282,1377),(5,106,78),r=9)
        txt(terminal,(233,1361),'LONG',20,GREEN,kind='bold',anchor='mm')
        txt(terminal,(112,1394),'1 contract  ·  Entry 5,825.00',20,MUTED,kind='regular')
        txt(terminal,(642,1357),money(p,True),35,GREEN,anchor='rm',stroke=1)
        txt(terminal,(642,1408),'Open profit',18,MUTED,kind='regular',anchor='rm')
        panel(terminal,(685,1343,915,1436),(119,64,224),(66,26,160),r=14,border=(192,142,255),width=2,shine=True)
        txt(terminal,(800,1391),'CLOSE',29,anchor='mm',stroke=1)
    else:
        rr(terminal,(110,1340,155,1385),GREEN,r=22)
        ImageDraw.Draw(terminal).line([(121,1362),(130,1371),(145,1354)],fill=INK,width=4)
        txt(terminal,(173,1345),'Trade closed',30)
        txt(terminal,(173,1391),'Profit added to balance',21,MUTED,kind='regular')
        txt(terminal,(905,1369),'+$1,500.00',41,GREEN,anchor='rm',stroke=1)
        txt(terminal,(905,1410),'REALIZED PROFIT',17,MUTED,kind='bold',anchor='rm')
    # Beat-synced card rim is transformed with the UI during the punch-in.
    if 6.4<=t<6.65 or 12.8<=t<13.05:
        dt=t-(6.4 if t<7 else 12.8)
        a=int(200*(1-dt/.25))
        flash=Image.new('RGBA',(W,H))
        ImageDraw.Draw(flash).rounded_rectangle((496,513,940,640),24,outline=(175,255,218,a),width=7)
        terminal=Image.alpha_composite(terminal,flash)
    # Punch-in is tied to the drop; enough context survives to read the trade.
    z=1.0
    if 6.4<=t<9.6:
        z=1.05+.035*(1-smooth((t-6.4)/.35))
        if t>9.4:z=1+.05*(1-smooth((t-9.4)/.2))
    if 12.8<=t<13.35: z=max(z,1+.05*(1-smooth((t-12.8)/.55)))
    if z>1:
        scaled=terminal.resize((int(W*z),int(H*z)),Image.Resampling.BICUBIC)
        terminal=scaled.crop((int(495*(z-1)),int(920*(z-1)),int(495*(z-1))+W,int(920*(z-1))+H))
    # Tiny impact motion on the beat drop, resolved within 0.3 sec.
    dx=dy=0
    if 6.4<=t<6.7:
        a=8*(1-(t-6.4)/.3);dx=int(a*math.sin(t*130));dy=int(a*.5*math.cos(t*117))
    im.alpha_composite(terminal,(dx,dy))
    if 11.95<t<13.2:
        k=smooth((t-11.95)/.65)
        x=985+(815-985)*k;y=1680+(1402-1680)*k
        cursor(im,(x,y),clamp((t-12.8)/.3) if t>=12.8 else 0)
    if t>=15.2:
        k=smooth((t-15.2)/.65)
        cursor(im,(830+(304-830)*k,1700+(1515-1700)*k))
    captions(im,t)
    # Editorial counter occupies its own band; never covers the chart or controls.
    if 6.4<t<12.8:
        txt(im,(495,1683),money(p,True),66,GREEN,kind='bold',anchor='mm',stroke=2)
        txt(im,(495,1737),'STILL IN THE TRADE',19,MUTED,kind='bold',anchor='mm')
    elif 12.8<=t<15.2:
        txt(im,(495,1683),'+$1,500 LOCKED.',55,GREEN,kind='bold',anchor='mm',stroke=2)
        txt(im,(495,1737),'ONE TRADE LATER',19,MUTED,kind='bold',anchor='mm')
    elif t>=15.2:
        txt(im,(495,1664),'famous last words.',33,MUTED,kind='bold',anchor='mm')
    else:
        txt(im,(495,1664),'the +$100 plan lasted 2 seconds',28,MUTED,kind='regular',anchor='mm')
    txt(im,(495,1774),'STAGED TRADE  ·  VIRTUAL GAME FUNDS',18,(114,149,182),kind='bold',anchor='mm')
    return im.convert('RGB')

def make_audio():
    sr=48000
    samples=int(DURATION*sr)
    mix=np.zeros((samples,2),dtype=np.float64)
    rng=np.random.default_rng(42)
    def add(at,sig,vol=1,pan=0):
        idx=int(at*sr);n=min(len(sig),samples-idx)
        if n<=0 or idx<0:return
        mix[idx:idx+n,0]+=sig[:n]*vol*math.sqrt((1-pan)/2)
        mix[idx:idx+n,1]+=sig[:n]*vol*math.sqrt((1+pan)/2)
    def kick():
        t=np.arange(int(.34*sr))/sr
        phase=2*np.pi*(48*t+110*.022*(1-np.exp(-t/.022)))
        return np.sin(phase)*np.exp(-t*13)+rng.normal(0,.18,len(t))*np.exp(-t*180)
    def hat(open=False):
        t=np.arange(int((.13 if open else .055)*sr))/sr
        n=rng.normal(0,1,len(t));n=np.r_[0,np.diff(n)]
        return n*np.exp(-t*(34 if open else 100))
    def clap():
        t=np.arange(int(.18*sr))/sr;n=rng.normal(0,1,len(t));n=np.r_[0,np.diff(n)]
        env=np.exp(-t*35)
        for off in [.011,.023]:env+=np.where(t>=off,np.exp(-np.maximum(t-off,0)*80),0)*.5
        return n*env*.28
    def note(hz,duration=.32,bass=False):
        t=np.arange(int(duration*sr))/sr
        sig=np.sin(2*np.pi*hz*t)+(.2 if bass else .3)*np.sin(2*np.pi*hz*2*t)
        if not bass:sig+=.13*np.sin(2*np.pi*hz*3*t)
        env=np.minimum(t/.006,1)*np.exp(-t*(5 if bass else 11))*np.minimum((duration-t)/.035,1)
        return sig*env
    roots=[55,55,65.406,49]
    melody=[440,523.25,659.25,587.33,523.25,440,783.99,659.25]
    for beat in range(40):
        at=beat*BEAT
        drop=at>=6.4
        # Sparse first half, with a half-beat silence before the drop.
        if 6.15<at<6.4:continue
        level=.92 if drop else .48
        if beat%4 in (0,2) or (drop and beat%8==7):add(at,kick(),.60*level)
        if beat%4 in (1,3):add(at,clap(),.35*level)
        for half in range(2 if drop else 1):
            add(at+half*.2,hat(),.048 if half else .067,pan=(-.25 if half else .25))
        if drop and beat%4==3:
            for off in [.25,.3,.35]:add(at+off,hat(),.03,pan=.35)
        root=roots[(beat//4)%4]
        if beat%2==0: add(at,note(root,.62,True),.23 if drop else .12)
        if beat%2==0 or drop:
            sig=note(melody[(beat//2)%8],.34)
            add(at,sig,.105 if drop else .078,pan=-.1)
            add(at+.15,sig,.025,pan=.4)
    # Original riser, short whooshes and ascending transaction tones.
    rt=np.arange(int(1.3*sr))/sr
    rise=(rng.normal(0,1,len(rt))*.12+np.sin(2*np.pi*(190*rt+700*rt**2))*.16)*(rt/1.3)**2
    add(4.85,rise,.6)
    for at in [3.2,6.4,9.6]:
        wt=np.arange(int(.2*sr))/sr
        add(at-.07,rng.normal(0,1,len(wt))*np.sin(np.pi*wt/.2)**2,.07,pan=.2)
    for at,hz in [(1.6,880),(4.8,1046.5),(8,1174.66),(10.4,1318.5)]:add(at,note(hz,.2),.065)
    for i,hz in enumerate([659.25,830.61,987.77,1318.51]):add(12.8+i*.095,note(hz,.7),.2,pan=(i-1.5)*.12)
    # Soft pause on the joke, then a single UI tap into the loop.
    mix[int(15.2*sr):]*=.6
    add(15.9,note(1050,.07),.11)
    mix=np.tanh(mix*1.8)
    mix*=.88/max(np.max(np.abs(mix)),.001)
    fade=np.ones(samples);fade[:240]=np.linspace(0,1,240);fade[-1200:]=np.linspace(1,0,1200)
    mix*=fade[:,None]
    with wave.open(str(OUT/'source'/'original-beat.wav'),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(sr);f.writeframes((mix*32767).astype('<i2').tobytes())
    return {'sample_rate':sr,'seconds':DURATION,'peak_dbfs':float(20*np.log10(np.max(abs(mix)))),'bpm':150,'composition':'Original synthesized instrumental and UI effects; no sampled music.'}

def previews():
    times=[.7,3.8,5.7,7.2,10.4,13.4,15.8]
    for i,t in enumerate(times):make_frame(t).save(OUT/'previews'/f'{i+1:02d}-{t:04.1f}s.jpg',quality=92)
    cover=make_frame(7.6);cover.save(OUT/'cover.jpg',quality=96)
    sheet=Image.new('RGB',(270*4,480*2),(2,9,25))
    for i,t in enumerate(times):
        shot=make_frame(t).resize((270,480),Image.Resampling.LANCZOS)
        ImageDraw.Draw(shot).rectangle((5,5,62,29),fill=(2,9,25))
        ImageDraw.Draw(shot).text((11,8),f'{t:.1f}s',font=font(17,'bold'),fill=WHITE)
        sheet.paste(shot,((i%4)*270,(i//4)*480))
    sheet.save(OUT/'previews'/'contact-sheet.jpg',quality=94)

def render():
    exe=imageio_ffmpeg.get_ffmpeg_exe()
    audio_info=make_audio()
    cmd=[exe,'-y','-hide_banner','-loglevel','warning','-f','rawvideo','-vcodec','rawvideo',
         '-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-',
         '-i',str(OUT/'source'/'original-beat.wav'),'-c:v','libx264','-preset','fast',
         '-crf','18','-profile:v','high','-pix_fmt','yuv420p','-r',str(FPS),
         '-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709',
         '-af','loudnorm=I=-14:TP=-2.5:LRA=8,alimiter=limit=0.75:level=false','-c:a','aac','-b:a','192k','-ar','48000',
         '-movflags','+faststart','-t',str(DURATION),str(OUT/'Get-Funded-One-More-Candle.mp4')]
    with open(OUT/'source'/'encode.log','w') as log:
        proc=subprocess.Popen(cmd,stdin=subprocess.PIPE,stderr=log)
        for i in range(int(FPS*DURATION)):
            proc.stdin.write(make_frame(i/FPS).tobytes())
            if i%60==0: print(f'Rendered {i}/{int(FPS*DURATION)} frames',flush=True)
        proc.stdin.close()
        if proc.wait()!=0: raise RuntimeError('ffmpeg failed; see encode.log')
    info={'file':'Get-Funded-One-More-Candle.mp4','width':W,'height':H,'fps':FPS,
          'duration':DURATION,'frames':int(FPS*DURATION),'audio':audio_info,
          'provenance':'Staged animation reconstructed from the current game UI; not a live recording.',
          'trade':{'market':'BX / Blox 500','quantity':1,'entry':ENTRY,'exit':5855,'multiplier':50,'realized_profit':1500,'starting_balance':10000,'ending_balance':11500}}
    (OUT/'source'/'render-metadata.json').write_text(json.dumps(info,indent=2))
    print('Finished:',OUT/'Get-Funded-One-More-Candle.mp4',flush=True)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--previews-only',action='store_true');args=ap.parse_args()
    previews()
    if not args.previews_only:render()

import Foundation

/// Generates a self-contained, offline HTML dashboard from the database.
/// No server, no network — the file embeds its data inline as JSON and is
/// rendered in the app's own WKWebView window (see DashboardWindow).
enum Dashboard {

    /// The full self-contained dashboard HTML for the given moment.
    static func htmlString(store: Database, now: Date = Date()) -> String {
        let payload = DashboardData.build(store: store, now: now)
        let json = (try? JSONEncoder().encode(payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return html(json: json)
    }

    /// Writes the dashboard to disk and returns the file URL (used by the test hook).
    @discardableResult
    static func generate(store: Database, now: Date = Date()) -> URL {
        let url = outputURL()
        try? Data(htmlString(store: store, now: now).utf8).write(to: url)
        return url
    }

    private static func outputURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("FocusTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dashboard.html")
    }

    // The only interpolation in this raw string is `\#(json)`.
    private static func html(json: String) -> String {
        return #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>scattrd — Daily Replay</title>
<style>
  :root{
    --bg:#07080c; --text:#eef0f6; --muted:#8b93a8; --faint:#5b6379;
    --card:rgba(255,255,255,.04); --brd:rgba(255,255,255,.09); --brd2:rgba(255,255,255,.14);
    --green:#34d399; --amber:#fbbf24; --red:#fb7185; --gray:#5b6478;
  }
  *{box-sizing:border-box}
  html{color-scheme:dark}
  body{margin:0;background:var(--bg);color:var(--text);overflow-x:hidden;
    font:15px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;
    -webkit-font-smoothing:antialiased;letter-spacing:.01em}

  /* Drifting aurora background for depth */
  .aurora{position:fixed;inset:-30vmax;z-index:0;filter:blur(90px);opacity:.55;pointer-events:none}
  .aurora span{position:absolute;width:46vmax;height:46vmax;border-radius:50%;mix-blend-mode:screen}
  .a1{background:#5b8cff;top:-6vmax;left:-4vmax;animation:drift1 22s ease-in-out infinite}
  .a2{background:#9b5cff;bottom:-8vmax;right:-2vmax;animation:drift2 26s ease-in-out infinite}
  .a3{background:#22d3ee;top:30%;left:38%;width:34vmax;height:34vmax;opacity:.5;animation:drift3 30s ease-in-out infinite}
  @keyframes drift1{50%{transform:translate(8vmax,6vmax) scale(1.15)}}
  @keyframes drift2{50%{transform:translate(-7vmax,-5vmax) scale(1.1)}}
  @keyframes drift3{50%{transform:translate(-6vmax,7vmax) scale(1.2)}}

  .wrap{position:relative;z-index:1;max-width:1180px;margin:0 auto;padding:46px 38px 84px}

  /* Reveal-on-load motion */
  @keyframes rise{from{opacity:0;transform:translateY(16px)}to{opacity:1;transform:none}}
  .reveal{opacity:0;animation:rise .7s cubic-bezier(.2,.8,.2,1) forwards}

  h2{font-size:14px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);
    margin:0 0 24px;font-weight:600;display:flex;align-items:center;gap:12px}
  h2::after{content:"";flex:1;height:1px;background:linear-gradient(90deg,var(--brd),transparent)}

  /* Glass surface */
  .glass{background:var(--card);border:1px solid var(--brd);border-radius:20px;
    backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);
    box-shadow:inset 0 1px 0 rgba(255,255,255,.05),0 18px 40px -22px rgba(0,0,0,.8)}

  /* ---- Hero ---- */
  header{display:flex;align-items:center;gap:34px;margin-bottom:34px;flex-wrap:wrap}
  .ring{position:relative;width:184px;height:184px;flex:0 0 auto}
  .ring svg{transform:rotate(-90deg)}
  .ring .ring-num{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
  .ring .big{font-size:58px;font-weight:750;line-height:1;letter-spacing:-.02em;
    background-clip:text;-webkit-background-clip:text;color:transparent}
  .ring .den{font-size:12px;color:var(--muted);margin-top:5px;letter-spacing:.06em}
  .head-meta{flex:1;min-width:260px}
  .eyebrow{font-size:12.5px;color:var(--muted);letter-spacing:.04em}
  .verdict{font-size:34px;font-weight:720;letter-spacing:-.025em;line-height:1.1;margin:6px 0 16px;
    background:linear-gradient(180deg,#fff,rgba(255,255,255,.62));
    background-clip:text;-webkit-background-clip:text;color:transparent}
  .chips{display:flex;gap:9px;flex-wrap:wrap}
  .chip{padding:7px 13px;border-radius:12px;font-size:12px;color:var(--muted);
    background:var(--card);border:1px solid var(--brd);transition:.25s}
  .chip:hover{border-color:var(--brd2);color:var(--text);transform:translateY(-1px)}
  .streak-chip{background:rgba(251,146,60,.13);border-color:rgba(251,146,60,.34);color:var(--text)}
  .chip b{color:var(--text);font-weight:650;font-variant-numeric:tabular-nums}

  /* ---- Stat cards ---- */
  .cards{display:grid;grid-template-columns:repeat(5,1fr);gap:13px;margin-bottom:24px}
  .card{padding:17px 18px;border-radius:17px;transition:transform .3s cubic-bezier(.2,.8,.2,1),border-color .3s}
  .card:hover{transform:translateY(-3px);border-color:var(--brd2)}
  .card .n{font-size:25px;font-weight:730;font-variant-numeric:tabular-nums;letter-spacing:-.02em}
  .card .l{font-size:11.5px;color:var(--muted);margin-top:5px}
  .card .spark{height:3px;border-radius:3px;margin-top:11px;background:var(--brd);overflow:hidden}
  .card .spark i{display:block;height:100%;width:0;border-radius:3px;transition:width 1.1s cubic-bezier(.2,.8,.2,1) .3s}

  .panel{padding:30px 30px 32px;border-radius:24px;margin-bottom:24px}

  /* ---- Replay ---- */
  .replay{position:relative;user-select:none}
  .golden{font-size:13px;color:var(--amber);font-weight:600;margin:-8px 0 14px;display:flex;align-items:center;gap:6px}
  .golden b{color:#fcd34d}
  .goldband{position:absolute;top:0;bottom:0;z-index:0;pointer-events:none;
    background:linear-gradient(180deg,rgba(251,191,36,.18),rgba(251,191,36,.05));
    border-left:1px solid rgba(251,191,36,.35);border-right:1px solid rgba(251,191,36,.35)}
  .mtgrow{position:relative;height:0}
  .mtg{position:absolute;top:0;height:22px;line-height:22px;border-radius:6px;font-size:10.5px;padding:0 7px;
    background:rgba(91,140,255,.24);border:1px solid rgba(91,140,255,.5);color:#c7d6ff;
    overflow:hidden;white-space:nowrap;text-overflow:ellipsis;min-width:6px}
  .mrow{display:flex;align-items:center;gap:12px;padding:8px 2px;border-bottom:1px solid rgba(255,255,255,.06);font-size:13px}
  .mrow:last-child{border-bottom:0}
  .mt{color:var(--muted);width:62px;flex:0 0 auto;font-variant-numeric:tabular-nums}
  .mname{flex:1;font-weight:550;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .mi{font-weight:600;white-space:nowrap;font-size:12.5px}
  .mi-na{color:var(--faint);font-size:12px}
  .mtg-sub{font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);font-weight:650;margin-bottom:6px}
  .mtg-hint{color:var(--muted);font-size:13px;padding:8px 0;line-height:1.6}
  .mtg-hint .sub{font-size:12px;margin-top:4px;color:var(--faint)}
  .strip{position:relative;height:120px;margin-top:4px;border-radius:14px;overflow:hidden;
    background:rgba(255,255,255,.025);border:1px solid var(--brd)}
  .seg{position:absolute;top:0;bottom:0;min-width:2px;opacity:0;animation:segIn .5s ease forwards}
  .seg:hover{filter:brightness(1.25)}
  @keyframes segIn{to{opacity:1}}
  .axis{position:relative;height:24px;margin-top:11px;color:var(--faint);font-size:13px}
  .axis span{position:absolute;transform:translateX(-50%)}
  .scrub{position:absolute;top:0;width:1px;background:rgba(255,255,255,.6);pointer-events:none;opacity:0;transition:opacity .15s}
  .scrub .rd{position:absolute;top:-22px;left:50%;transform:translateX(-50%);background:#0b0d12;
    border:1px solid var(--brd2);border-radius:7px;padding:2px 8px;font-size:11px;white-space:nowrap}
  .legend{display:flex;gap:26px;margin-top:26px;flex-wrap:wrap;font-size:13.5px;color:var(--muted)}
  .legend i{width:9px;height:9px;border-radius:3px;display:inline-block;margin-right:7px;vertical-align:0}
  .tip{position:fixed;pointer-events:none;opacity:0;transition:opacity .12s;z-index:20;padding:9px 12px;
    border-radius:11px;font-size:12px;max-width:250px;background:rgba(12,14,20,.92);
    border:1px solid var(--brd2);backdrop-filter:blur(10px);box-shadow:0 10px 30px -10px #000}
  .tip .ta{font-weight:650;margin-bottom:2px}
  .tip .tb{color:var(--muted)}

  /* ---- Distractions ---- */
  .drow{display:flex;align-items:center;gap:14px;margin-bottom:12px}
  .drow .dn{width:150px;flex:0 0 auto;font-weight:550;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .dbar{height:26px;border-radius:8px;min-width:4px;width:0;
    background:linear-gradient(90deg,#fb7185,#f43f5e);box-shadow:0 0 16px -4px rgba(244,63,94,.6);
    transition:width 1s cubic-bezier(.2,.8,.2,1) .25s}
  .drow .dm{color:var(--muted);font-size:12px;white-space:nowrap}
  .empty{color:var(--muted);padding:10px 0}

  /* ---- Week ---- */
  .week{display:grid;grid-template-columns:repeat(7,1fr);gap:12px;align-items:end;height:150px;margin-bottom:6px}
  .wday{display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:100%;gap:9px}
  .wbar{width:100%;max-width:50px;border-radius:9px 9px 4px 4px;height:0;
    display:flex;align-items:flex-start;justify-content:center;color:#05140d;font-weight:750;font-size:12px;
    padding-top:5px;transition:height .9s cubic-bezier(.2,.8,.2,1)}
  .wtoday{outline:2px solid rgba(120,160,255,.8);outline-offset:3px;border-radius:11px;
    box-shadow:0 0 22px -4px rgba(120,160,255,.5)}
  .wmeta{font-size:11px;color:var(--muted);text-align:center;line-height:1.3}
  .wmeta b{color:var(--text)}
  .wday.clickable{cursor:pointer}
  .wday.clickable:hover .wbar{filter:brightness(1.2)}
  .dayModal{position:fixed;inset:0;z-index:30;background:rgba(5,6,10,.62);backdrop-filter:blur(5px);
    display:none;align-items:center;justify-content:center;opacity:0;transition:opacity .2s}
  .dayModal.open{display:flex;opacity:1}
  .dayCard{width:380px;max-width:90vw;background:#13161d;border:1px solid var(--brd2);border-radius:20px;
    padding:24px;box-shadow:0 30px 80px -20px #000;animation:pop .25s cubic-bezier(.2,.8,.2,1)}
  @keyframes pop{from{transform:scale(.94);opacity:0}to{transform:none;opacity:1}}
  .dayHd{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:18px;gap:14px}
  .dayTitle{font-size:18px;font-weight:700}
  .dayVerd{font-size:13px;font-weight:600;margin-top:3px}
  .dayScore{font-size:46px;font-weight:780;line-height:1;letter-spacing:-.03em}
  .dayRow{display:flex;justify-content:space-between;padding:9px 2px;border-bottom:1px solid rgba(255,255,255,.06);font-size:13.5px}
  .dayRow:last-child{border-bottom:0}
  .dk{color:var(--muted)}
  .dv{font-weight:600}
  .dayClose{margin-top:18px;width:100%;padding:11px;border-radius:12px;background:var(--card);
    border:1px solid var(--brd);color:var(--text);font:inherit;font-weight:600;cursor:pointer}
  .dayClose:hover{border-color:var(--brd2)}
  .finger{display:flex;gap:14px;margin-top:20px;flex-wrap:wrap}
  .fcard{flex:1;min-width:150px;padding:16px 18px;border-radius:16px;
    background:#161a24;border:1px solid var(--brd);backdrop-filter:none;-webkit-backdrop-filter:none}
  .fcard .ft{font-size:12px;color:var(--muted)}
  .fcard .fv{font-size:21px;font-weight:720;margin-top:4px;letter-spacing:-.01em}

  footer{color:var(--faint);font-size:11.5px;text-align:center;margin-top:38px}
  .warm{padding:34px;text-align:center;color:var(--muted);margin-bottom:22px;border-radius:20px;border-style:dashed}
  .warm b{color:var(--text)}

  /* ---- Customize bar ---- */
  .ctog{display:inline-flex;align-items:center;padding:3px 10px;border-radius:9px;
    font-size:11px;font-weight:680;cursor:pointer;transition:.2s;
    margin-left:10px;vertical-align:2px;border:1px solid transparent}
  .ctog.on{background:rgba(52,211,153,.16);color:var(--green);border-color:rgba(52,211,153,.3)}
  .ctog.off{background:rgba(255,255,255,.07);color:var(--muted);border-color:var(--brd)}
  .cust-off-note{font-size:13px;color:var(--faint);padding:2px 0 4px}
  .cust-search{position:relative;margin-bottom:16px}
  .cust-search input{width:100%;padding:10px 14px;border-radius:12px;
    background:rgba(255,255,255,.06);border:1px solid var(--brd);
    color:var(--text);font:inherit;font-size:13.5px;outline:none;transition:.2s}
  .cust-search input:focus{border-color:var(--brd2);background:rgba(255,255,255,.08)}
  .cust-dd{position:absolute;top:calc(100% + 5px);left:0;right:0;border-radius:12px;
    background:#13161d;border:1px solid var(--brd2);z-index:20;overflow:hidden;
    box-shadow:0 16px 40px -12px #000;display:none}
  .cust-dd.open{display:block}
  .cust-ddi{padding:10px 15px;font-size:13px;cursor:pointer;transition:.12s;
    display:flex;align-items:center;justify-content:space-between;gap:10px}
  .cust-ddi:hover{background:rgba(255,255,255,.07)}
  .cust-ddi .ddi-name{flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .cust-ddi .ddi-cat{font-size:11px;padding:2px 8px;border-radius:6px;font-weight:650;white-space:nowrap}
  .cust-picker-wrap{margin-bottom:16px;padding:14px;border-radius:14px;
    background:rgba(255,255,255,.04);border:1px solid var(--brd)}
  .cust-picker-label{font-size:12px;color:var(--muted);margin-bottom:10px;font-weight:600}
  .cust-picker{display:flex;gap:8px;flex-wrap:wrap}
  .cat-btn{flex:1;min-width:90px;padding:9px 6px;border-radius:10px;font:inherit;
    font-size:12.5px;font-weight:650;cursor:pointer;border:2px solid rgba(255,255,255,.12);
    transition:.15s;color:#fff;opacity:.75}
  .cat-btn:hover{opacity:1;filter:brightness(1.1)}
  .cat-btn.sel{opacity:1;border-color:#fff;box-shadow:0 0 0 1px rgba(255,255,255,.25)}
  .cust-chips{display:flex;gap:8px;flex-wrap:wrap;margin-top:4px}
  .cust-chip{display:inline-flex;align-items:center;gap:7px;padding:6px 10px 6px 13px;
    border-radius:10px;font-size:12.5px;font-weight:600;
    background:rgba(255,255,255,.06);border:1px solid var(--brd);cursor:default}
  .cust-chip .cc-dot{width:8px;height:8px;border-radius:50%;flex:0 0 auto}
  .cust-chip .cc-x{font-size:15px;line-height:1;cursor:pointer;color:var(--muted);
    transition:.15s;padding:0 2px}
  .cust-chip .cc-x:hover{color:var(--red)}
</style>
</head>
<body>
<div class="aurora"><span class="a1"></span><span class="a2"></span><span class="a3"></span></div>
<div class="wrap">
  <header class="reveal">
    <div class="ring" id="ring"></div>
    <div class="head-meta">
      <div class="eyebrow" id="date"></div>
      <div class="verdict" id="verdict"></div>
      <div class="chips" id="chips"></div>
    </div>
  </header>

  <div id="warm" style="display:none" class="glass warm reveal"></div>

  <section class="cards" id="cards"></section>

  <section class="panel glass reveal">
    <h2>Focus Replay</h2>
    <div class="golden" id="golden"></div>
    <div class="replay" id="replay">
      <div class="mtgrow" id="mtgrow"></div>
      <div class="strip" id="strip"></div>
      <div class="scrub" id="scrub"><div class="rd" id="rd"></div></div>
      <div class="axis" id="axis"></div>
    </div>
    <div class="legend">
      <span><i style="background:var(--green)"></i>Deep work</span>
      <span><i style="background:var(--amber)"></i>Communication</span>
      <span><i style="background:var(--red)"></i>Distraction</span>
      <span><i style="background:var(--gray)"></i>Neutral / web</span>
    </div>
  </section>

  <section class="panel glass reveal">
    <h2>Meetings &amp; Focus</h2>
    <div id="meetings"></div>
  </section>

  <section class="panel glass reveal">
    <h2>Distraction Leaderboard</h2>
    <div id="distractions"></div>
  </section>

  <section class="panel glass reveal">
    <h2>Weekly Patterns</h2>
    <div class="week" id="week"></div>
    <div class="finger" id="finger"></div>
  </section>

  <section class="panel glass reveal" id="cust-section">
    <h2>Customize Categories
      <span class="ctog" id="cust-tog" onclick="custToggle()"></span>
    </h2>
    <div id="cust-body"></div>
  </section>

  <footer>🔒 All data stays on your Mac · nothing leaves this device · <span id="gen"></span></footer>
</div>
<div class="tip" id="tip"></div>
<div class="dayModal" id="dayModal"></div>

<script>
const DATA = \#(json);
const T = DATA.today, W = DATA.week;
const CATC = {0:'#34d399',1:'#fbbf24',2:'#fb7185',3:'#5b6478',4:'transparent'};
const $ = id => document.getElementById(id);
const fmt = m => m>=10 ? Math.round(m).toString() : (Math.round(m*10)/10).toString();
const band = s => s>=70?'#34d399':s>=40?'#fbbf24':'#fb7185';
const grad = s => s>=70?['#34d399','#22d3ee']:s>=40?['#fbbf24','#fb923c']:['#fb7185','#f43f5e'];
const hhmm = ts => new Date(ts*1000).toLocaleTimeString([], {hour:'numeric', minute:'2-digit'});
const ease = p => 1-Math.pow(1-p,3);

// Stagger the reveals
document.querySelectorAll('.reveal').forEach((el,i)=>el.style.animationDelay=(i*0.09)+'s');

// ---- Hero ring (animated sweep + count-up) ----
(function(){
  const s=T.hasData?T.score:0, r=80, c=2*Math.PI*r, [c1,c2]=grad(s);
  $('ring').innerHTML =
    '<svg width="184" height="184" viewBox="0 0 184 184">'+
    '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'+
    '<stop offset="0" stop-color="'+c1+'"/><stop offset="1" stop-color="'+c2+'"/></linearGradient></defs>'+
    '<circle cx="92" cy="92" r="'+r+'" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="10"/>'+
    '<circle id="arc" cx="92" cy="92" r="'+r+'" fill="none" stroke="url(#g)" stroke-width="10" '+
      'stroke-linecap="round" stroke-dasharray="'+c+'" stroke-dashoffset="'+c+'" '+
      'style="transition:stroke-dashoffset 1.2s cubic-bezier(.2,.8,.2,1)"/></svg>'+
    '<div class="ring-num"><div class="big" id="bn" style="background-image:linear-gradient(180deg,'+c1+','+c2+')">'+(T.hasData?'0':'–')+'</div>'+
    '<div class="den">/ 100 focus</div></div>';
  if(T.hasData){
    requestAnimationFrame(()=>{ setTimeout(()=>{ $('arc').setAttribute('stroke-dashoffset', c*(1-s/100)); },60); });
    const bn=$('bn'), t0=performance.now();
    (function up(t){ const p=Math.min(1,(t-t0)/1200); bn.textContent=Math.round(ease(p)*s); if(p<1)requestAnimationFrame(up); })(t0);
  }
})();
$('date').textContent = DATA.date;
$('verdict').textContent = T.verdict;
const streakChip = T.streak>0 ? '<span class="chip streak-chip">🔥 <b>'+T.streak+'</b> day streak · best '+T.streakBest+'</span>' : '';
$('chips').innerHTML = streakChip + (T.hasData ?
  [['Sustain',T.sustain],['Switching',T.switching],['Deep work',T.deepWork]]
    .map(p=>'<span class="chip">'+p[0]+' <b>'+p[1]+'</b></span>').join('') : '');

// ---- Stat cards ----
const cards=[
  [T.switches,'context switches', Math.min(100,T.switches), 'var(--red)'],
  [fmt(T.avgFocus)+'m','avg focus block', Math.min(100,T.avgFocus/20*100), 'var(--green)'],
  [fmt(T.longestFocus)+'m','longest streak', Math.min(100,T.longestFocus/45*100), 'var(--green)'],
  [T.deepWorkBlocks,'deep-work blocks', Math.min(100,T.deepWorkBlocks*25), 'var(--green)'],
  [fmt(T.activeMinutes)+'m','active time', Math.min(100,T.activeMinutes/240*100), 'var(--amber)'],
];
$('cards').innerHTML = cards.map(c=>
  '<div class="card glass reveal"><div class="n">'+c[0]+'</div><div class="l">'+c[1]+'</div>'+
  '<div class="spark"><i data-w="'+c[2]+'" style="background:'+c[3]+'"></i></div></div>').join('');
document.querySelectorAll('.cards .reveal').forEach((el,i)=>el.style.animationDelay=(0.15+i*0.06)+'s');
setTimeout(()=>document.querySelectorAll('.spark i').forEach(i=>i.style.width=i.dataset.w+'%'),300);

// ---- Focus Replay ----
const span=Math.max(1,T.dayEnd-T.dayStart), xPct=ts=>(ts-T.dayStart)/span*100;
$('strip').innerHTML = T.segments.map((s,i)=>{
  const l=xPct(s.start), w=Math.max(0.18,xPct(s.end)-xPct(s.start));
  return '<div class="seg" data-app="'+encodeURIComponent(s.app)+'" data-s="'+s.start+'" data-e="'+s.end+'" '+
    'style="left:'+l+'%;width:'+w+'%;background:'+CATC[s.cat]+';animation-delay:'+(0.3+i*0.012)+'s"></div>';
}).join('');
(function(){
  let html='';
  for(let t=Math.ceil(T.dayStart/3600)*3600; t<=T.dayEnd; t+=3600){
    const h=new Date(t*1000).getHours(); if(h%2) continue;
    html+='<span style="left:'+xPct(t)+'%">'+(h%12||12)+(h<12?'a':'p')+'</span>';
  }
  $('axis').innerHTML=html;
})();
// ---- Golden hours ----
$('golden').innerHTML = T.goldenValid ? '⭐ Your brain peaks at <b>'+T.goldenLabel+'</b> — your golden hours' : '';
if(T.goldenValid){
  const gl=Math.max(0,xPct(T.goldenStartTs)), gr=Math.min(100,xPct(T.goldenEndTs));
  if(gr>gl){
    const band='<div class="goldband" style="left:'+gl+'%;width:'+(gr-gl)+'%"></div>';
    $('strip').insertAdjacentHTML('afterbegin',band);
  }
}
// ---- Meetings overlay on the timeline ----
(function(){
  const mr=$('mtgrow'); if(!mr) return;
  const esc=s=>(''+s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  if(DATA.calendarOn && DATA.meetings.length){
    mr.style.height='24px'; mr.style.marginBottom='8px';
    mr.innerHTML=DATA.meetings.map(m=>{
      const l=Math.max(0,xPct(m.startTs)), r=Math.min(100,xPct(m.endTs));
      if(r<=l) return '';
      return '<div class="mtg" style="left:'+l+'%;width:'+(r-l)+'%">'+esc(m.title)+'</div>';
    }).join('');
  }
})();
const tip=$('tip'), strip=$('strip'), scrub=$('scrub'), rd=$('rd'), replay=$('replay');
strip.addEventListener('mousemove',e=>{
  const seg=e.target.closest('.seg'); if(!seg){tip.style.opacity=0;return;}
  const s=+seg.dataset.s, en=+seg.dataset.e;
  tip.innerHTML='<div class="ta">'+decodeURIComponent(seg.dataset.app)+'</div><div class="tb">'+hhmm(s)+' – '+hhmm(en)+' · '+fmt((en-s)/60)+' min</div>';
  tip.style.opacity=1; tip.style.left=(e.clientX+15)+'px'; tip.style.top=(e.clientY+15)+'px';
});
strip.addEventListener('mouseleave',()=>tip.style.opacity=0);
replay.addEventListener('mousemove',e=>{
  const b=replay.getBoundingClientRect(), frac=Math.min(1,Math.max(0,(e.clientX-b.left)/b.width));
  scrub.style.left=(frac*100)+'%'; scrub.style.height=b.height+'px'; scrub.style.opacity=.85;
  rd.textContent=hhmm(T.dayStart+frac*span);
});
replay.addEventListener('mouseleave',()=>scrub.style.opacity=0);

// ---- Warm-up notice ----
if(!T.hasData){
  $('warm').style.display='block';
  $('warm').innerHTML='⏳ <b>Warming up.</b> Once you\'ve logged ~5 minutes of activity, your Focus Score and a richer replay appear here. The timeline below shows what you\'ve done so far.';
}

// ---- Distraction leaderboard ----
(function(){
  const d=T.distractions;
  if(!d.length){ $('distractions').innerHTML='<div class="empty">'+(T.hasData?'No distractions logged — nicely focused 👏':'—')+'</div>'; return; }
  const max=Math.max(...d.map(x=>x.switchIns),1);
  $('distractions').innerHTML=d.map(x=>
    '<div class="drow"><div class="dn">'+x.app+'</div>'+
    '<div class="dbar" data-w="'+(x.switchIns/max*72+5)+'"></div>'+
    '<div class="dm">'+x.switchIns+' interruption'+(x.switchIns===1?'':'s')+' · '+fmt(x.minutes)+' min</div></div>').join('');
  setTimeout(()=>document.querySelectorAll('.dbar').forEach(b=>b.style.width=b.dataset.w+'%'),300);
})();

// ---- Day detail modal (click a weekly day) ----
function showDay(i){
  const d=W.days[i]; if(!d||!d.hasData) return;
  const fn=m=>m>=10?Math.round(m):Math.round(m*10)/10;
  const rows=[['Focus score',d.score+' / 100'],['Context switches',d.switches],['Avg focus block',fn(d.avgFocus)+' min'],['Longest streak',fn(d.longestFocus)+' min'],['Deep-work blocks',d.deepWorkBlocks],['Active time',fn(d.activeMin)+' min'],['Top distraction',d.topApp]];
  $('dayModal').innerHTML='<div class="dayCard" onclick="event.stopPropagation()">'+
    '<div class="dayHd"><div><div class="dayTitle">'+d.label+' '+d.date+'</div><div class="dayVerd" style="color:'+band(d.score)+'">'+d.verdict+'</div></div>'+
    '<div class="dayScore" style="color:'+band(d.score)+'">'+d.score+'</div></div>'+
    rows.map(r=>'<div class="dayRow"><span class="dk">'+r[0]+'</span><span class="dv">'+r[1]+'</span></div>').join('')+
    '<button class="dayClose" onclick="closeDay()">Close</button></div>';
  const m=$('dayModal'); m.classList.add('open'); m.onclick=closeDay;
}
function closeDay(){ $('dayModal').classList.remove('open'); }

// ---- Weekly patterns ----
(function(){
  const days=W.days;
  $('week').innerHTML=days.map((d,i)=>{
    const h=d.hasData?Math.max(14,d.score):5, col=d.hasData?band(d.score):'rgba(255,255,255,.08)';
    return '<div class="wday'+(d.isToday?' wtoday':'')+(d.hasData?' clickable':'')+'"'+(d.hasData?' onclick="showDay('+i+')"':'')+'>'+
      '<div class="wbar" data-h="'+h+'" style="background:'+col+'">'+(d.hasData?d.score:'')+'</div>'+
      '<div class="wmeta"><b>'+d.label+'</b><br>'+d.date+'</div></div>';
  }).join('');
  setTimeout(()=>document.querySelectorAll('.wbar').forEach(b=>b.style.height=b.dataset.h+'%'),300);

  const m=W.morningScore, a=W.afternoonScore;
  const lean=(m===0&&a===0)?'Keep tracking to reveal your focus fingerprint.'
    :(m>a?'You focus deeper in the <b>morning</b>.':a>m?'You focus deeper in the <b>afternoon</b>.':'Your focus is evenly split across the day.');
  $('finger').innerHTML=
    '<div class="fcard"><div class="ft">Morning deep-work</div><div class="fv" style="color:'+band(m)+'">'+m+'%</div></div>'+
    '<div class="fcard"><div class="ft">Afternoon deep-work</div><div class="fv" style="color:'+band(a)+'">'+a+'%</div></div>'+
    '<div class="fcard"><div class="ft">Best / toughest day</div><div class="fv">'+W.bestDay+' <span style="color:var(--faint);font-weight:500;font-size:14px">vs</span> '+W.worstDay+'</div></div>'+
    '<div class="fcard" style="flex:2"><div class="ft">Your pattern</div><div class="fv" style="font-size:15px;font-weight:560;line-height:1.45">'+lean+'</div></div>';
})();

// ---- Meetings & focus ----
(function(){
  const el=$('meetings'); if(!el) return;
  const esc=s=>(''+s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  if(!DATA.calendarOn){
    el.innerHTML='<div class="mtg-hint">📅 Connect your calendar to see how meetings affect your focus.<div class="sub">Turn on “Show calendar meetings” from the 🧠 menubar menu.</div></div>';
    return;
  }
  const ms=DATA.meetings, worst=DATA.meetingWorst;
  const hhmm=ts=>new Date(ts*1000).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'});
  let html='<div class="mtg-sub">Today</div>';
  if(ms.length){
    html+=ms.map(m=>{
      const imp=m.postScore<0?'<span class="mi-na">upcoming / no data</span>'
        :'<span class="mi" style="color:'+band(m.postScore)+'">focus '+m.postScore+' after'+(m.drop>0?' · ▼'+m.drop:'')+'</span>';
      return '<div class="mrow"><span class="mt">'+hhmm(m.startTs)+'</span><span class="mname">'+esc(m.title)+'</span>'+imp+'</div>';
    }).join('');
  } else { html+='<div class="mtg-hint">No meetings today 🎉</div>'; }
  if(worst.length){
    html+='<div class="mtg-sub" style="margin-top:18px">Focus-killer meetings · this week</div>';
    html+=worst.map(w=>'<div class="mrow"><span class="mname">'+esc(w.title)+'</span><span class="mi" style="color:#fb7185">▼'+w.avgDrop+' avg · '+w.count+'×</span></div>').join('');
  }
  el.innerHTML=html;
})();

// ---- Customize bar ----
(function(){
  // Category metadata: rawValue, label, hex color, background for chips/buttons.
  const CATS = [
    { id:0, label:'Deep work',     color:'#34d399', bg:'rgba(52,211,153,.22)'  },
    { id:1, label:'Communication', color:'#fbbf24', bg:'rgba(251,191,36,.22)'  },
    { id:2, label:'Distraction',   color:'#fb7185', bg:'rgba(251,113,133,.22)' },
    { id:3, label:'Neutral',       color:'#8b93a8', bg:'rgba(91,99,120,.22)'   },
  ];
  // catMeta by rawValue
  const catOf = id => CATS.find(c=>c.id===id) || CATS[3];

  let custEnabled = DATA.customizeEnabled;
  let custOverrides = DATA.overrides || {};           // {name: rawInt}
  const knownApps = DATA.knownApps || [];            // [{n,c}]
  let selectedApp = null;                             // currently active picker target

  const tog    = $('cust-tog');
  const body   = $('cust-body');

  // ---- Swift sync callback (no full reload) ----
  window._syncCustomize = function(state){
    custEnabled  = state.enabled;
    custOverrides = state.overrides || {};
    renderAll();
  };

  function send(obj){ window.webkit.messageHandlers.customize.postMessage(JSON.stringify(obj)); }

  function custToggle(){
    send({action:'customize:toggle'});
    // Optimistic local update while Swift round-trips
    custEnabled = !custEnabled;
    renderAll();
  }
  window.custToggle = custToggle;

  function custSetCat(app, catId){
    custOverrides[app] = catId;
    send({action:'customize:set', app, cat:catId});
    selectedApp = null;
    renderAll();
  }
  window.custSetCat = custSetCat;

  function custRemove(app){
    delete custOverrides[app];
    send({action:'customize:remove', app});
    if(selectedApp===app) selectedApp=null;
    renderAll();
  }
  window.custRemove = custRemove;

  // ---- Search / dropdown ----
  let lastQuery = '';
  function custSearch(q){
    lastQuery = q;
    renderDropdown(q);
  }
  window.custSearch = custSearch;

  function custSelect(name){
    selectedApp = name;
    // Clear search box + close dropdown
    const inp = document.getElementById('cust-inp');
    if(inp){ inp.value = ''; }
    lastQuery = '';
    renderAll();
  }
  window.custSelect = custSelect;

  function closeDropdown(){ lastQuery=''; renderDropdown(''); }
  window.custCloseDD = closeDropdown;

  function renderDropdown(q){
    const dd = document.getElementById('cust-dd');
    if(!dd) return;
    const trimmed = q.trim().toLowerCase();
    if(!trimmed){ dd.classList.remove('open'); dd.innerHTML=''; return; }

    const matches = knownApps
      .filter(a => a.n.toLowerCase().includes(trimmed))
      .slice(0, 6);

    if(!matches.length){ dd.classList.remove('open'); dd.innerHTML=''; return; }

    const esc = s => (''+s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    dd.innerHTML = matches.map(a => {
      const effCat = custOverrides[a.n] !== undefined ? custOverrides[a.n] : a.c;
      const meta   = catOf(effCat);
      return '<div class="cust-ddi" onclick="custSelect('+JSON.stringify(esc(a.n))+')">'+
        '<span class="ddi-name">'+esc(a.n)+'</span>'+
        '<span class="ddi-cat" style="background:'+meta.bg+';color:'+meta.color+'">'+meta.label+'</span>'+
      '</div>';
    }).join('');
    dd.classList.add('open');
  }

  // ---- Render ----
  function renderAll(){
    // Toggle pill
    tog.textContent = custEnabled ? 'ON' : 'OFF';
    tog.className   = 'ctog ' + (custEnabled ? 'on' : 'off');

    if(!custEnabled){
      body.innerHTML = '<div class="cust-off-note">Category overrides are off — everything uses default classification.</div>';
      return;
    }

    const esc = s => (''+s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');

    // Search input (preserved value)
    let html = '<div class="cust-search">'+
      '<input id="cust-inp" type="text" placeholder="Search apps &amp; sites you\'ve visited…" '+
        'oninput="custSearch(this.value)" onkeydown="if(event.key===\'Escape\')custCloseDD()" '+
        'autocomplete="off" value="'+esc(lastQuery)+'">'+
      '<div class="cust-dd" id="cust-dd"></div>'+
    '</div>';

    // Picker — shown when an app is selected via the dropdown
    if(selectedApp !== null){
      const curCat = custOverrides[selectedApp] !== undefined ? custOverrides[selectedApp] : -1;
      html += '<div class="cust-picker-wrap">'+
        '<div class="cust-picker-label">Set category for <b>'+esc(selectedApp)+'</b></div>'+
        '<div class="cust-picker">'+
          CATS.map(c =>
            '<button class="cat-btn'+(c.id===curCat?' sel':'')+'" '+
              'style="background:'+c.bg+';border-color:'+(c.id===curCat?c.color:'rgba(255,255,255,.12)')+'" '+
              'onclick="custSetCat('+JSON.stringify(esc(selectedApp))+','+c.id+')">'+
              c.label+
            '</button>'
          ).join('')+
        '</div>'+
      '</div>';
    }

    // Chips — only explicitly customized apps
    const entries = Object.keys(custOverrides);
    if(entries.length){
      html += '<div class="cust-chips">'+
        entries.map(app => {
          const meta = catOf(custOverrides[app]);
          return '<div class="cust-chip">'+
            '<span class="cc-dot" style="background:'+meta.color+'"></span>'+
            '<span>'+esc(app)+'</span>'+
            '<span style="font-size:11px;color:'+meta.color+';opacity:.8;margin-left:2px">'+meta.label+'</span>'+
            '<span class="cc-x" onclick="custRemove('+JSON.stringify(esc(app))+')">×</span>'+
          '</div>';
        }).join('')+
      '</div>';
    } else {
      html += '<div class="cust-off-note" style="margin-top:8px">No overrides set yet. Search for an app above to customize it.</div>';
    }

    body.innerHTML = html;

    // Re-run the dropdown if there was an active query (e.g. after a chip removal)
    if(lastQuery){ renderDropdown(lastQuery); }

    // After re-render, focus the input if picker is open so UX stays fluid
    if(selectedApp === null){
      const inp = document.getElementById('cust-inp');
      if(inp) inp.focus();
    }
  }

  // Close dropdown when clicking elsewhere
  document.addEventListener('click', e => {
    if(!e.target.closest('#cust-dd') && !e.target.closest('#cust-inp')) closeDropdown();
  });

  renderAll();
})();

$('gen').textContent=new Date().toLocaleString();
</script>
</body>
</html>
"""#
    }
}

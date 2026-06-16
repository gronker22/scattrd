import Foundation

struct Villain: Codable {
    let valid: Bool
    let app: String
    let switchIns: Int
    let pct: Int            // % of all context switches this month
    let totalSwitches: Int
    let runnerUp: String
    let runnerUpPct: Int
    let periodLabel: String
    let tie: Bool           // top two within ~1pt — no clear winner
}

/// "App Villain of the Month" — the app you switched *into* most (a communication
/// or distraction app), as a share of all your context switches. 100% local.
enum VillainAnalysis {
    static func detect(store: Database, now: Date = Date()) -> Villain {
        let lf = DateFormatter(); lf.dateFormat = "MMMM yyyy"
        let label = lf.string(from: now)

        // Shared aggregation, so "total context switches" matches the Wrapped tab exactly.
        let stats = ContextSwitches.forMonth(store: store, now: now)
        // A villain is a nameable distraction destination (a neutral browser isn't a "villain").
        let distractions = stats.perApp.filter { $0.category == .distraction }

        guard stats.total > 0, let top = distractions.first else {
            return Villain(valid: false, app: "—", switchIns: 0, pct: 0, totalSwitches: stats.total,
                           runnerUp: "—", runnerUpPct: 0, periodLabel: label, tie: false)
        }
        let topPct = Double(top.count) / Double(stats.total) * 100
        let runner = distractions.count > 1 ? distractions[1] : nil
        let runnerPct = runner.map { Double($0.count) / Double(stats.total) * 100 } ?? 0
        // Bug 3: top two within 1 percentage point → it's a near-tie, not a clear winner.
        let tie = runner != nil && isNearTie(top: top.count, runner: runner!.count, total: stats.total)

        return Villain(valid: true, app: top.app, switchIns: top.count,
                       pct: Int(topPct.rounded()), totalSwitches: stats.total,
                       runnerUp: runner?.app ?? "—", runnerUpPct: Int(runnerPct.rounded()),
                       periodLabel: label, tie: tie)
    }

    /// Top two within <1 percentage point of all context switches → a near-tie.
    static func isNearTie(top: Int, runner: Int, total: Int) -> Bool {
        guard total > 0 else { return false }
        return Double(top - runner) / Double(total) * 100 < 1.0
    }

    static func cardHTML(store: Database, now: Date = Date()) -> String {
        let v = detect(store: store, now: now)
        let json = (try? JSONEncoder().encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return template(json: json)
    }

    private static func template(json: String) -> String {
        return #"""
<!doctype html><html><head><meta charset="utf-8"><style>
  :root{--text:#f3eef0;--muted:#a99aa0}
  *{margin:0;box-sizing:border-box}
  html,body{width:480px;height:720px;overflow:hidden;background:#0c0709;color:var(--text);
    font:14px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
  .aurora{position:absolute;inset:-20%;z-index:0;filter:blur(85px);opacity:.55}
  .aurora span{position:absolute;border-radius:50%;mix-blend-mode:screen}
  .a1{background:#e0586a;width:62%;height:62%;top:-10%;left:-8%}
  .a2{background:#7c3aed;width:58%;height:58%;bottom:-12%;right:-8%}
  .a3{background:#fb7185;width:40%;height:40%;top:40%;left:36%;opacity:.5}
  .wrap{position:relative;z-index:1;padding:36px 32px 30px;height:100%;display:flex;flex-direction:column;align-items:center;text-align:center}
  .brand{align-self:flex-start;display:flex;align-items:center;gap:8px;font-weight:700;font-size:15px}
  .brand .dot{width:10px;height:10px;border-radius:50%;background:linear-gradient(135deg,#e0586a,#7c3aed)}
  .eyebrow{margin-top:30px;font-size:11px;letter-spacing:.3em;text-transform:uppercase;color:#fb7185;font-weight:700}
  .period{font-size:14px;color:var(--muted);margin-top:6px;letter-spacing:.04em}
  .mug{margin-top:26px;width:128px;height:128px;border-radius:50%;display:flex;align-items:center;justify-content:center;
    font-size:62px;background:rgba(224,88,106,.14);border:2px solid rgba(251,113,133,.5);box-shadow:0 0 40px -8px rgba(224,88,106,.6)}
  .vmug{width:86px;height:86px;object-fit:contain}
  .vname{margin-top:20px;font-size:42px;font-weight:820;letter-spacing:-.02em;line-height:1.05;
    background:linear-gradient(120deg,#fb7185,#f43f5e);background-clip:text;-webkit-background-clip:text;-webkit-text-fill-color:transparent;
    max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .charge{margin-top:14px;font-size:17px;font-weight:600;line-height:1.4;max-width:320px}
  .charge b{color:#fb7185}
  .stats{margin-top:auto;width:100%;display:flex;gap:12px}
  .stat{flex:1;background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.09);border-radius:14px;padding:14px 10px}
  .stat .n{font-size:22px;font-weight:760}
  .stat .l{font-size:10.5px;color:var(--muted);margin-top:2px}
  .runner{margin-top:14px;font-size:12.5px;color:var(--muted)}
  .runner b{color:var(--text)}
  .foot{margin-top:16px;font-size:11px;color:var(--muted)}
  .empty{margin:auto;color:var(--muted);font-size:15px;line-height:1.6;padding:0 30px}
</style></head><body>
<div class="aurora"><span class="a1"></span><span class="a2"></span><span class="a3"></span></div>
<div class="wrap" id="root"></div>
<script>
const V = \#(json);
const root=document.getElementById('root');
const brand='<div class="brand"><span class="dot"></span>scattrd</div>';
if(!V.valid){
  root.innerHTML=brand+'<div class="empty">No villain yet for <b>'+V.periodLabel+'</b>.<br><br>Once you log some app-switching, your monthly villain will be exposed here.</div>';
} else {
  const eyebrow = V.tie ? 'Joint Villains' : 'App Villain';
  const charge = V.tie
    ? 'neck-and-neck with <b>'+V.runnerUp+'</b> — both ~<b>'+V.pct+'%</b> of your context switches'
    : 'caused <b>'+V.pct+'%</b> of your context switches this month';
  root.innerHTML = brand +
    '<div class="eyebrow">'+eyebrow+'</div>'+
    '<div class="period">'+V.periodLabel+'</div>'+
    '<div class="mug"><img class="vmug" src="data:image/png;base64,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"></div>'+
    '<div class="vname">'+V.app+'</div>'+
    '<div class="charge">'+charge+'</div>'+
    '<div class="stats">'+
      '<div class="stat"><div class="n">'+V.switchIns.toLocaleString()+'</div><div class="l">times you switched to it</div></div>'+
      '<div class="stat"><div class="n">'+V.totalSwitches.toLocaleString()+'</div><div class="l">total context switches</div></div>'+
    '</div>'+
    (!V.tie && V.runnerUp!=='—'?'<div class="runner">Runner-up: <b>'+V.runnerUp+'</b> ('+V.runnerUpPct+'%)</div>':'')+
    '<div class="foot">🔒 Tracked privately on this Mac · scattrd</div>';
}
</script></body></html>
"""#
    }
}

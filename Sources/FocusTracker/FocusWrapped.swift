import Foundation

enum WrappedPeriod { case month, year }

/// Aggregated highlights for a Focus Wrapped card (monthly or annual).
struct WrappedData: Codable {
    let periodLabel: String
    let hasData: Bool
    let activeHours: Double
    let deepWorkHours: Double
    let totalSwitches: Int
    let bestDayLabel: String
    let bestDayScore: Int
    let longestStreakMin: Int
    let longestStreakDay: String
    let peakHour: String
    let worstDayLabel: String
    let worstDayApp: String
}

enum FocusWrapped {

    static func cardHTML(store: Database, period: WrappedPeriod, now: Date = Date()) -> String {
        let data = compute(store: store, period: period, now: now)
        let json = (try? JSONEncoder().encode(data)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return template(json: json)
    }

    // MARK: - Aggregation

    static func compute(store: Database, period: WrappedPeriod, now: Date = Date()) -> WrappedData {
        let cal = Calendar.current
        let start: Date
        let label: String
        let lf = DateFormatter()
        if period == .month {
            start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            lf.dateFormat = "MMMM yyyy"
        } else {
            start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            lf.dateFormat = "yyyy"
        }
        label = lf.string(from: now)

        let dayFmt = DateFormatter(); dayFmt.dateFormat = "EEE, MMM d"
        var day = cal.startOfDay(for: start)
        let today = cal.startOfDay(for: now)

        var anyData = false
        var bestScore = -1, bestDay = today
        var worstDistSec = 0.0, worstDay = today, worstApp = ""
        var longestBlock = 0.0, longestDay = today
        var totalActiveSec = 0.0, totalDeepSec = 0.0
        var hourActive = [Double](repeating: 0, count: 24)
        var hourDeep = [Double](repeating: 0, count: 24)

        while day <= today {
            let (s, e) = dayBounds(for: day)
            let st = FocusScore.analyze(store.sessions(from: s, to: e))
            if st.hasEnoughData {
                anyData = true
                if st.score > bestScore { bestScore = st.score; bestDay = day }

                let distSec = st.blocks.filter { $0.category == .distraction }.reduce(0) { $0 + $1.duration }
                if distSec > worstDistSec {
                    worstDistSec = distSec; worstDay = day
                    worstApp = st.topDistractions.first?.app ?? ""
                }

                totalActiveSec += st.activeMinutes * 60

                for b in st.blocks {
                    if b.category == .deepWork { totalDeepSec += b.duration }
                    distributeHours(b, active: &hourActive, deep: &hourDeep)
                }
                // "Longest deep-work streak" uses the shared deep-work-block definition,
                // so it can't credit a long neutral block as deep work.
                for b in FocusScore.deepWorkBlocks(in: st.blocks) where b.duration > longestBlock {
                    longestBlock = b.duration; longestDay = day
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let hours = hourDeep.reduce(0, +) > 0 ? hourDeep : hourActive
        let peakIdx = hours.indices.max(by: { hours[$0] < hours[$1] }) ?? 9
        let peak = (anyData && hours[peakIdx] > 0) ? hourRange(peakIdx) : "—"

        // Shared aggregation — the exact number the Villain tab shows too.
        let totalSwitches = ContextSwitches.forRange(store: store, from: start, to: now).total

        return WrappedData(
            periodLabel: label,
            hasData: anyData,
            activeHours: totalActiveSec / 3600,
            deepWorkHours: totalDeepSec / 3600,
            totalSwitches: totalSwitches,
            bestDayLabel: anyData ? dayFmt.string(from: bestDay) : "—",
            bestDayScore: max(0, bestScore),
            longestStreakMin: Int((longestBlock / 60).rounded()),
            longestStreakDay: longestBlock > 0 ? dayFmt.string(from: longestDay) : "—",
            peakHour: peak,
            worstDayLabel: worstDistSec > 0 ? dayFmt.string(from: worstDay) : "—",
            worstDayApp: worstApp.isEmpty ? "—" : worstApp
        )
    }

    private static func distributeHours(_ b: FocusSession, active: inout [Double], deep: inout [Double]) {
        let cal = Calendar.current
        var t = b.start
        while t < b.end {
            let d = Date(timeIntervalSince1970: t)
            let hour = cal.component(.hour, from: d)
            let hourStart = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: d))?
                .timeIntervalSince1970 ?? t
            let chunkEnd = min(b.end, hourStart + 3600)
            if chunkEnd <= t { break }
            let dur = chunkEnd - t
            if (0..<24).contains(hour) {
                active[hour] += dur
                if b.category == .deepWork { deep[hour] += dur }
            }
            t = chunkEnd
        }
    }

    private static func hourRange(_ h: Int) -> String {
        func fmt(_ hr: Int) -> String {
            let hh = hr % 24
            let disp = hh % 12 == 0 ? 12 : hh % 12
            return "\(disp)\(hh < 12 ? "am" : "pm")"
        }
        return "\(fmt(h))–\(fmt(h + 1))"
    }

    // MARK: - Card (480×720 portrait, exported as an image)

    private static func template(json: String) -> String {
        return #"""
<!doctype html><html><head><meta charset="utf-8"><style>
  :root{--text:#eef0f6;--muted:#9aa0b4}
  *{margin:0;box-sizing:border-box}
  html,body{width:480px;height:720px;overflow:hidden;background:#0a0c12;color:var(--text);
    font:14px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
  .aurora{position:absolute;inset:-20%;z-index:0;filter:blur(80px);opacity:.55}
  .aurora span{position:absolute;width:60%;height:60%;border-radius:50%;mix-blend-mode:screen}
  .a1{background:#5b8cff;top:-8%;left:-6%}
  .a2{background:#a855f7;bottom:-10%;right:-6%}
  .a3{background:#22d3ee;top:36%;left:38%;width:42%;height:42%;opacity:.6}
  .wrap{position:relative;z-index:1;padding:36px 32px 30px;height:100%;display:flex;flex-direction:column}
  .brand{display:flex;align-items:center;gap:8px;font-weight:700;font-size:15px}
  .brand .dot{width:10px;height:10px;border-radius:50%;background:linear-gradient(135deg,#5b8cff,#a855f7)}
  .eyebrow{margin-top:24px;font-size:11px;letter-spacing:.24em;text-transform:uppercase;color:var(--muted);font-weight:600}
  .period{font-size:36px;font-weight:790;letter-spacing:-.02em;margin-top:4px;
    background:linear-gradient(120deg,#fff,#a78bfa);background-clip:text;-webkit-background-clip:text;-webkit-text-fill-color:transparent}
  .hero{margin-top:22px}
  .hero .big{font-size:62px;font-weight:800;letter-spacing:-.03em;line-height:1;
    background:linear-gradient(135deg,#5b8cff,#22d3ee);background-clip:text;-webkit-background-clip:text;-webkit-text-fill-color:transparent}
  .hero .lbl{font-size:13px;color:var(--muted);margin-top:5px}
  .stats{margin-top:auto;display:flex;flex-direction:column;gap:9px}
  .row{display:flex;align-items:center;gap:13px;background:rgba(255,255,255,.05);
    border:1px solid rgba(255,255,255,.09);border-radius:14px;padding:12px 14px}
  .row .ico{font-size:18px;width:22px;text-align:center}
  .row .meta{flex:1;min-width:0}
  .row .k{font-size:11px;color:var(--muted)}
  .row .v{font-size:15px;font-weight:650;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .foot{margin-top:18px;font-size:11px;color:var(--muted);text-align:center}
  .empty{margin:auto;text-align:center;color:var(--muted);font-size:15px;line-height:1.6;padding:0 28px}
</style></head><body>
<div class="aurora"><span class="a1"></span><span class="a2"></span><span class="a3"></span></div>
<div class="wrap" id="root"></div>
<script>
const D = \#(json);
const root = document.getElementById('root');
const comma = n => n.toLocaleString();
const brand = '<div class="brand"><span class="dot"></span>scattrd</div>';
if(!D.hasData){
  root.innerHTML = brand + '<div class="empty">Not enough focus data for <b>'+D.periodLabel+'</b> yet.<br><br>Keep scattrd running and your Wrapped will fill in.</div>';
} else {
  const rows = [
    ['🏆','Best focus day', D.bestDayLabel+' · '+D.bestDayScore+'/100'],
    ['🔥','Longest deep-work streak', D.longestStreakMin+' min · '+D.longestStreakDay],
    ['⏰','Most productive hour', D.peakHour],
    ['🌀','Worst distraction day', D.worstDayLabel+(D.worstDayApp!=='—'?' · '+D.worstDayApp:'')],
    ['↔','Total context switches', comma(D.totalSwitches)],
  ];
  root.innerHTML = brand +
    '<div class="eyebrow">Focus Wrapped</div>'+
    '<div class="period">'+D.periodLabel+'</div>'+
    '<div class="hero"><div class="big">'+D.activeHours.toFixed(1)+'h</div>'+
    '<div class="lbl">of focus tracked'+(D.deepWorkHours>=0.5?' · '+D.deepWorkHours.toFixed(1)+'h deep work':'')+'</div></div>'+
    '<div class="stats">'+rows.map(r=>'<div class="row"><div class="ico">'+r[0]+'</div><div class="meta"><div class="k">'+r[1]+'</div><div class="v">'+r[2]+'</div></div></div>').join('')+'</div>'+
    '<div class="foot">🔒 Tracked privately on this Mac · scattrd</div>';
}
</script></body></html>
"""#
    }
}

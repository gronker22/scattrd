import AppKit
import WebKit

/// Owns the menubar status item. Left-click opens a premium NSPopover panel
/// (a compact WKWebView that mirrors the dashboard's look); right-click shows a
/// tiny fallback menu. The panel talks back to Swift via a script-message bridge.
final class MenuBarController: NSObject, WKScriptMessageHandler {
    private let statusItem: NSStatusItem
    private let store: Database

    var onPauseToggle: ((Bool) -> Void)?
    var onSendTestSummary: (() -> Void)?
    var onOpenDashboard: (() -> Void)?
    var onOpenWrapped: (() -> Void)?
    private var isPaused = false
    private var justBlocked = false

    private let popover = NSPopover()
    private var webView: WKWebView!
    private var eventMonitor: Any?
    private var snapWindow: NSWindow?
    private var snapWebView: WKWebView?

    init(store: Database) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildPopover()
        if let b = statusItem.button {
            b.action = #selector(statusClicked)
            b.target = self
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshTitle()
    }

    // MARK: - Status bar title (every tick)

    func refreshTitle() {
        guard let button = statusItem.button else { return }
        let stats = FocusScore.today(store)
        button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "scattrd")
        button.imagePosition = .imageLeading
        if stats.hasEnoughData {
            button.attributedTitle = NSAttributedString(string: " \(stats.score)",
                attributes: [.foregroundColor: Self.color(for: stats.score),
                             .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)])
        } else {
            button.attributedTitle = NSAttributedString(string: " –",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        }
    }

    static func color(for score: Int) -> NSColor {
        switch score {
        case 70...: return .systemGreen
        case 40..<70: return .systemOrange
        default: return .systemRed
        }
    }

    // MARK: - Popover

    private func buildPopover() {
        let ucc = WKUserContentController()
        ucc.add(self, name: "act")
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ucc

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 344, height: 770), configuration: cfg)
        if #available(macOS 12.0, *) {
            wv.underPageBackgroundColor = NSColor(red: 0.04, green: 0.045, blue: 0.06, alpha: 1)
        }
        webView = wv

        let vc = NSViewController()
        vc.view = wv
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: 344, height: 770)
        popover.behavior = .applicationDefined   // we manage closing via an event monitor
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)   // keep the popover chrome dark, not white
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false) {
            showFallbackMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() { popover.isShown ? closePopover() : showPopover() }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        justBlocked = false
        webView.loadHTMLString(panelHTML(), baseURL: nil)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    private func reloadPanel() { webView.loadHTMLString(panelHTML(), baseURL: nil) }

    /// Test helper: render the popover panel to a PNG.
    func snapshotPanel(_ completion: @escaping (String) -> Void) {
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 344, height: 770))
        snapWebView = wv
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 344, height: 770),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = wv
        win.alphaValue = 0.02
        win.orderFront(nil)
        snapWindow = win
        wv.loadHTMLString(panelHTML(), baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            let cfg = WKSnapshotConfiguration(); cfg.afterScreenUpdates = true
            wv.takeSnapshot(with: cfg) { image, _ in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("scattrd-panel-test.png")
                if let image {
                    var rect = CGRect(origin: .zero, size: image.size)
                    if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                       let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                        try? png.write(to: url)
                    }
                }
                win.close()
                completion(url.path)
            }
        }
    }

    private func showFallbackMenu() {
        let menu = NSMenu()
        let dash = NSMenuItem(title: "Open Dashboard…", action: #selector(fmDashboard), keyEquivalent: "")
        dash.target = self; menu.addItem(dash)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit scattrd", action: #selector(fmQuit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        if let b = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height + 5), in: b)
        }
    }
    @objc private func fmDashboard() { onOpenDashboard?() }
    @objc private func fmQuit() { NSApp.terminate(nil) }

    // MARK: - JS → Swift bridge

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let action = message.body as? String else { return }

        // Custom-scheduled Deep Work block: "blockAt:<startUnix>:<endUnix>".
        if action.hasPrefix("blockAt:") {
            let comps = action.dropFirst("blockAt:".count).split(separator: ":")
            if comps.count == 2, let s = Double(comps[0]), let e = Double(comps[1]), e > s {
                scheduleDeepWork(start: Date(timeIntervalSince1970: s), end: Date(timeIntervalSince1970: e))
            }
            return
        }

        switch action {
        case "dashboard": closePopover(); onOpenDashboard?()
        case "wrapped":   closePopover(); onOpenWrapped?()
        case "test":      onSendTestSummary?()
        case "pause":     isPaused.toggle(); onPauseToggle?(isPaused); reloadPanel()
        case "login":     LoginItem.setEnabled(!LoginItem.isEnabled); reloadPanel()
        case "tabs":
            Settings.tabTrackingEnabled.toggle()
            if Settings.tabTrackingEnabled { BrowserTabReader.resetPermissionCache() }
            reloadPanel()
        case "nudge":     Settings.nudgeEnabled.toggle(); reloadPanel()
        case "calendar":
            Settings.calendarEnabled.toggle()
            if Settings.calendarEnabled { CalendarService.shared.requestAccess { [weak self] _ in self?.reloadPanel() } }
            reloadPanel()
        case "blockIt":
            // Fallback: block the suggested forecast window (used if the picker
            // ever can't supply times). Custom times come via "blockAt:".
            let f = FocusForecast.compute(store: store)
            scheduleDeepWork(start: f.blockStart, end: f.blockEnd)
        case "goalUp":    Settings.streakThreshold += 5; reloadPanel()
        case "goalDown":  Settings.streakThreshold -= 5; reloadPanel()
        case "streakSeen": Settings.streakJustBroke = false   // clear after the break animation plays
        case "quit":      NSApp.terminate(nil)
        default: break
        }
        refreshTitle()
    }

    /// Creates a Deep Work calendar block for an explicit window, requesting
    /// Calendar access first if needed, then refreshes the panel so the new
    /// block shows up in the "already scheduled" list.
    private func scheduleDeepWork(start: Date, end: Date) {
        let create = { [weak self] in
            guard let self else { return }
            self.justBlocked = CalendarService.shared.createDeepWorkBlock(start: start, end: end)
            self.reloadPanel()
        }
        if CalendarService.shared.isAuthorized {
            create()
        } else {
            CalendarService.shared.requestAccess { granted in
                if granted { Settings.calendarEnabled = true; create() }
                else { self.reloadPanel() }
            }
        }
    }

    // MARK: - Summary (opened from a notification tap)

    @objc func presentSummary() {
        let s = FocusScore.today(store)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = s.hasEnoughData ? "Today's Focus: \(s.score)/100" : "Not enough data yet"
        alert.informativeText = s.hasEnoughData ? scoreVerdict(s.score) : "Keep working — your score appears after ~5 minutes."
        alert.addButton(withTitle: "Open Dashboard")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn { onOpenDashboard?() }
    }

    private func scoreVerdict(_ score: Int) -> String {
        switch score {
        case 80...: return "Deep, sustained focus 🧘"
        case 60..<80: return "Solid focus with some breaks"
        case 40..<60: return "Fragmented — lots of switching"
        default: return "Heavily scattered today"
        }
    }

    // MARK: - Panel HTML

    /// True only in debug builds. build_app.sh ships `swiftc -O` (no -DDEBUG),
    /// so this is false in production — keeping dev-only controls out of the menu.
    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private func panelHTML() -> String {
        let s = FocusScore.today(store)
        let dists = s.topDistractions.prefix(3).map {
            ["app": $0.app, "ints": $0.switchIns] as [String: Any]
        }
        let threshold = Settings.streakThreshold
        let fc = FocusForecast.compute(store: store)

        // Picker defaults come from the suggested forecast window; the user can
        // edit day/start/end before scheduling. Formats are local-time and match
        // the <input type="date"|"time"> value formats.
        let dFmt = DateFormatter(); dFmt.dateFormat = "yyyy-MM-dd"
        let tFmt = DateFormatter(); tFmt.dateFormat = "HH:mm"
        let lFmt = DateFormatter(); lFmt.dateFormat = "EEE MMM d · h:mm"
        let l2Fmt = DateFormatter(); l2Fmt.dateFormat = "h:mma"

        // Already-scheduled scattrd blocks (persist across reopen/relaunch).
        let blocks = CalendarService.shared.upcomingDeepWorkBlocks().map { b -> String in
            "\(lFmt.string(from: b.start))–\(l2Fmt.string(from: b.end).lowercased())"
        }

        let obj: [String: Any] = [
            "hasData": s.hasEnoughData, "score": s.score, "verdict": scoreVerdict(s.score),
            "switches": s.switches, "avg": s.avgFocusMinutes, "longest": s.longestFocusMinutes,
            "deep": s.deepWorkBlocks,
            "dists": dists,
            "tabsOn": Settings.tabTrackingEnabled, "loginOn": LoginItem.isEnabled, "paused": isPaused,
            "nudgeOn": Settings.nudgeEnabled,
            "debug": Self.isDebugBuild,
            "calOn": Settings.calendarEnabled,
            "fcValid": fc.valid, "fcText": fc.headline, "fcBlock": fc.blockLabel,
            "fcDefDate": dFmt.string(from: fc.blockStart),
            "fcDefStart": tFmt.string(from: fc.blockStart),
            "fcDefEnd": tFmt.string(from: fc.blockEnd),
            "fcMinDate": dFmt.string(from: Date()),
            "fcBlocks": blocks,
            "streak": FocusStreak.current(store: store, threshold: threshold),
            "streakBest": FocusStreak.best(store: store, threshold: threshold),
            "streakGoal": threshold,
            "streakBroke": Settings.streakJustBroke,
            "streakBrokeLen": Settings.brokenStreakLength,
        ]
        let json = (try? JSONSerialization.data(withJSONObject: obj))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return Self.panelTemplate(json: json)
    }

    private static func panelTemplate(json: String) -> String {
        return #"""
<!doctype html><html><head><meta charset="utf-8">
<style>
  :root{--text:#eef0f6;--muted:#8b93a8;--card:rgba(255,255,255,.05);--brd:rgba(255,255,255,.10);
    --green:#34d399;--amber:#fbbf24;--red:#fb7185;--gray:#5b6478}
  *{box-sizing:border-box;margin:0}
  html,body{background:#0c0e13;color:var(--text);
    font:13px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
  body{padding:15px 15px 13px}
  .glass{background:var(--card);border:1px solid var(--brd);border-radius:13px}
  .hd{display:flex;align-items:center;gap:13px;margin-bottom:13px}
  .ring{position:relative;width:64px;height:64px;flex:0 0 auto}
  .ring .v{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:21px;font-weight:740}
  .hd .vd{font-size:14.5px;font-weight:670;letter-spacing:-.01em}
  .hd .tdy{font-size:11px;color:var(--muted);margin-top:1px}
  .grid{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:12px}
  .cell{padding:9px 11px}
  .cell .n{font-size:17px;font-weight:720;font-variant-numeric:tabular-nums}
  .cell .l{font-size:10.5px;color:var(--muted);margin-top:1px}
  .sec{font-size:10px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);font-weight:650;margin:2px 2px 7px}
  .drow{display:flex;justify-content:space-between;font-size:12px;padding:4px 2px}
  .drow .dm{color:var(--muted)}
  .empty{color:var(--muted);font-size:12px;padding:3px 2px 8px}
  .tog{display:flex;align-items:center;justify-content:space-between;padding:9px 11px;margin-bottom:7px;cursor:pointer;transition:.15s}
  .tog:hover{border-color:rgba(255,255,255,.2)}
  .tog .t{font-size:12.5px;font-weight:540}
  .pill{font-size:10.5px;font-weight:680;padding:3px 9px;border-radius:20px}
  .on{background:rgba(52,211,153,.16);color:#34d399}
  .off{background:rgba(255,255,255,.07);color:var(--muted)}
  .btns{margin-top:12px;display:flex;flex-direction:column;gap:7px}
  button{font:inherit;font-weight:600;border:0;border-radius:11px;padding:10px;cursor:pointer;transition:.15s;color:var(--text)}
  .primary{background:linear-gradient(180deg,#5b8cff,#4f6ef0);box-shadow:0 6px 18px -8px rgba(91,140,255,.8)}
  .primary:hover{filter:brightness(1.08)}
  .ghost{background:var(--card);border:1px solid var(--brd)}
  .ghost:hover{border-color:rgba(255,255,255,.22)}
  .quit{background:transparent;color:var(--muted);font-weight:540;padding:6px}
  .quit:hover{color:var(--red)}
  .streak{display:flex;align-items:center;gap:11px;padding:11px 13px;margin-bottom:12px;border-radius:13px;
    background:linear-gradient(135deg,rgba(251,146,60,.16),rgba(251,113,133,.05));border:1px solid rgba(251,146,60,.28)}
  .streak.broke{background:linear-gradient(135deg,rgba(251,113,133,.20),rgba(120,80,90,.06));border-color:rgba(251,113,133,.42)}
  .sflame{font-size:26px;line-height:1;flex:0 0 auto}
  .smeta{flex:1;min-width:0}
  .snum{font-size:20px;font-weight:760;letter-spacing:-.02em}
  .snum .su{font-size:12px;font-weight:600;color:var(--muted)}
  .ssub{font-size:11px;color:var(--muted);margin-top:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .goal{display:flex;align-items:center;gap:5px;flex:0 0 auto}
  .goal .gl{font-size:10px;color:var(--muted);margin-right:2px}
  .gb{width:22px;height:21px;padding:0;font-size:14px;line-height:1;border-radius:7px;background:var(--card);border:1px solid var(--brd);color:var(--text)}
  .gb:hover{border-color:rgba(255,255,255,.28)}
  @keyframes shatter{0%{transform:translateX(0)}15%{transform:translateX(-6px) rotate(-1deg)}30%{transform:translateX(6px) rotate(1deg)}45%{transform:translateX(-4px)}60%{transform:translateX(4px)}75%{transform:translateX(-2px)}100%{transform:translateX(0)}}
  .streak.shatter{animation:shatter .6s cubic-bezier(.36,.07,.19,.97)}
  .fcast{padding:11px 13px;margin-bottom:12px;border-radius:13px;
    background:linear-gradient(135deg,rgba(91,140,255,.16),rgba(168,85,247,.06));border:1px solid rgba(91,140,255,.3)}
  .fc-hd{font-size:10px;letter-spacing:.12em;text-transform:uppercase;color:#9db4ff;font-weight:650}
  .fc-body{font-size:12px;margin:4px 0 9px;line-height:1.4}
  .fc-btn{width:100%;padding:8px;border-radius:9px;background:rgba(91,140,255,.92);border:0;color:#fff;font:inherit;font-weight:600;cursor:pointer;font-size:12px}
  .fc-btn:hover{filter:brightness(1.1)}
  .fc-ok{font-size:12px;color:#34d399;font-weight:600;text-align:center;padding:5px 6px}
  .fc-blocks{margin:2px 0 10px;display:flex;flex-direction:column;gap:3px}
  .fc-sched{display:flex;flex-direction:column;gap:7px}
  .fc-fl{font-size:10px;color:var(--muted);font-weight:600;display:block;margin-bottom:3px}
  .fc-in{width:100%;padding:6px 8px;border-radius:8px;background:rgba(255,255,255,.06);
    border:1px solid var(--brd);color:var(--text);font:inherit;font-size:12px;color-scheme:dark}
  .fc-in:focus{outline:none;border-color:rgba(255,255,255,.28)}
  .fc-times{display:flex;gap:8px}
  .fc-times>div{flex:1}
  .fc-err{font-size:11px;color:#fb7185;min-height:13px;line-height:1.1}
</style></head>
<body>
<div id="root"></div>
<script>
const P = \#(json);
const send = a => window.webkit.messageHandlers.act.postMessage(a);
const band = s => s>=70?'#34d399':s>=40?'#fbbf24':'#fb7185';
const fmt = m => m>=10?Math.round(m):Math.round(m*10)/10;
function ring(){
  const s=P.hasData?P.score:0,r=27,c=2*Math.PI*r,col=P.hasData?band(s):'#5b6478';
  return '<div class="ring"><svg width="64" height="64" style="transform:rotate(-90deg)">'+
    '<circle cx="32" cy="32" r="'+r+'" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="6"/>'+
    '<circle cx="32" cy="32" r="'+r+'" fill="none" stroke="'+col+'" stroke-width="6" stroke-linecap="round" '+
    'stroke-dasharray="'+c+'" stroke-dashoffset="'+(c*(1-(P.hasData?s/100:0)))+'"/></svg>'+
    '<div class="v" style="color:'+col+'">'+(P.hasData?s:'–')+'</div></div>';
}
function cell(n,l){return '<div class="glass cell"><div class="n">'+n+'</div><div class="l">'+l+'</div></div>';}
function tog(label,on,act){return '<div class="glass tog" onclick="send(\''+act+'\')"><div class="t">'+label+'</div>'+
  '<div class="pill '+(on?'on':'off')+'">'+(on?'ON':'OFF')+'</div></div>';}
let dl='';
if(P.dists.length){ dl=P.dists.map(d=>'<div class="drow"><span>'+d.app+'</span><span class="dm">'+d.ints+'×</span></div>').join(''); }
else { dl='<div class="empty">'+(P.hasData?'None — nicely focused 👏':'—')+'</div>'; }
function streakBanner(){
  const goal='<div class="goal"><span class="gl">goal ≥'+P.streakGoal+'</span>'+
    '<button class="gb" onclick="send(\'goalDown\')">−</button><button class="gb" onclick="send(\'goalUp\')">+</button></div>';
  if(P.streakBroke){
    return '<div class="streak broke" id="streakEl"><div class="sflame">💔</div>'+
      '<div class="smeta"><div class="snum">'+P.streakBrokeLen+'-day streak ended</div><div class="ssub">start a new one today</div></div>'+goal+'</div>';
  }
  return '<div class="streak" id="streakEl"><div class="sflame">'+(P.streak>0?'🔥':'·')+'</div>'+
    '<div class="smeta"><div class="snum">'+P.streak+' <span class="su">day'+(P.streak===1?'':'s')+'</span></div>'+
    '<div class="ssub">'+(P.streak>0?'focus streak · best '+P.streakBest:'no streak yet · best '+P.streakBest)+'</div></div>'+goal+'</div>';
}
function forecastCard(){
  // Already-scheduled scattrd Deep Work blocks (persist across reopen/relaunch).
  let blocked='';
  if(P.fcBlocks && P.fcBlocks.length){
    blocked='<div class="fc-blocks">'+P.fcBlocks.map(b=>'<div class="fc-ok">✓ '+b+'</div>').join('')+'</div>';
  }
  // Editable day / start / end picker, pre-filled with the suggested window.
  const picker=
    '<div class="fc-sched">'+
      '<div><label class="fc-fl">Day</label>'+
        '<input class="fc-in" type="date" id="fcDate" value="'+P.fcDefDate+'" min="'+P.fcMinDate+'"></div>'+
      '<div class="fc-times">'+
        '<div><label class="fc-fl">Start</label><input class="fc-in" type="time" id="fcStart" value="'+P.fcDefStart+'"></div>'+
        '<div><label class="fc-fl">End</label><input class="fc-in" type="time" id="fcEnd" value="'+P.fcDefEnd+'"></div>'+
      '</div>'+
      '<div class="fc-err" id="fcErr"></div>'+
      '<button class="fc-btn" onclick="scheduleBlock()">🔒 Add to calendar</button>'+
    '</div>';
  return '<div class="fcast"><div class="fc-hd">🔮 Schedule focus</div>'+
    (P.fcText?'<div class="fc-body">'+P.fcText+'</div>':'')+blocked+picker+'</div>';
}
function scheduleBlock(){
  const d=document.getElementById('fcDate').value;
  const s=document.getElementById('fcStart').value;
  const e=document.getElementById('fcEnd').value;
  const err=document.getElementById('fcErr');
  if(!d||!s||!e){ if(err)err.textContent='Pick a day, start and end time.'; return; }
  const start=new Date(d+'T'+s).getTime()/1000;
  const end=new Date(d+'T'+e).getTime()/1000;
  if(!(end>start)){ if(err)err.textContent='End must be after start.'; return; }
  send('blockAt:'+start+':'+end);
}
document.getElementById('root').innerHTML =
  '<div class="hd">'+ring()+'<div><div class="vd">'+(P.hasData?P.verdict:'Warming up…')+'</div><div class="tdy">Today\'s focus</div></div></div>'+
  streakBanner()+
  forecastCard()+
  '<div class="grid">'+cell(P.switches,'switches')+cell(fmt(P.avg)+'m','avg block')+cell(fmt(P.longest)+'m','longest')+cell(P.deep,'deep blocks')+'</div>'+
  '<div class="sec">Top distractions</div>'+dl+
  '<div style="height:10px"></div>'+
  tog('Track browser tabs',P.tabsOn,'tabs')+
  tog('Launch at login',P.loginOn,'login')+
  tog('Nudge me when scattered',P.nudgeOn,'nudge')+
  tog('Show calendar meetings',P.calOn,'calendar')+
  tog(P.paused?'Tracking paused':'Tracking active',!P.paused,'pause')+
  '<div class="btns"><button class="primary" onclick="send(\'dashboard\')">Open Full Dashboard</button>'+
  '<button class="ghost" onclick="send(\'wrapped\')">Focus Wrapped ✨</button>'+
  (P.debug ? '<button class="ghost" onclick="send(\'test\')">Send Test Summary (dev)</button>' : '')+
  '<button class="quit" onclick="send(\'quit\')">Quit scattrd</button></div>';
if(P.streakBroke){ const el=document.getElementById('streakEl'); if(el) el.classList.add('shatter'); send('streakSeen'); }
</script>
</body></html>
"""#
    }
}

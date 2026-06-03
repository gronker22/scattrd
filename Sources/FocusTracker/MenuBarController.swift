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
    private var isPaused = false

    private let popover = NSPopover()
    private var webView: WKWebView!
    private var eventMonitor: Any?

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

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 344, height: 560), configuration: cfg)
        if #available(macOS 12.0, *) {
            wv.underPageBackgroundColor = NSColor(red: 0.04, green: 0.045, blue: 0.06, alpha: 1)
        }
        webView = wv

        let vc = NSViewController()
        vc.view = wv
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: 344, height: 560)
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
        switch action {
        case "dashboard": closePopover(); onOpenDashboard?()
        case "test":      onSendTestSummary?()
        case "pause":     isPaused.toggle(); onPauseToggle?(isPaused); reloadPanel()
        case "login":     LoginItem.setEnabled(!LoginItem.isEnabled); reloadPanel()
        case "tabs":
            Settings.tabTrackingEnabled.toggle()
            if Settings.tabTrackingEnabled { BrowserTabReader.resetPermissionCache() }
            reloadPanel()
        case "nudge":     Settings.nudgeEnabled.toggle(); reloadPanel()
        case "quit":      NSApp.terminate(nil)
        default: break
        }
        refreshTitle()
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

    private func panelHTML() -> String {
        let s = FocusScore.today(store)
        let debt = FocusDebt.forWeek(store: store)
        let dists = s.topDistractions.prefix(3).map {
            ["app": $0.app, "ints": $0.switchIns] as [String: Any]
        }
        let obj: [String: Any] = [
            "hasData": s.hasEnoughData, "score": s.score, "verdict": scoreVerdict(s.score),
            "switches": s.switches, "avg": s.avgFocusMinutes, "longest": s.longestFocusMinutes,
            "deep": s.deepWorkBlocks,
            "debtH": debt.hoursLost, "debtPct": Int((debt.workdayFraction * 100).rounded()),
            "debtUSD": debt.dollarsLost, "debtInts": debt.interruptions,
            "dists": dists,
            "tabsOn": Settings.tabTrackingEnabled, "loginOn": LoginItem.isEnabled, "paused": isPaused,
            "nudgeOn": Settings.nudgeEnabled,
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
  .debt{padding:12px 13px;margin-bottom:12px;border-color:rgba(251,113,133,.28);
    background:linear-gradient(135deg,rgba(251,113,133,.14),rgba(168,85,247,.05))}
  .debt .lbl{font-size:10px;letter-spacing:.12em;text-transform:uppercase;color:#fda4af;font-weight:650}
  .debt .row{display:flex;align-items:baseline;gap:6px;margin-top:3px}
  .debt .big{font-size:30px;font-weight:780;letter-spacing:-.02em;color:#fb7185}
  .debt .eq{font-size:12px;color:var(--muted)}
  .debt .usd{font-size:12px;color:#fda4af;font-weight:600;margin-top:2px}
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
function debtBox(){
  const h=P.debtH,num=h>=1?fmt(h)+'h':Math.round(h*60)+'m';
  const eq=P.debtPct>=100?'≈ '+(P.debtPct/100).toFixed(1)+' workdays':P.debtInts>0?'≈ '+Math.max(1,P.debtPct)+'% of a workday':'no deep-work interruptions yet';
  const usd=P.debtUSD>=1?'<div class="usd">≈ $'+Math.round(P.debtUSD).toLocaleString()+' of focus lost</div>':'';
  return '<div class="glass debt"><div class="lbl">Focus Debt · this week</div>'+
    '<div class="row"><div class="big">'+num+'</div><div class="eq">'+eq+'</div></div>'+usd+'</div>';
}
function cell(n,l){return '<div class="glass cell"><div class="n">'+n+'</div><div class="l">'+l+'</div></div>';}
function tog(label,on,act){return '<div class="glass tog" onclick="send(\''+act+'\')"><div class="t">'+label+'</div>'+
  '<div class="pill '+(on?'on':'off')+'">'+(on?'ON':'OFF')+'</div></div>';}
let dl='';
if(P.dists.length){ dl=P.dists.map(d=>'<div class="drow"><span>'+d.app+'</span><span class="dm">'+d.ints+'×</span></div>').join(''); }
else { dl='<div class="empty">'+(P.hasData?'None — nicely focused 👏':'—')+'</div>'; }
document.getElementById('root').innerHTML =
  '<div class="hd">'+ring()+'<div><div class="vd">'+(P.hasData?P.verdict:'Warming up…')+'</div><div class="tdy">Today\'s focus</div></div></div>'+
  debtBox()+
  '<div class="grid">'+cell(P.switches,'switches')+cell(fmt(P.avg)+'m','avg block')+cell(fmt(P.longest)+'m','longest')+cell(P.deep,'deep blocks')+'</div>'+
  '<div class="sec">Top distractions</div>'+dl+
  '<div style="height:10px"></div>'+
  tog('Track browser tabs',P.tabsOn,'tabs')+
  tog('Launch at login',P.loginOn,'login')+
  tog('Nudge me when scattered',P.nudgeOn,'nudge')+
  tog(P.paused?'Tracking paused':'Tracking active',!P.paused,'pause')+
  '<div class="btns"><button class="primary" onclick="send(\'dashboard\')">Open Full Dashboard</button>'+
  '<button class="ghost" onclick="send(\'test\')">Send Test Summary</button>'+
  '<button class="quit" onclick="send(\'quit\')">Quit scattrd</button></div>';
</script>
</body></html>
"""#
    }
}

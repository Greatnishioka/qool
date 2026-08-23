"""モックアップの生成スクリプト。

    python3 qool/docs/design/mockups/build.py

すべての .html はこのファイルから生成される。HTML を直接編集せず、ここを直すこと。
共通 CSS を各ファイルにインライン展開しているのは、Claude Design のカード描画で
外部 CSS の相対パス解決が保証されないため。
"""
import pathlib
ROOT = pathlib.Path(__file__).resolve().parent

CSS = """
*,*::before,*::after{box-sizing:border-box}
html,body{margin:0;padding:0}
body{
  font:13px/1.35 -apple-system,"SF Pro Text","Helvetica Neue",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;
  color:var(--label);
  background:var(--desk);
  padding:28px;
  display:flex;flex-wrap:wrap;gap:24px;align-items:flex-start;
}
:root{
  --label:#000; --secondary:rgba(60,60,67,.62); --tertiary:rgba(60,60,67,.32);
  --separator:rgba(60,60,67,.16); --hairline:rgba(0,0,0,.08);
  --accent:#007AFF; --red:#FF3B30; --green:#34C759; --orange:#FF9500;
  --panel:rgba(243,243,243,.86); --panel-solid:#F2F2F2;
  --control:#FFF; --fill:rgba(116,116,128,.09); --fill2:rgba(116,116,128,.16);
  --desk:linear-gradient(135deg,#8EA9C9 0%,#C7B6D8 38%,#E8C9A8 68%,#9FC5B0 100%); --canvas:#FFF;
  --shadow:0 12px 34px rgba(0,0,0,.20),0 1px 2px rgba(0,0,0,.12);
}
:root:not([data-theme=light]){}
@media (prefers-color-scheme:dark){
  :root:not([data-theme=light]){
    --label:#FFF; --secondary:rgba(235,235,245,.60); --tertiary:rgba(235,235,245,.30);
    --separator:rgba(235,235,245,.18); --hairline:rgba(255,255,255,.10);
    --panel:rgba(42,42,44,.86); --panel-solid:#2A2A2C;
    --control:#1E1E20; --fill:rgba(120,120,128,.24); --fill2:rgba(120,120,128,.36);
    --desk:linear-gradient(135deg,#2C3A4E 0%,#43354F 38%,#523F2E 68%,#28453A 100%); --canvas:#F7F7F7;
    --shadow:0 14px 40px rgba(0,0,0,.55),0 1px 2px rgba(0,0,0,.4);
  }
}
.stage{display:flex;flex-direction:column;gap:8px}
.cap{font-size:11px;color:var(--secondary);letter-spacing:.02em}
.cap b{color:var(--label);font-weight:600}
/* --- panel --- */
.panel{
  width:320px;background:var(--panel);backdrop-filter:blur(28px) saturate(180%);
  -webkit-backdrop-filter:blur(28px) saturate(180%);
  border-radius:14px;box-shadow:var(--shadow);
  border:.5px solid var(--hairline);overflow:hidden;
}
.pad{padding:10px 12px}
.row{display:flex;align-items:center;gap:10px}
.sep{height:.5px;background:var(--separator);margin:0 12px}
/* --- list row --- */
.mrow{display:flex;align-items:center;gap:10px;padding:6px 12px;height:48px}
.mrow:hover{background:var(--fill)}
.mrow.sel{background:color-mix(in srgb,var(--accent) 16%,transparent)}
.thumb{width:36px;height:36px;border-radius:5px;background:var(--canvas);
  border:.5px solid var(--hairline);flex:none;overflow:hidden}
.thumb.lg{width:52px;height:52px;border-radius:7px}
.txt{min-width:0;flex:1}
.t1{font-size:13px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.t2{font-size:11px;color:var(--secondary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}
.more{color:var(--tertiary);flex:none;font-size:15px;letter-spacing:1px;line-height:1}
.kbd{font:10px/1 ui-monospace,"SF Mono",monospace;color:var(--secondary);
  background:var(--fill);border:.5px solid var(--hairline);border-radius:4px;
  padding:3px 5px;white-space:nowrap}
/* --- section header --- */
.shead{display:flex;align-items:baseline;justify-content:space-between;padding:10px 12px 4px}
.shead .h{font-size:13px;font-weight:700}
.shead .a{font-size:12px;color:var(--accent)}
.ssub{font-size:11px;color:var(--secondary);padding:0 12px 6px}
/* --- segmented --- */
.seg{display:flex;gap:6px;padding:6px 12px 10px}
.seg > div{flex:1;height:26px;border-radius:13px;display:flex;align-items:center;
  justify-content:center;gap:5px;font-size:12px;font-weight:500;background:var(--fill);color:var(--label)}
.seg > div.on{background:var(--label);color:var(--panel-solid)}
/* --- toolbar --- */
.win{background:var(--panel-solid);border-radius:10px;box-shadow:var(--shadow);
  border:.5px solid var(--hairline);overflow:hidden}
.tbar{height:46px;display:flex;align-items:center;gap:6px;padding:0 12px;
  background:var(--panel);border-bottom:.5px solid var(--separator)}
.lights{display:flex;gap:8px;margin-right:8px}
.lights i{width:12px;height:12px;border-radius:50%;display:block}
.tt{font-size:13px;font-weight:600}
.tbtn{width:28px;height:24px;border-radius:6px;display:flex;align-items:center;
  justify-content:center;color:var(--label);opacity:.75}
.tbtn.on{background:var(--fill2);opacity:1;color:var(--accent)}
.spacer{flex:1}
/* --- inspector --- */
.insp{width:260px;background:var(--panel-solid);border-left:.5px solid var(--separator);padding:12px}
.grp{font-size:11px;font-weight:600;color:var(--secondary);text-transform:none;margin:14px 0 6px}
.grp:first-child{margin-top:0}
.frow{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:3px 0;font-size:12px}
.slider{height:4px;border-radius:2px;background:var(--fill2);position:relative;flex:1}
.slider i{position:absolute;top:-5px;width:14px;height:14px;border-radius:50%;background:#fff;
  box-shadow:0 1px 3px rgba(0,0,0,.35);display:block}
.slider u{position:absolute;left:0;top:0;bottom:0;background:var(--accent);border-radius:2px;display:block}
.well{width:34px;height:20px;border-radius:4px;border:.5px solid var(--hairline)}
.tog{width:34px;height:20px;border-radius:10px;background:var(--green);position:relative}
.tog i{position:absolute;right:2px;top:2px;width:16px;height:16px;border-radius:50%;background:#fff;display:block}
.tog.off{background:var(--fill2)} .tog.off i{left:2px;right:auto}

/* --- Liquid Glass (macOS 26) の近似 --- */
.glass{
  position:relative;
  background:
    radial-gradient(120% 90% at 18% 6%, rgba(255,255,255,.66), rgba(255,255,255,.30) 58%, rgba(255,255,255,.20) 100%);
  backdrop-filter:blur(26px) saturate(220%) brightness(1.06);
  -webkit-backdrop-filter:blur(26px) saturate(220%) brightness(1.06);
  border-radius:20px;
  box-shadow:
    0 12px 36px rgba(0,0,0,.20),
    0 2px 6px rgba(0,0,0,.10),
    0 0 0 .5px rgba(255,255,255,.75);
}
/* 縁のレンズ効果 */
.glass::before{
  content:"";position:absolute;inset:0;border-radius:inherit;pointer-events:none;
  box-shadow:
    inset 0 1.5px 0 rgba(255,255,255,1),
    inset 0 0 16px rgba(255,255,255,.58),
    inset 0 -1.5px 0 rgba(255,255,255,.55),
    inset 1.5px 0 0 rgba(255,255,255,.65),
    inset -1.5px 0 0 rgba(255,255,255,.65);
}
/* スペキュラハイライト */
.glass::after{
  content:"";position:absolute;inset:0;border-radius:inherit;pointer-events:none;
  background:linear-gradient(148deg,
    rgba(255,255,255,.62) 0%, rgba(255,255,255,.10) 26%,
    rgba(255,255,255,0) 52%, rgba(255,255,255,0) 74%,
    rgba(255,255,255,.34) 100%);
  mix-blend-mode:overlay;
}
.glass > *{position:relative;z-index:1}
@media (prefers-color-scheme:dark){
  :root:not([data-theme=light]) .glass{
    background:radial-gradient(120% 90% at 18% 6%, rgba(120,120,126,.56), rgba(58,58,62,.34) 60%, rgba(44,44,48,.30) 100%);
    box-shadow:0 14px 40px rgba(0,0,0,.55),0 2px 6px rgba(0,0,0,.35),0 0 0 .5px rgba(255,255,255,.24);
  }
  :root:not([data-theme=light]) .glass::before{
    box-shadow:
      inset 0 1.5px 0 rgba(255,255,255,.42),
      inset 0 0 16px rgba(255,255,255,.16),
      inset 0 -1.5px 0 rgba(255,255,255,.12),
      inset 1.5px 0 0 rgba(255,255,255,.16),
      inset -1.5px 0 0 rgba(255,255,255,.16);
  }
  :root:not([data-theme=light]) .glass::after{
    background:linear-gradient(148deg,rgba(255,255,255,.26) 0%,rgba(255,255,255,.04) 30%,
      rgba(255,255,255,0) 60%,rgba(255,255,255,.12) 100%);
  }
}
/* パネルをガラスにする（S1 / S2 / S3） */
.panel.glass{border:none}
.glass .grp{color:var(--secondary)}
.gcap{display:flex;align-items:center;justify-content:space-between;
  padding:9px 12px 5px;border-bottom:.5px solid rgba(255,255,255,.5)}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]) .gcap{border-bottom-color:rgba(255,255,255,.12)}}
.gcap .gt{font-size:12px;font-weight:600}
.chev{font-size:10px;color:var(--secondary);width:18px;height:18px;border-radius:9px;
  display:flex;align-items:center;justify-content:center;background:rgba(120,120,128,.20)}
.gbody{padding:8px 12px 12px}
.glass .slider{background:rgba(120,120,128,.30)}
.glass .segsm{border-color:rgba(255,255,255,.65)}
.glass .segsm span{background:rgba(255,255,255,.38)}
.glass .segsm span.on{background:rgba(255,255,255,.88)}
.glass .sep{background:rgba(255,255,255,.5)}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]) .glass .sep{background:rgba(255,255,255,.12)}}
.grab{width:26px;height:4px;border-radius:2px;background:rgba(120,120,128,.35);margin:0 auto}
.mono{font:10px/1 ui-monospace,"SF Mono",monospace;color:var(--secondary)}
.segsm{display:flex;border-radius:6px;overflow:hidden;border:.5px solid var(--hairline);flex:1}
.segsm span{flex:1;text-align:center;font-size:11px;padding:3px 0;background:var(--control)}
.segsm span.on{background:var(--fill2);font-weight:600}
"""

def page(title, group, body, subtitle=""):
    return ('<!-- @dsCard group="%s" -->\n' % group +
            '<meta charset="utf-8"><title>%s</title>\n<style>%s</style>\n' % (title, CSS) +
            body)

def stage(cap, inner):
    return '<div class="stage"><div class="cap">%s</div>%s</div>' % (cap, inner)

# ---------- thumbnails (SVG) ----------
def thumb_shapes():
    return ('<svg viewBox="0 0 100 100" width="100%" height="100%">'
            '<rect x="12" y="20" width="52" height="34" rx="6" fill="#FAF5E0" stroke="#1F2429" stroke-width="3"/>'
            '<path d="M46 46 q22 -18 40 4 q-14 26 -40 12 z" fill="#7BAEE5" stroke="#1F2429" stroke-width="3"/>'
            '<rect x="20" y="66" width="44" height="4" rx="2" fill="#1F2429"/>'
            '<rect x="20" y="76" width="30" height="4" rx="2" fill="#1F2429" opacity=".5"/></svg>')
def thumb_cutout():
    return ('<svg viewBox="0 0 100 100" width="100%" height="100%">'
            '<path d="M22 14 L78 20 L88 70 L36 86 L12 52 Z" fill="#F07A6B" stroke="#1F2429" stroke-width="3"/>'
            '<circle cx="52" cy="46" r="10" fill="#FAF5E0"/></svg>')
def thumb_list():
    return ('<svg viewBox="0 0 100 100" width="100%" height="100%">'
            '<rect x="14" y="14" width="72" height="72" rx="8" fill="#A9DCBD" stroke="#1F2429" stroke-width="3"/>'
            '<rect x="26" y="32" width="48" height="5" rx="2.5" fill="#1F2429"/>'
            '<rect x="26" y="46" width="40" height="5" rx="2.5" fill="#1F2429"/>'
            '<rect x="26" y="60" width="30" height="5" rx="2.5" fill="#1F2429" opacity=".5"/></svg>')
def thumb_mixed():
    return ('<svg viewBox="0 0 100 100" width="100%" height="100%">'
            '<path d="M14 62 q18 -30 38 -12 q16 14 34 -6" fill="none" stroke="#1F2429" stroke-width="3"/>'
            '<rect x="18" y="16" width="30" height="22" rx="4" fill="#7BAEE5" stroke="#1F2429" stroke-width="3"/>'
            '<circle cx="72" cy="30" r="13" fill="#F07A6B" stroke="#1F2429" stroke-width="3"/>'
            '<rect x="20" y="74" width="52" height="5" rx="2.5" fill="#1F2429" opacity=".6"/></svg>')

TH = {"shapes":thumb_shapes(),"cutout":thumb_cutout(),"list":thumb_list(),"mixed":thumb_mixed()}

def row(kind, t1, t2, sel=False, trail='<div class="more">•••</div>'):
    return ('<div class="mrow%s"><div class="thumb">%s</div>'
            '<div class="txt"><div class="t1">%s</div><div class="t2">%s</div></div>%s</div>'
            % (" sel" if sel else "", TH[kind], t1, t2, trail))

MEMOS = [("list","買い物メモ","3 オブジェクト — 昨日"),
         ("cutout","名刺の切り抜き","1 オブジェクト — 昨日"),
         ("mixed","会議のスケッチ","8 オブジェクト — 3日前"),
         ("shapes","構成図ラフ","12 オブジェクト — 先週"),
         ("list","読みたい本","5 オブジェクト — 先週"),
         ("cutout","レシート","2 オブジェクト — 2週間前")]

files = {}

# ================= FOUNDATIONS =================
sw = lambda n,v,d: ('<div style="display:flex;align-items:center;gap:10px;padding:5px 0">'
  '<div style="width:44px;height:24px;border-radius:5px;border:.5px solid var(--hairline);background:%s"></div>'
  '<div><div class="t1">%s</div><div class="t2">%s</div></div></div>' % (v,n,d))
files["foundations/colors.html"] = page("Colors","Foundations", stage(
 "<b>カラー</b> — すべて macOS のセマンティックカラーに対応。独自色は持たない",
 '<div class="panel" style="width:340px"><div class="pad">'
 + sw("labelColor","var(--label)","本文・見出し")
 + sw("secondaryLabelColor","var(--secondary)","2 行目の副次情報")
 + sw("tertiaryLabelColor","var(--tertiary)","••• などの控えめな要素")
 + sw("separatorColor","var(--separator)","行の区切り 0.5pt")
 + sw("controlAccentColor","var(--accent)","選択・リンク・スライダー")
 + sw("systemRed","var(--red)","破棄系のアクション")
 + sw("underPageBackground","var(--panel-solid)","ウィンドウ背景")
 + '<div class="sep" style="margin:8px 0"></div>'
 + '<div class="t2" style="padding:4px 0">パネル背景は NSVisualEffectView（.regularMaterial）。'
   'ライト / ダークは system 追従で、独自のテーマは持たない。</div>'
 + '</div></div>'))

ty = lambda s,w,n,d: ('<div style="padding:6px 0"><div style="font-size:%s;font-weight:%s">%s</div>'
  '<div class="t2">%s</div></div>' % (s,w,n,d))
files["foundations/type.html"] = page("Typography","Foundations", stage(
 "<b>タイポグラフィ</b> — San Francisco。macOS の標準サイズのみを使う",
 '<div class="panel" style="width:340px"><div class="pad">'
 + ty("15px","600","見出し / 15pt Semibold","ウィンドウタイトル、セクションの主見出し")
 + ty("13px","700","小見出し / 13pt Bold","パネル内のセクション見出し")
 + ty("13px","500","本文 / 13pt Medium","リスト行の 1 行目。macOS の標準本文サイズ")
 + ty("13px","400","本文 / 13pt Regular","フォーム、設定項目のラベル")
 + ty("11px","400","キャプション / 11pt","リスト行の 2 行目、補足")
 + '<div style="padding:6px 0"><div class="mono" style="font-size:11px">数値 / 11pt SF Mono &nbsp; 0.80 &nbsp; 12px &nbsp; #FF3B30</div>'
   '<div class="t2">スライダーの値、座標、HEX は等幅にして桁を揃える</div></div>'
 + '<div class="sep" style="margin:8px 0"></div>'
 + '<div class="t2" style="padding:4px 0"><b style="color:var(--label)">折り返さない。</b>'
   '収まらないテキストは末尾を … で切る（ミニプレーヤーと同じ挙動）。</div>'
 + '</div></div>'))

# ================= COMPONENTS =================
files["components/memo-row.html"] = page("Memo Row","Components", stage(
 "<b>メモ行</b> — 高さ 48pt。ミニプレーヤーの曲行に対応する、密度の基準単位",
 '<div class="panel">'
 + row("list","買い物メモ","3 オブジェクト — 昨日")
 + '<div class="sep"></div>'
 + row("mixed","会議のスケッチ","8 オブジェクト — 3日前", sel=True)
 + '<div class="sep"></div>'
 + row("cutout","とても長いタイトルのメモで省略されるもの","2 オブジェクト — 2週間前")
 + '<div class="sep"></div>'
 + row("shapes","浮いているメモ","12 オブジェクト — たった今",
       trail='<div class="kbd">⌃Q F</div>')
 + '</div>'
 + '<div class="cap" style="max-width:320px">36pt サムネイル（キャンバスの実描画）+ '
   'タイトル + 「N オブジェクト — 更新日時」の 2 行。右端は ••• メニュー、'
   'メインのメモだけ割り当てキーを出す。</div>'))

files["components/panel-chrome.html"] = page("Panel Chrome","Components", stage(
 "<b>パネルの構成要素</b> — 見出し・フィルタ・検索",
 '<div class="panel">'
 '<div class="pad row" style="gap:8px">'
   '<div style="flex:1;height:24px;border-radius:6px;background:var(--control);'
   'border:.5px solid var(--hairline);display:flex;align-items:center;padding:0 8px;gap:6px">'
   '<span style="color:var(--tertiary)">⌕</span><span class="t2">検索</span></div>'
   '<div class="tbtn">＋</div></div>'
 '<div class="seg"><div class="on">すべて</div><div>浮いている</div></div>'
 '<div class="sep"></div>'
 '<div class="shead"><div class="h">最近使った項目</div><div class="a">消去</div></div>'
 '<div class="ssub">6 件のメモ</div>'
 + row("list","買い物メモ","3 オブジェクト — 昨日")
 + '</div>'
 + '<div class="cap" style="max-width:320px">セグメンテッドな 2 択、見出し + 右端アクション、'
   '見出し下の補足行。いずれもミニプレーヤーから寸法を借りている。</div>'))

files["components/inspector.html"] = page("Inspector Controls","Components", stage(
 "<b>インスペクタのコントロール</b> — 純正の Slider / Toggle / ColorWell / Segmented のみ",
 '<div class="win" style="width:260px"><div class="insp" style="border-left:none;width:260px">'
 '<div class="grp">矩形</div>'
 '<div class="frow"><span>角丸</span><div class="slider" style="max-width:120px"><u style="width:40%"></u><i style="left:calc(40% - 7px)"></i></div><span class="mono">12</span></div>'
 '<div class="grp">塗り</div>'
 '<div class="frow"><div class="well" style="background:#FAF5E0"></div><span class="mono">#FAF5E0 100%</span><span style="color:var(--tertiary)">◉</span></div>'
 '<div class="grp">枠線</div>'
 '<div class="frow"><span>表示</span><div class="tog"><i></i></div></div>'
 '<div class="frow"><div class="well" style="background:#1F2429"></div><span class="mono">#1F2429</span></div>'
 '<div class="frow"><span>太さ</span><div class="slider" style="max-width:110px"><u style="width:18%"></u><i style="left:calc(18% - 7px)"></i></div><span class="mono">2</span></div>'
 '<div class="grp">ぼかし方向</div>'
 '<div class="frow"><div class="segsm"><span>外側</span><span class="on">内側</span><span>両側</span></div></div>'
 '<div class="grp">位置</div>'
 '<div class="frow"><span class="mono">x 128 &nbsp; y 96 &nbsp; 180 × 120</span></div>'
 '</div></div>'
 + '<div class="cap" style="max-width:260px">幅 260pt。ラベルと値を 1 行に収め、'
   '数値は等幅で右に置く。項目は選択中の要素に応じて出し分ける。</div>'))

# ================= SCREENS =================
files["screens/s1-menubar.html"] = page("S1 Menu Bar","Screens", stage(
 "<b>S1. メニューバー項目</b> — Dock には出さない。常駐の入り口",
 '<div style="width:420px">'
 '<div style="height:24px;border-radius:6px 6px 0 0;background:var(--panel);'
 'backdrop-filter:blur(20px);display:flex;align-items:center;justify-content:flex-end;'
 'gap:14px;padding:0 10px;font-size:11px;border:.5px solid var(--hairline)">'
 '<span style="color:var(--secondary)">􀊫</span><span style="color:var(--secondary)">􀉉</span>'
 '<span style="font-weight:700;color:var(--accent)">◱</span>'
 '<span style="color:var(--secondary)">100%</span><span style="color:var(--secondary)">火 8:24</span></div>'
 '<div class="glass" style="width:200px;margin:6px 0 0 auto;border-radius:12px;padding:5px">'
 + ''.join('<div style="display:flex;justify-content:space-between;padding:4px 8px;'
           'border-radius:5px;font-size:13px%s"><span>%s</span><span class="kbd">%s</span></div>'
           % (";background:var(--accent);color:#fff" if i==0 else "", n, k)
           for i,(n,k) in enumerate([("メモを表示","⌃Q F"),("新しいメモ","⌃Q N")]))
 + '<div class="sep" style="margin:4px 6px"></div>'
 + ''.join('<div style="padding:4px 8px;font-size:13px">%s</div>' % n
           for n in ["設定…","qool を終了"])
 + '</div></div>'
 + '<div class="cap" style="max-width:420px">アイコンのみ。クリックで S3 を開閉。'
   '右クリックでこのメニュー。</div>'))

files["screens/s2-command-hud.html"] = page("S2 Command HUD","Screens", stage(
 "<b>S2. コマンド HUD</b> — ⌃Q の直後に出て、次のキーを待つ。Liquid Glass（.behindWindow）",
 '<div class="panel glass" style="width:300px;border-radius:20px">'
 '<div class="pad" style="padding:14px 16px 6px;display:flex;align-items:center;gap:8px">'
 '<div class="kbd" style="font-size:12px;padding:4px 7px">⌃Q</div>'
 '<div class="t2" style="font-size:12px">次のキーを押してください</div></div>'
 + ''.join('<div class="mrow" style="height:34px;padding:0 16px">'
           '<div class="kbd" style="width:26px;text-align:center">%s</div>'
           '<div class="txt"><div class="t1" style="font-weight:400">%s</div></div></div>' % (k,n)
           for k,n in [("F","メインのメモを表示 / 非表示"),("N","新しいメモ"),(",","設定")])
 + '<div class="pad" style="padding:6px 16px 12px"><div class="t2" style="font-size:11px">'
   'esc でキャンセル</div></div>'
 '</div>'
 + '<div class="cap" style="max-width:300px">押せば消えるものなので最も小さく。'
   '非アクティブパネルとして出すことで、アクセシビリティ権限なしに 2 打目を受け取れる。</div>'))

files["screens/s3-memo-panel.html"] = page("S3 Memo Panel","Screens", stage(
 "<b>S3. メモパネル</b> — アプリの中心。Liquid Glass。ミニプレーヤーを直接なぞる（320 × 560）",
 '<div class="panel glass" style="height:560px;display:flex;flex-direction:column;border-radius:20px">'
 '<div class="pad row" style="gap:8px;padding-top:12px">'
   '<div style="flex:1;height:24px;border-radius:6px;background:var(--control);'
   'border:.5px solid var(--hairline);display:flex;align-items:center;padding:0 8px;gap:6px">'
   '<span style="color:var(--tertiary)">⌕</span><span class="t2">検索</span></div>'
   '<div class="tbtn" style="font-size:16px">＋</div></div>'
 # main memo
 '<div class="mrow" style="height:68px">'
   '<div class="thumb lg">' + TH["mixed"] + '</div>'
   '<div class="txt"><div class="t1" style="font-size:14px;font-weight:600">会議のスケッチ</div>'
   '<div class="t2">8 オブジェクト — 3日前</div>'
   '<div class="t2" style="color:var(--accent);margin-top:3px">メインのメモ</div></div>'
   '<div class="kbd">⌃Q F</div></div>'
 '<div class="seg"><div class="on">すべて</div><div>浮いている</div></div>'
 '<div class="sep"></div>'
 '<div class="shead"><div class="h">最近使った項目</div><div class="a">消去</div></div>'
 '<div class="ssub">6 件</div>'
 '<div style="flex:1;overflow:hidden;position:relative">'
 + ''.join(row(k,a,b) + '<div class="sep"></div>' for k,a,b in MEMOS)
 + '<div style="position:absolute;right:3px;top:8px;width:4px;height:120px;'
   'border-radius:2px;background:var(--tertiary)"></div>'
 '</div></div>'
 + '<div class="cap" style="max-width:320px">上部に<b>メインのメモ</b>を固定し割り当てキーを添える。'
   '行をクリックすると S5 が<b>別ウィンドウ</b>で開く（push 遷移はしない）。</div>'))

files["screens/s4-floating-memo.html"] = page("S4 Floating Memo","Screens", stage(
 "<b>S4. フローティングメモ</b> — ⌃Q F で出る本体。クロームはゼロ",
 '<div style="position:relative;width:360px;height:260px">'
 '<svg viewBox="0 0 360 260" width="360" height="260" style="filter:drop-shadow(0 14px 34px rgba(0,0,0,.34))">'
 '<defs><clipPath id="c"><path d="M28 22 Q150 4 322 30 Q346 120 314 214 Q180 254 44 232 Q10 130 28 22 Z"/></clipPath></defs>'
 '<g clip-path="url(#c)">'
 '<rect width="360" height="260" fill="#FAF7EC"/>'
 '<rect x="34" y="40" width="120" height="72" rx="10" fill="#A9DCBD" stroke="#1F2429" stroke-width="2.5"/>'
 '<circle cx="268" cy="78" r="34" fill="#F07A6B" stroke="#1F2429" stroke-width="2.5"/>'
 '<path d="M40 200 q60 -46 118 -14 q52 28 122 -18" fill="none" stroke="#1F2429" stroke-width="2.5"/>'
 '<text x="48" y="80" font-size="15" font-family="-apple-system" fill="#1F2429">15:00 打ち合わせ</text>'
 '<text x="48" y="104" font-size="15" font-family="-apple-system" fill="#1F2429">資料を持っていく</text>'
 '<text x="48" y="152" font-size="15" font-family="-apple-system" fill="#1F2429">・見積もりの確認</text>'
 '<text x="48" y="174" font-size="15" font-family="-apple-system" fill="#1F2429">・次回の日程</text>'
 '</g></svg>'
 '<div style="position:absolute;right:26px;top:26px;display:flex;gap:5px">'
 '<div style="width:22px;height:22px;border-radius:50%;background:rgba(0,0,0,.34);'
 'color:#fff;font-size:11px;display:flex;align-items:center;justify-content:center">✎</div>'
 '<div style="width:22px;height:22px;border-radius:50%;background:rgba(0,0,0,.34);'
 'color:#fff;font-size:11px;display:flex;align-items:center;justify-content:center">✕</div>'
 '</div></div>'
 + '<div class="cap" style="max-width:360px">タイトルバーなし。輪郭でマスクされ、'
   '<b>外側のクリックは背面のアプリに抜ける</b>。操作はホバー時だけ隅に薄く出す。</div>'))

CANVAS_SVG = ('<svg width="100%" height="100%" viewBox="0 0 640 440">'
 '<defs><pattern id="g" width="24" height="24" patternUnits="userSpaceOnUse">'
 '<path d="M24 0H0V24" fill="none" stroke="#000" stroke-opacity=".07" stroke-width="1"/></pattern></defs>'
 '<rect width="640" height="440" fill="#fff"/><rect width="640" height="440" fill="url(#g)"/>'
 '<rect x="72" y="70" width="190" height="120" rx="14" fill="#FAF5E0" stroke="#1F2429" stroke-width="2"/>'
 '<path d="M300 120 q60 -60 130 -8 q40 60 -18 108 q-84 26 -120 -30 z" fill="#7BAEE5" fill-opacity=".75" stroke="#1F2429" stroke-width="2"/>'
 '<path d="M96 250 L300 250" stroke="#1F2429" stroke-width="4" stroke-linecap="round"/>'
 '<text x="100" y="112" font-size="19" font-family="-apple-system" font-weight="600" fill="#1F2429">買うもの</text>'
 '<text x="100" y="146" font-size="16" font-family="-apple-system" fill="#1F2429">牛乳 / 卵</text>'
 '<path d="M360 300 L470 316 L488 386 L392 402 L350 348 Z" fill="#F07A6B" fill-opacity=".8" stroke="#1F2429" stroke-width="2"/>'
 '<rect x="66" y="64" width="202" height="132" fill="none" stroke="#007AFF" stroke-width="2" stroke-dasharray="6 4"/>'
 + ''.join('<rect x="%d" y="%d" width="8" height="8" fill="#fff" stroke="#007AFF" stroke-width="1.5"/>'%(x,y)
           for x,y in [(62,60),(264,60),(62,192),(264,192)])
 + '</svg>')


def window_float(title, tools, canvas_html, panel_html, w=1000, h=560, panel_w=244, top=14, right=14):
    return ('<div class="win" style="width:%dpx">'
            '<div class="tbar"><div class="lights">'
            '<i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i>'
            '</div><div class="tt">%s</div><div class="spacer"></div>%s</div>'
            '<div style="position:relative;height:%dpx;overflow:hidden">'
            '<div style="position:absolute;inset:0">%s</div>'
            '<div class="glass" style="position:absolute;top:%dpx;right:%dpx;width:%dpx">%s</div>'
            '</div></div>' % (w,title,tools,h,canvas_html,top,right,panel_w,panel_html))

def gpanel(title, body, collapsed=False):
    if collapsed:
        return ('<div class="gcap" style="border-bottom:none"><div class="gt">%s</div>'
                '<div class="chev">▸</div></div>' % title)
    return ('<div class="gcap"><div class="gt">%s</div><div class="chev">▾</div></div>'
            '<div class="gbody">%s</div><div style="padding:0 0 7px"><div class="grab"></div></div>'
            % (title, body))

def window(title, tools, body_html, w=1000, h=700, note=""):
    return ('<div class="win" style="width:%dpx">'
            '<div class="tbar"><div class="lights">'
            '<i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i>'
            '</div><div class="tt">%s</div><div class="spacer"></div>%s</div>'
            '<div style="display:flex;height:%dpx">%s</div></div>' % (w,title,tools,h,body_html))

tools5 = ''.join('<div class="tbtn%s">%s</div>' % (" on" if i==1 else "", t)
                 for i,t in enumerate(["⌖","▭","✎","／","T","▣"]))
INSP5 = (
 '<div class="grp" style="margin-top:0">矩形</div>'
 '<div class="frow"><span class="mono">x 72 &nbsp; y 70 &nbsp; 190 × 120</span></div>'
 '<div class="frow"><span>角丸</span><div class="slider" style="max-width:104px"><u style="width:30%"></u><i style="left:calc(30% - 7px)"></i></div><span class="mono">14</span></div>'
 '<div class="grp">塗り</div>'
 '<div class="frow"><div class="well" style="background:#FAF5E0"></div><span class="mono">#FAF5E0 100%</span></div>'
 '<div class="grp">枠線</div>'
 '<div class="frow"><span>表示</span><div class="tog"><i></i></div></div>'
 '<div class="frow"><div class="well" style="background:#1F2429"></div>'
 '<div class="slider" style="max-width:74px"><u style="width:16%"></u><i style="left:calc(16% - 7px)"></i></div><span class="mono">2</span></div>'
 '<div class="grp">選択中 2 個</div>'
 '<div class="frow"><div class="segsm"><span class="on">結合</span><span>分割</span></div></div>')

tools5b = tools5 + ('<div style="width:8px"></div>'
  '<div class="tbtn on" title="インスペクタ">◨</div>')

files["screens/s5-canvas.html"] = page("S5 Canvas","Screens", stage(
 "<b>S5. キャンバス編集</b> — インスペクタは Liquid Glass でキャンバスの上に浮かせる",
 window_float("会議のスケッチ", tools5b, CANVAS_SVG, gpanel("矩形", INSP5), w=1000, h=560)
 + '<div class="cap" style="max-width:1000px">'
   '<b>SwiftUI の .inspector() は使わない。</b>ドッキングされた区画になるため、'
   'ZStack でキャンバスの上に重ね、.glassEffect(in:) を当てる。'
   '背後のグリッドと図形が透けて見えるのは within-window のブレンド。</div>'))

files["components/floating-inspector.html"] = page("Floating Inspector","Components", stage(
 "<b>浮くインスペクタ</b> — 展開 / 折りたたみ。ツールバーのボタンと連動する",
 '<div style="position:relative;width:640px;height:330px;border-radius:10px;overflow:hidden;'
 'box-shadow:var(--shadow);border:.5px solid var(--hairline)">'
 '<div style="position:absolute;inset:0">'
 + CANVAS_SVG.replace('viewBox="0 0 640 440"','viewBox="0 0 640 330"').replace('height="440"','height="330"')
 + '</div>'
 '<div class="glass" style="position:absolute;top:14px;right:14px;width:244px">'
 + gpanel("矩形", INSP5) + '</div>'
 '<div class="glass" style="position:absolute;top:14px;left:14px;width:150px">'
 + gpanel("矩形", "", collapsed=True) + '</div>'
 '</div>'
 + '<div class="cap" style="max-width:640px">'
   '左が折りたたみ状態。<b>下端のグラブハンドルでドラッグ移動</b>もできるが、'
   'MVP では畳めることを優先する。</div>'))

CHIPS = [("被写体","3.2",True),("前処理","2.8",False),("背景差分","2.1",False),
         ("線色","1.9",False),("色矩形","1.4",False),("手描き","",False)]
chips_html = ''.join(
 '<div style="display:flex;align-items:center;gap:5px;padding:4px 10px;border-radius:13px;'
 'font-size:12px;font-weight:500;white-space:nowrap;%s">%s%s%s</div>'
 % ("background:color-mix(in srgb,var(--accent) 16%,transparent);color:var(--accent)" if on else "color:var(--label)",
    '<span style="font-size:10px">★</span>' if on else "", n,
    '<span class="mono" style="margin-left:2px">%s</span>' % s if s else "")
 for n,s,on in CHIPS)

files["screens/s6-cutout.html"] = page("S6 Cutout","Screens", stage(
 "<b>S6. 画像切り抜き（シート）</b> — なぞって、候補から選ぶ",
 window("画像切り抜き",
   ''.join('<div class="tbtn%s" style="width:auto;padding:0 8px;font-size:12px">%s</div>'
           % (" on" if i==1 else "", t) for i,t in enumerate(["画像を選択","なぞる","抽出","リセット"]))
   + '<div style="width:10px"></div><div class="tbtn" style="width:auto;padding:0 10px;font-size:12px;'
     'background:var(--accent);color:#fff;opacity:1">次へ</div>',
   '<div style="flex:1;display:flex;flex-direction:column">'
   '<div style="flex:1;background:var(--fill);display:flex;align-items:center;justify-content:center">'
   '<svg width="330" height="330" viewBox="0 0 330 330">'
   '<rect width="330" height="330" rx="6" fill="#DDD6CB"/>'
   '<path d="M74 60 Q170 34 254 74 Q286 176 244 262 Q152 292 74 254 Q52 152 74 60 Z" fill="#F4EFE2"/>'
   '<text x="104" y="150" font-size="20" font-family="-apple-system" fill="#8A8078">写真</text>'
   '<path d="M70 56 Q172 30 258 70 Q292 176 248 266 Q150 296 70 258 Q46 152 70 56 Z" fill="none" stroke="#007AFF" stroke-width="3" stroke-dasharray="8 6"/>'
   '<path d="M88 74 Q176 52 244 86" fill="none" stroke="#0A84FF" stroke-width="4" stroke-opacity=".45" stroke-linecap="round"/>'
   '</svg></div>'
   '<div style="border-top:.5px solid var(--separator);background:var(--panel-solid);padding:8px 12px">'
   '<div class="t2" style="margin-bottom:6px">候補</div>'
   '<div style="display:flex;gap:6px;overflow:hidden">' + chips_html + '</div></div>'
   '</div>', w=720, h=470)
 + '<div class="cap" style="max-width:720px">'
   '候補バーは<b>スコア付きのチップを横スクロール</b>。★ が推奨。'
   '自動選択が外れても 1 クリックで直せる。</div>'))

ADJ_SVG = ('<div style="width:100%;height:100%;background:var(--fill);'
 'display:flex;align-items:center;justify-content:center">'
 '<svg width="300" height="300" viewBox="0 0 300 300">'
 '<path d="M60 44 Q158 22 236 60 Q266 156 226 240 Q140 268 62 232 Q38 138 60 44 Z" fill="#F4EFE2" stroke="#007AFF" stroke-width="2.5" stroke-dasharray="7 5"/>'
 '<circle cx="150" cy="130" r="42" fill="#E8DCC8"/>'
 '<text x="112" y="216" font-size="15" font-family="-apple-system" fill="#8A8078">切り抜き結果</text>'
 '</svg></div>')

INSP7 = (
 '<div class="grp" style="margin-top:0">表示</div>'
 + ''.join('<div class="frow"><span>%s</span><div class="slider" style="max-width:104px">'
           '<u style="width:%s"></u><i style="left:calc(%s - 7px)"></i></div><span class="mono">%s</span></div>'
           % (n,p,p,v) for n,p,v in [("薄さ","78%","0.8"),("明度","42%","0.1"),("余白","70%","60px")])
 + '<div class="grp">輪郭</div>'
 '<div class="frow"><span>ぼかし</span><div class="slider" style="max-width:104px"><u style="width:22%"></u><i style="left:calc(22% - 7px)"></i></div><span class="mono">3px</span></div>'
 '<div class="frow"><div class="segsm"><span>外側</span><span class="on">内側</span><span>両側</span></div></div>'
 '<div class="frow" style="margin-top:7px"><div class="tbtn" style="width:100%;height:24px;'
 'background:rgba(255,255,255,.7);opacity:1;font-size:12px;border-radius:7px">表示範囲を修正</div></div>'
 '<div class="grp">テキスト表示域</div>'
 '<div class="frow"><div class="tbtn" style="width:100%;height:24px;background:rgba(255,255,255,.5);'
 'opacity:1;font-size:12px;border-radius:7px">範囲を指定</div></div>')

files["screens/s7-adjust.html"] = page("S7 Adjust","Screens", stage(
 "<b>S7. 画像調整（シート）</b> — コントロールも Liquid Glass でプレビューの上に浮かせる",
 window_float("メモの調整",
   '<div class="tbtn" style="width:auto;padding:0 10px;font-size:12px">キャンセル</div>'
   '<div class="tbtn" style="width:auto;padding:0 10px;font-size:12px;background:var(--accent);color:#fff;opacity:1">作成</div>',
   ADJ_SVG, gpanel("調整", INSP7), w=860, h=480, panel_w=252)
 + '<div class="cap" style="max-width:860px">'
   '<b>常時 15 個以上を並べない。</b>「表示範囲を修正」を押したときだけ、'
   'ブラシ・投げ縄・色域選択のコントロールを出す。'
   'コントラストが落ちるため、S5 より濃いマテリアル（.thickMaterial 相当）を想定。</div>'))

files["screens/s8-settings.html"] = page("S8 Settings","Screens", stage(
 "<b>S8. 設定</b> — 純正の Settings シーン",
 '<div class="win" style="width:520px">'
 '<div class="tbar" style="height:38px"><div class="lights">'
 '<i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i>'
 '</div><div class="spacer"></div>'
 + ''.join('<div class="tbtn%s" style="width:auto;padding:0 10px;font-size:12px">%s</div>'
           % (" on" if i==1 else "", t) for i,t in enumerate(["一般","キーバインド","表示"]))
 + '<div class="spacer"></div></div>'
 '<div style="padding:18px 22px;background:var(--panel-solid)">'
 '<div class="frow" style="padding:7px 0"><span style="width:150px;text-align:right;color:var(--secondary)">プレフィックス</span>'
 '<div style="flex:1;display:flex;align-items:center;gap:8px">'
 '<div class="kbd" style="font-size:12px;padding:5px 9px">⌃Q</div>'
 '<span class="t2" style="font-size:11px">クリックして変更</span></div></div>'
 '<div class="sep" style="margin:10px 0"></div>'
 + ''.join('<div class="frow" style="padding:5px 0"><span style="width:150px;text-align:right;color:var(--secondary)">%s</span>'
           '<div style="flex:1"><div class="kbd" style="font-size:12px;padding:5px 9px">%s</div></div></div>'
           % (n,k) for n,k in [("メモを表示 / 非表示","F"),("新しいメモ","N"),("設定を開く",",")])
 + '<div class="sep" style="margin:12px 0"></div>'
 '<div class="frow" style="padding:5px 0"><span style="width:150px;text-align:right;color:var(--secondary)">メインのメモ</span>'
 '<div style="flex:1"><div class="segsm" style="max-width:220px"><span class="on">選んだメモ</span><span>直近に編集</span></div></div></div>'
 '<div class="frow" style="padding:5px 0"><span style="width:150px;text-align:right"></span>'
 '<span class="t2" style="font-size:11px;flex:1">⌃Q はターミナルのフロー制御と重なります。'
 '必要なら変更してください。</span></div>'
 '</div></div>'
 + '<div class="cap" style="max-width:520px">'
   'キー記録 UI は自作になるが、<b>見た目は純正のショートカット設定に寄せる</b>。</div>'))

for path, html in files.items():
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(html, encoding="utf-8")
    print(path, len(html))

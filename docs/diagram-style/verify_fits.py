"""Render an SVG against the SITE's stylesheet and report any text that
escapes the canvas.

Previewing against Google's CDN font is what let a 914px title ship: the
site serves a self-hosted Caveat subset with wider metrics, so a layout
that fits in the preview can overflow in production. Always measure
against the stylesheet the reader will actually get.
"""
import asyncio, os, sys
from playwright.async_api import async_playwright

SVG = sys.argv[1] if len(sys.argv) > 1 else "week-11-post.svg"
CSS = "https://jayanthkatta.com/blog/assets/fonts.css"

async def main():
    svg = open(SVG, encoding="utf-8").read()
    open("_verify.html", "w", encoding="utf-8").write(
        f'<!doctype html><meta charset="utf-8">'
        f'<link rel="stylesheet" href="{CSS}">'
        f'<style>body{{margin:0;background:#15171a}}svg{{width:100%}}</style>{svg}')
    async with async_playwright() as p:
        b = await p.chromium.connect_over_cdp("http://127.0.0.1:9222")
        ctx = await b.new_context(viewport={"width": 1200, "height": 820},
                                  device_scale_factor=2)
        pg = await ctx.new_page()
        await pg.goto("file:///" + os.path.abspath("_verify.html").replace("\\", "/"),
                      wait_until="networkidle", timeout=60000)
        await pg.wait_for_timeout(2500)
        r = await pg.evaluate("""() => {
            const s=document.querySelector('svg'), vb=s.viewBox.baseVal, bad=[];
            s.querySelectorAll('text').forEach(t=>{
              const b=t.getBBox();
              // getBBox().y is already the TOP in user units, so y+height is the
              // bottom. An earlier version also tested y-height, which flagged
              // every heading and made the whole check noise.
              if(b.x<-2 || b.x+b.width>vb.width+2 || b.y<-2 || b.y+b.height>vb.height+2)
                bad.push({t:t.textContent.slice(0,26), x:Math.round(b.x),
                          r:Math.round(b.x+b.width), b:Math.round(b.y+b.height)});});
            // overlapping text is the other failure this must catch
            const ts=[...s.querySelectorAll('text')].map(t=>({t:t.textContent.slice(0,20),
                                                              b:t.getBBox()}));
            const hits=[];
            for(let i=0;i<ts.length;i++)for(let j=i+1;j<ts.length;j++){
              const a=ts[i].b,c=ts[j].b;
              // 10px of air: two labels that merely touch read as one word.
              const PAD=10;
              const ox=Math.min(a.x+a.width+PAD,c.x+c.width+PAD)-Math.max(a.x,c.x);
              const oy=Math.min(a.y+a.height,c.y+c.height)-Math.max(a.y,c.y);
              if(ox<=0||oy<=0) continue;
              // Two stacked caption lines always touch a little - that is
              // leading, not a collision. A real collision shares a LINE, so
              // require most of the shorter box's height to overlap as well as
              // a real slice of its width. Ratio-of-area alone could not tell
              // the two apart: it called leading a bug at 22% and missed
              // "approves" printing across "principal" at 40%.
              const hMin=Math.min(a.height,c.height), wMin=Math.min(a.width,c.width);
              if(oy/hMin > 0.55 && ox/wMin > 0.18)
                hits.push(ts[i].t+" / "+ts[j].t);}
            // Text escaping the BOX it belongs to. The canvas check cannot see
            // this: a caption can overflow its panel and still sit inside the
            // canvas, which is exactly how "needs approval" landed on top of
            // "a DIFFERENT".
            const meta=s.querySelector('metadata#panels');
            const boxes=(meta?meta.textContent:'').split(';').filter(Boolean).map(e=>{
              const [,v]=e.split(':'); const [x,y,w,h]=v.split(',').map(Number);
              return {x,y,width:w,height:h};});
            const esc=[];
            s.querySelectorAll('text').forEach(t=>{
              const b=t.getBBox(), cx=b.x+b.width/2, cy=b.y+b.height/2;
              for(const bx of boxes){
                const inside = cx>bx.x && cx<bx.x+bx.width && cy>bx.y && cy<bx.y+bx.height;
                if(inside && (b.x < bx.x-6 || b.x+b.width > bx.x+bx.width+6
                              || b.y < bx.y-8 || b.y+b.height > bx.y+bx.height+8))
                  { esc.push(t.textContent.slice(0,26)); break; }}});
            // Arrows crossing labels. The last blind spot: three diagrams
            // shipped with a connector drawn straight through a caption and
            // every other check passed them. Sample along each arrow path and
            // see whether a point lands inside a text box.
            const cross=[];
            s.querySelectorAll('path[marker-end]').forEach(p=>{
              const L=p.getTotalLength(); if(!L) return;
              for(let d=L*0.12; d<=L*0.88; d+=Math.max(4,L/40)){
                const pt=p.getPointAtLength(d);
                for(const t of s.querySelectorAll('text:not(.alabel)')){
                  const b=t.getBBox();
                  if(pt.x>b.x+3 && pt.x<b.x+b.width-3 &&
                     pt.y>b.y+3 && pt.y<b.y+b.height-3){
                    cross.push(t.textContent.slice(0,26)); break;}}}});
            return {cross:[...new Set(cross)].slice(0,6),
                    font:getComputedStyle(s.querySelector('text')).fontFamily.split(',')[0],
                    vb:[vb.width,vb.height], bad, hits:hits.slice(0,6),
                    esc:[...new Set(esc)].slice(0,6)};}""")
        print(f"  font: {r['font']}   canvas: {r['vb'][0]}x{r['vb'][1]}")
        if r["bad"]:
            print(f"  {len(r['bad'])} text element(s) OUTSIDE the canvas:")
            for o in r["bad"]:
                print(f"     [{o['x']}..{o['r']}] bottom {o['b']}  {o['t']!r}")
        if r["hits"]:
            print(f"  {len(r['hits'])} OVERLAPPING pair(s):")
            for h in r["hits"]:
                print(f"     {h}")
        if r.get("esc"):
            print(f"  {len(r['esc'])} caption(s) overflowing their own panel:")
            for e in r["esc"]:
                print(f"     {e!r}")
        if r.get("cross"):
            print(f"  {len(r['cross'])} label(s) with an arrow drawn through them:")
            for c in r["cross"]:
                print(f"     {c!r}")
        if not r["bad"] and not r["hits"] and not r.get("esc") and not r.get("cross"):
            print("  FITS - nothing outside the canvas, nothing overlapping")
        await ctx.close()
        return 1 if (r["bad"] or r["hits"] or r.get("esc") or r.get("cross")) else 0

sys.exit(asyncio.run(main()))

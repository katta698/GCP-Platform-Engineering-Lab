"""Screenshot each week SVG at a given CSS width, against the site's fonts."""
import asyncio, os, sys
from playwright.async_api import async_playwright

WIDTH = int(sys.argv[1]) if len(sys.argv) > 1 else 390
WEEKS = sys.argv[2:] or [f"{n:02d}" for n in range(1, 14)]
CSS = "https://jayanthkatta.com/blog/assets/fonts.css"

async def main():
    async with async_playwright() as p:
        b = await p.chromium.connect_over_cdp("http://127.0.0.1:9222")
        ctx = await b.new_context(viewport={"width": WIDTH, "height": 600},
                                  device_scale_factor=3)
        pg = await ctx.new_page()
        for n in WEEKS:
            svg = open(f"week-{n}.svg", encoding="utf-8").read()
            open("_shot.html", "w", encoding="utf-8").write(
                f'<!doctype html><meta charset="utf-8">'
                f'<link rel="stylesheet" href="{CSS}">'
                f'<style>body{{margin:0;background:#fff}}svg{{width:100%;'
                f'height:auto;display:block}}</style>{svg}')
            await pg.goto("file:///" + os.path.abspath("_shot.html").replace("\\", "/"),
                          wait_until="networkidle", timeout=60000)
            await pg.wait_for_timeout(900)
            el = await pg.query_selector("svg")
            await el.screenshot(path=f"_m{WIDTH}-{n}.png")
            print(f"  _m{WIDTH}-{n}.png")
        await ctx.close()

asyncio.run(main())

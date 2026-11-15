"""Screenshot the architecture figure of a LIVE post at phone width."""
import asyncio, sys
from playwright.async_api import async_playwright

URL = sys.argv[1]; OUT = sys.argv[2]; WIDTH = int(sys.argv[3])

async def main():
    async with async_playwright() as p:
        b = await p.chromium.connect_over_cdp("http://127.0.0.1:9222")
        ctx = await b.new_context(viewport={"width": WIDTH, "height": 900},
                                  device_scale_factor=3, is_mobile=True)
        pg = await ctx.new_page()
        await pg.goto(URL, wait_until="networkidle", timeout=90000)
        await pg.wait_for_timeout(2500)
        el = await pg.query_selector("#architecture figure")
        if not el:
            print("no figure found"); await ctx.close(); return
        box = await el.bounding_box()
        print(f"figure is {box['width']:.0f} x {box['height']:.0f} CSS px "
              f"in a {WIDTH}px viewport")
        await el.screenshot(path=OUT)
        print("wrote", OUT)
        await ctx.close()

asyncio.run(main())

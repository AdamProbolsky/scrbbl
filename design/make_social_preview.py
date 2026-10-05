"""Generates docs/social-preview.png (1280x640), the card shown when the repo
or scrbbl.ai is shared. Black on white, system font plus the app's handwriting."""
from PIL import Image, ImageDraw, ImageFont

W, H, SCALE = 1280, 640, 2
SANS = "/System/Library/Fonts/SFNS.ttf"
HAND = "Scrbbl/Fonts/NothingYouCouldDo.ttf"
ICON = "Scrbbl/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

img = Image.new("RGB", (W * SCALE, H * SCALE), "white")
d = ImageDraw.Draw(img)
s = lambda v: int(v * SCALE)

def sans(size, weight):
    # SF axes are width, optical size, grade, weight; keep normal width.
    f = ImageFont.truetype(SANS, s(size))
    f.set_variation_by_axes([100, min(max(size, 17), 96), 400, weight])
    return f

def bezier(p0, p1, p2, p3, n=400):
    for i in range(n + 1):
        t = i / n
        a, b, c, e = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
        yield (a*p0[0]+b*p1[0]+c*p2[0]+e*p3[0], a*p0[1]+b*p1[1]+c*p2[1]+e*p3[1])

def pen_line(points, width):
    r = s(width) / 2
    for px, py in bezier(*[(s(px), s(py)) for px, py in points]):
        d.ellipse((px - r, py - r, px + r, py + r), fill="black")

# App icon with iPadOS-style rounded corners and a hairline edge.
icon_size = 300
icon = Image.open(ICON).convert("RGB").resize((s(icon_size), s(icon_size)), Image.LANCZOS)
mask = Image.new("L", icon.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, icon.size[0] - 1, icon.size[1] - 1), radius=s(icon_size * 0.225), fill=255)
ix, iy = s(110), s((H - icon_size) / 2)
img.paste(icon, (ix, iy), mask)
d.rounded_rectangle((ix, iy, ix + s(icon_size) - 1, iy + s(icon_size) - 1), radius=s(icon_size * 0.225), outline=(225, 225, 230), width=s(2))

x = s(110 + icon_size + 80)
d.text((x, s(150)), "Scrbbl AI", font=sans(84, 700), fill="black")
d.text((x, s(262)), "Write a question with Apple Pencil.", font=sans(34, 400), fill=(110, 110, 115))
d.text((x, s(308)), "Get the answer back in handwriting.", font=sans(34, 400), fill=(110, 110, 115))
d.text((x, s(392)), "What is the meaning of life?", font=ImageFont.truetype(HAND, s(40)), fill="black")
# Three loose, hand-drawn underlines, like the gesture.
x0 = x / SCALE
for dx0, y, dx1, wob in ((0, 458, 470, -4), (6, 472, 455, 3), (-3, 486, 478, -2)):
    pen_line([(x0 + dx0, y), (x0 + 150, y + wob), (x0 + 320, y - wob), (x0 + dx1, y - 3)], 3.2)
d.text((x, s(520)), "scrbbl.ai  ·  open source on GitHub", font=sans(26, 500), fill=(110, 110, 115))

img.resize((W, H), Image.LANCZOS).save("docs/social-preview.png", optimize=True)
print("saved docs/social-preview.png")

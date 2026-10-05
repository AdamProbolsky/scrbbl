from PIL import Image, ImageDraw, ImageFont
S = 1024
FONT = "/Users/adamprobolsky/Downloads/scribble-ai/Scrbbl/Fonts/NothingYouCouldDo.ttf"

def bezier(p0, p1, p2, p3, n=60):
    pts = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3; b = 3 * (1 - t) ** 2 * t; c = 3 * (1 - t) * t ** 2; d = t ** 3
        pts.append((a*p0[0]+b*p1[0]+c*p2[0]+d*p3[0], a*p0[1]+b*p1[1]+c*p2[1]+d*p3[1]))
    return pts

def render(scale=4):
    s = S * scale
    img = Image.new("RGB", (s, s), "white")
    draw = ImageDraw.Draw(img)
    u = s / 100  # icon drawn on a 100-unit grid, like the preview

    font = ImageFont.truetype(FONT, int(84 * u))
    # Center the "s" horizontally; its bottom sits just above the lines. A thin
    # outline in the same color gives the ballpoint stroke more weight.
    stroke = int(0.25 * u)
    bbox = draw.textbbox((0, 0), "s", font=font, anchor="ls", stroke_width=stroke)
    w = bbox[2] - bbox[0]
    draw.text((50 * u - w / 2 - bbox[0], 58 * u - bbox[3]), "s", font=font, fill="black",
              anchor="ls", stroke_width=stroke, stroke_fill="black")

    width = 3.6 * u
    lines = [
        ((31, 65), (43, 62.5), (57, 66), (69, 63.5)),
        ((32.5, 72.5), (44, 70), (56, 73.5), (67.5, 71)),
        ((30, 80), (43, 77.5), (57, 81), (70, 78.5)),
    ]
    for p0, p1, p2, p3 in lines:
        # Stamp round dabs densely along the curve for a smooth pen stroke.
        r = width / 2
        for x, y in bezier(*[(x * u, y * u) for x, y in (p0, p1, p2, p3)], n=600):
            draw.ellipse((x - r, y - r, x + r, y + r), fill="black")
    return img.resize((S, S), Image.LANCZOS)

icon = render()
icon.save("AppIcon-1024.png")
# Rounded preview the way iPadOS masks it, for review only.
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.225), fill=255)
preview = Image.new("RGB", (S + 160, S + 160), (230, 230, 230))
preview.paste(icon, (80, 80), mask)
preview.resize((600, 600), Image.LANCZOS).save("preview.png")
print("ok", icon.size, icon.mode)

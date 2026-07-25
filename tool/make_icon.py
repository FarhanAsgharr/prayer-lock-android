#!/usr/bin/env python3
"""Draw the Prayer Lock launcher icon as three PNG layers.

The brand is a mosque and a lock — the app restricts apps during prayer. The
mark is a mosque silhouette (dome, finial, two minarets) with a keyhole set into
the prayer hall, which reads as both "prayer" and "lock" without any text. Text
is deliberately absent: the README explains why a wordmark fails at 48dp.

Everything is drawn on a 4x supersampled canvas and downsampled, so the curves
and the keyhole stay clean at the small sizes a launcher actually renders.

Outputs (1024x1024):
  app_icon.png             full green badge, mark in white
  app_icon_foreground.png  mark only, ~60% scale, transparent — adaptive layer
  app_icon_monochrome.png  solid white mark on transparent — Android 13 themed
"""
import math
import pathlib

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # supersample factor
C = SIZE * SS

PRIMARY = (27, 94, 74)      # #1B5E4A
PRIMARY_DARK = (15, 59, 46)  # #0F3B2E
GOLD = (201, 162, 39)        # #C9A227
WHITE = (255, 255, 255)

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "branding"


def vertical_gradient(size, top, bottom):
    """A tall gradient the badge sits on."""
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        grad.putpixel(
            (0, y),
            tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return grad.resize((size, size))


def draw_mark(draw, cx, cy, unit, colour):
    """The mosque-and-keyhole mark, centred at (cx, cy).

    `unit` scales the whole mark, so the same routine draws the full-badge mark
    and the padded adaptive foreground. Coordinates are multiples of `unit`,
    chosen so the mark is optically centred — the minarets extend the silhouette
    upward, so the visual centre sits a little below the geometric one.
    """
    def U(v):
        return v * unit

    # -- two minarets, one each side ------------------------------------------
    for sign in (-1, 1):
        mx = cx + sign * U(2.15)
        top = cy - U(2.35)
        base = cy + U(1.7)
        width = U(0.34)
        # shaft
        draw.rounded_rectangle(
            [mx - width, top, mx + width, base],
            radius=width * 0.6,
            fill=colour,
        )
        # cap
        draw.polygon(
            [
                (mx - width * 1.5, top),
                (mx + width * 1.5, top),
                (mx, top - U(0.55)),
            ],
            fill=colour,
        )
        # finial dot
        draw.ellipse(
            [mx - U(0.1), top - U(0.78), mx + U(0.1), top - U(0.58)],
            fill=colour,
        )

    # -- central dome ---------------------------------------------------------
    # A semicircle sitting flat where it meets the prayer hall. Its half-width
    # is dw; its flat base is dome_top + dw.
    dw = U(1.55)
    dome_top = cy - U(2.0)
    dome_base = dome_top + dw
    draw.pieslice(
        [cx - dw, dome_top, cx + dw, dome_top + dw * 2],
        start=180,
        end=360,
        fill=colour,
    )
    # dome finial
    fx_top = dome_top - U(0.5)
    draw.rounded_rectangle(
        [cx - U(0.08), fx_top, cx + U(0.08), dome_top + U(0.15)],
        radius=U(0.08),
        fill=colour,
    )
    draw.ellipse(
        [cx - U(0.16), fx_top - U(0.28), cx + U(0.16), fx_top + U(0.04)],
        fill=colour,
    )

    # -- prayer hall ----------------------------------------------------------
    hall_w = U(2.55)
    hall_top = dome_base
    hall_base = cy + U(1.9)
    draw.rounded_rectangle(
        [cx - hall_w, hall_top, cx + hall_w, hall_base],
        radius=U(0.25),
        fill=colour,
    )
    # ground line, so the building sits rather than floats
    draw.rounded_rectangle(
        [cx - U(3.0), hall_base, cx + U(3.0), hall_base + U(0.34)],
        radius=U(0.17),
        fill=colour,
    )

    return (hall_top, hall_base, cx)


def punch_keyhole(image, cx, cy_top, cy_base, unit):
    """Cut a keyhole out of the prayer hall, so the mark reads as a lock.

    Cut rather than drawn in the background colour, so the same mark works on the
    transparent foreground and monochrome layers where there is no background to
    match.
    """
    unit_c = unit
    hall_mid = (cy_top + cy_base) / 2
    cx_ = cx
    # keyhole = a circle over a tapering slot
    r = unit_c * 0.42
    kc_y = hall_mid - unit_c * 0.25
    hole = Image.new("L", image.size, 0)
    hd = ImageDraw.Draw(hole)
    hd.ellipse([cx_ - r, kc_y - r, cx_ + r, kc_y + r], fill=255)
    slot_top = kc_y + r * 0.2
    slot_bot = kc_y + unit_c * 1.15
    hd.polygon(
        [
            (cx_ - r * 0.5, slot_top),
            (cx_ + r * 0.5, slot_top),
            (cx_ + r * 0.34, slot_bot),
            (cx_ - r * 0.34, slot_bot),
        ],
        fill=255,
    )
    # subtract the keyhole from the mark's alpha
    alpha = image.split()[3]
    alpha = Image.composite(
        Image.new("L", image.size, 0),
        alpha,
        hole,
    )
    image.putalpha(alpha)


def badge():
    """Full launcher icon: green badge, white mark."""
    base = Image.new("RGBA", (C, C), (0, 0, 0, 0))

    # circular badge with a vertical gradient
    grad = vertical_gradient(C, PRIMARY, PRIMARY_DARK).convert("RGBA")
    mask = Image.new("L", (C, C), 0)
    md = ImageDraw.Draw(mask)
    inset = C * 0.04
    md.ellipse([inset, inset, C - inset, C - inset], fill=255)
    base = Image.composite(grad, base, mask)

    # a thin gold ring, for a little warmth against the green
    rd = ImageDraw.Draw(base)
    ring = C * 0.052
    rd.ellipse(
        [ring, ring, C - ring, C - ring],
        outline=GOLD + (255,),
        width=int(C * 0.006),
    )

    # the mark, in white, with the keyhole punched through to the green
    mark = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    mdraw = ImageDraw.Draw(mark)
    unit = C * 0.084
    hall_top, hall_base, mcx = draw_mark(mdraw, C / 2, C / 2 + C * 0.02, unit,
                                         WHITE + (255,))
    punch_keyhole(mark, mcx, hall_top, hall_base, unit)
    base = Image.alpha_composite(base, mark)

    return base.resize((SIZE, SIZE), Image.LANCZOS)


def foreground():
    """Adaptive foreground: mark only, padded to ~60% so the launcher mask
    cannot clip the minarets."""
    img = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    unit = C * 0.066  # smaller: the badge occupies ~60% of the canvas
    hall_top, hall_base, mcx = draw_mark(d, C / 2, C / 2 + C * 0.015, unit,
                                         WHITE + (255,))
    punch_keyhole(img, mcx, hall_top, hall_base, unit)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def monochrome():
    """Android 13 themed layer: solid white mark, no keyhole cut-out.

    The launcher tints this single colour, so a punched keyhole would tint the
    same as the mark and vanish. A solid silhouette is what themed mode expects.
    """
    img = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    unit = C * 0.066
    draw_mark(d, C / 2, C / 2 + C * 0.015, unit, WHITE + (255,))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    badge().save(OUT / "app_icon.png")
    foreground().save(OUT / "app_icon_foreground.png")
    monochrome().save(OUT / "app_icon_monochrome.png")
    print("wrote", OUT / "app_icon.png")
    print("wrote", OUT / "app_icon_foreground.png")
    print("wrote", OUT / "app_icon_monochrome.png")


if __name__ == "__main__":
    main()

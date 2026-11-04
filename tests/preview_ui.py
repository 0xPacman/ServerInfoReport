"""Render saved ANSI fixture frames to PNG. Development-only: requires Pillow."""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from test_ui import decode_frame

parser = argparse.ArgumentParser()
parser.add_argument("frame", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--columns", type=int, default=120)
parser.add_argument("--rows", type=int, default=36)
args = parser.parse_args()
cells = decode_frame(args.frame.read_text(encoding="utf-8"), args.columns, args.rows)
font_paths = [Path("C:/Windows/Fonts/JetBrainsMonoNerdFontMono-Regular.ttf"), Path("C:/Windows/Fonts/consola.ttf"), Path("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")]
font_path = next(path for path in font_paths if path.exists())
font = ImageFont.truetype(str(font_path), 17)
bold_path = font_path.with_name(font_path.name.replace("Regular", "Bold").replace("consola.ttf", "consolab.ttf").replace("Mono.ttf", "Mono-Bold.ttf"))
bold_font = ImageFont.truetype(str(bold_path), 17) if bold_path.exists() else font
cw, ch, pad = round(font.getlength("M")), 23, 24
image = Image.new("RGB", (args.columns * cw + pad * 2, args.rows * ch + pad * 2), cells[0][0][2])
draw = ImageDraw.Draw(image)
for y, row in enumerate(cells):
    for x, (char, fg, bg, bold) in enumerate(row):
        px, py = pad + x * cw, pad + y * ch
        draw.rectangle((px, py, px + cw - 1, py + ch - 1), fill=bg)
        # Terminal emulators commonly draw block/box cells themselves. Do the
        # same here so missing font fallback cannot distort a preview chart.
        midx, midy = px + cw // 2, py + ch // 2
        if "\u2581" <= char <= "\u2588":
            level = ord(char) - 0x2580
            draw.rectangle((px, py + ch - round(ch * level / 8), px + cw - 1, py + ch - 1), fill=fg)
        elif char == "─":
            draw.line((px, midy, px + cw - 1, midy), fill=fg)
        elif char == "│":
            draw.line((midx, py, midx, py + ch - 1), fill=fg)
        elif char in "╭╮╰╯":
            radius = min(cw // 2, ch // 2)
            if char == "╭":
                draw.line((midx, midy + radius, midx, py + ch - 1), fill=fg)
                draw.arc((midx, midy, midx + 2 * radius, midy + 2 * radius), 180, 270, fill=fg)
                draw.line((midx + radius, midy, px + cw - 1, midy), fill=fg)
            elif char == "╮":
                draw.line((midx, midy + radius, midx, py + ch - 1), fill=fg)
                draw.arc((midx - 2 * radius, midy, midx, midy + 2 * radius), 270, 360, fill=fg)
                draw.line((px, midy, midx - radius, midy), fill=fg)
            elif char == "╰":
                draw.line((midx, py, midx, midy - radius), fill=fg)
                draw.arc((midx, midy - 2 * radius, midx + 2 * radius, midy), 90, 180, fill=fg)
                draw.line((midx + radius, midy, px + cw - 1, midy), fill=fg)
            else:
                draw.line((midx, py, midx, midy - radius), fill=fg)
                draw.arc((midx - 2 * radius, midy - 2 * radius, midx, midy), 0, 90, fill=fg)
                draw.line((px, midy, midx - radius, midy), fill=fg)
        else:
            draw.text((px, py + 1), char, font=bold_font if bold else font, fill=fg, stroke_width=0)
args.output.parent.mkdir(parents=True, exist_ok=True)
image.save(args.output)

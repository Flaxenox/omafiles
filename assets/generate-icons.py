#!/usr/bin/env python3
# Genera las variantes técnicas del icono oficial (Fase 29) a partir de la
# ÚNICA fuente de verdad: assets/omafiles.svg (el icono oficial, un PNG de alta
# resolución embebido en un envoltorio SVG). NO redibuja nada: la silueta del
# simbólico se EXTRAE de los propios píxeles del icono oficial.
#
# Produce, junto a este script:
#   - omafiles-symbolic.svg : misma geometría, recoloreable con currentColor
#     (sin fondo). La carpeta se aísla por componentes conexas — la región
#     oscura que NO toca el borde es la carpeta; la que lo toca son las esquinas
#     exteriores —, se usa como máscara de luminancia y se pinta currentColor.
#     Las barras/puntos (claros) quedan como huecos, igual que en el principal.
#   - omafiles-{32,48,64,128,256}.png : rasterizaciones (LANCZOS) para hicolor.
#
# Requiere numpy y Pillow. Reejecutar solo si cambia omafiles.svg.
import base64
import re
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
SRC_SVG = HERE / "omafiles.svg"


def embedded_png(svg_path: Path) -> bytes:
    m = re.search(r"data:image/png;base64,([A-Za-z0-9+/=]+)", svg_path.read_text())
    if not m:
        raise SystemExit("omafiles.svg no contiene un PNG embebido")
    return base64.b64decode(m.group(1))


def folder_silhouette(im: Image.Image) -> np.ndarray:
    """True donde está la carpeta (oscuro y NO conectado al borde)."""
    rgb = np.asarray(im.convert("RGB")).astype(np.int32)
    lum = 0.2126 * rgb[:, :, 0] + 0.7152 * rgb[:, :, 1] + 0.0722 * rgb[:, :, 2]
    dark = lum < 128  # carpeta + esquinas exteriores negras
    h, w = dark.shape
    outer = np.zeros_like(dark)
    dq = deque()

    def seed(y, x):
        if dark[y, x] and not outer[y, x]:
            outer[y, x] = True
            dq.append((y, x))

    for x in range(w):
        seed(0, x)
        seed(h - 1, x)
    for y in range(h):
        seed(y, 0)
        seed(y, w - 1)
    while dq:
        y, x = dq.popleft()
        if y > 0:
            seed(y - 1, x)
        if y < h - 1:
            seed(y + 1, x)
        if x > 0:
            seed(y, x - 1)
        if x < w - 1:
            seed(y, x + 1)
    return dark & ~outer


def main():
    png = embedded_png(SRC_SVG)
    src_png = HERE / "_omafiles-src.png"
    src_png.write_bytes(png)
    im = Image.open(src_png).convert("RGBA")
    h, w = im.size[1], im.size[0]

    folder = folder_silhouette(im)
    sil = np.zeros((h, w, 4), np.uint8)
    sil[folder] = (255, 255, 255, 255)
    sil_png = HERE / "_omafiles-silhouette.png"
    Image.fromarray(sil, "RGBA").save(sil_png)
    sb = base64.b64encode(sil_png.read_bytes()).decode()

    (HERE / "omafiles-symbolic.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" '
        'width="256" height="256">\n'
        '  <mask id="omafiles-sil" maskUnits="userSpaceOnUse" '
        'x="0" y="0" width="256" height="256">\n'
        f'    <image href="data:image/png;base64,{sb}" '
        'x="0" y="0" width="256" height="256"/>\n'
        "  </mask>\n"
        '  <rect x="0" y="0" width="256" height="256" '
        'fill="currentColor" mask="url(#omafiles-sil)"/>\n'
        "</svg>\n"
    )

    base = Image.open(src_png).convert("RGBA")
    for s in (256, 128, 64, 48, 32):
        base.resize((s, s), Image.LANCZOS).save(HERE / f"omafiles-{s}.png")

    src_png.unlink()
    sil_png.unlink()
    print("generado: omafiles-symbolic.svg + omafiles-{32,48,64,128,256}.png")


if __name__ == "__main__":
    main()

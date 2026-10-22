#!/usr/bin/env python3
"""Bakes the notch buddy's built-in Lottie files into MyWorkDock/Resources/Buddies.

    scripts/bake-buddies.py

The stops below are the CSS keyframes of the design (design/Buddy-States.dc.html: budBlink, budLook, budRing, budWave), so a
changed design is a changed number here, then a re-bake. Every file is a 36 x 28 pt composition at the Lively pace; Calm is the
same file played slower (BuddyAsset.calmSpeed). Colour layers are named `tint` (the app recolours them with the user's tint) and
the eyes are plain black. Needs Xcode's `swift` for the emoji bitmaps.
"""
import base64, json, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "MyWorkDock/Resources/Buddies"
FPS = 30
COMP = (36, 28)                      # points: the ear is 36 wide, the notch about 28 tall
HELLO_MARGIN = 3                     # pt around the hint's 👋, which swings out of its box
TINT = (0xD4 / 255, 0xFF / 255, 0x3A / 255, 1)  # the lime default; the app overrides it
BLACK = (0, 0, 0, 1)

# --- CSS timing functions, as the (x1, y1, x2, y2) of the Lottie handles
EASE = (.25, .1, .25, 1)
EASE_IN_OUT = (.42, 0, .58, 1)
EASE_OUT = (0, 0, .58, 1)

def static(v): return {"a": 0, "k": v}
def animated(k): return {"a": 1, "k": k}

def keyframes(stops, ease, loop_s, loops, value):
    """`stops` are (fraction of the loop, value) as in `@keyframes`; the same easing between each pair, like CSS."""
    out = []
    for r in range(loops):
        for i, (frac, v) in enumerate(stops):
            if i == len(stops) - 1 and r < loops - 1:
                continue                      # the next loop's first stop is the same instant
            kf = {"t": round((r + frac) * loop_s * FPS, 3), "s": value(v)}
            if i < len(stops) - 1:
                if stops[i + 1][1] == v:
                    kf["h"] = 1               # nothing changes until the next stop
                else:
                    kf["o"] = {"x": [ease[0]], "y": [ease[1]]}
                    kf["i"] = {"x": [ease[2]], "y": [ease[3]]}
            out.append(kf)
    out[-1].pop("o", None); out[-1].pop("i", None); out[-1].pop("h", None)
    return animated(out)

def transform(p=(0, 0), a=(0, 0), s=(100, 100), r=0, o=100):
    return {"o": o if isinstance(o, dict) else static(o), "r": r if isinstance(r, dict) else static(r),
            "p": p if isinstance(p, dict) else static([p[0], p[1], 0]), "a": static([a[0], a[1], 0]),
            "s": s if isinstance(s, dict) else static([s[0], s[1], 100])}

def layer(ind, name, ks, frames, **kw):
    return {"ddd": 0, "ind": ind, "nm": name, "sr": 1, "ao": 0, "ip": 0, "op": frames, "st": 0, "bm": 0, "ks": ks, **kw}

def shape_layer(ind, name, ks, frames, shapes):
    return layer(ind, name, ks, frames, ty=4, shapes=[{"ty": "gr", "nm": name, "it": shapes + [
        {"ty": "tr", "p": static([0, 0]), "a": static([0, 0]), "s": static([100, 100]), "r": static(0), "o": static(100)}]}])

def ellipse(w, h): return {"ty": "el", "d": 1, "nm": "shape", "s": static([w, h]), "p": static([0, 0])}
def fill(name, c): return {"ty": "fl", "nm": name, "c": static(list(c)), "o": static(100), "r": 1}
def stroke(name, c, width): return {"ty": "st", "nm": name, "c": static(list(c)), "o": static(100), "w": static(width), "lc": 2, "lj": 2}

def comp(name, w, h, frames, layers, assets=()):
    return {"v": "5.7.0", "fr": FPS, "ip": 0, "op": frames, "w": w, "h": h, "nm": name, "ddd": 0, "assets": list(assets), "layers": layers}

# --- face: budBlink 4 s, budLook 7 s ease-in-out; the 28 s loop holds seven blinks and four glances
def face():
    frames = 28 * FPS
    def eye(x):
        rect = {"ty": "rc", "d": 1, "nm": "eye", "s": static([3, 5]), "p": static([0, 0]), "r": static(2)}
        blink = keyframes([(0, 1), (.93, 1), (.96, .15), (1, 1)], EASE, 4, 7, lambda v: [100, v * 100])
        return {"ty": "gr", "nm": "eye", "it": [rect, fill("ink", BLACK),
                {"ty": "tr", "p": static([x, -0.5]), "a": static([0, 0]), "s": blink, "r": static(0), "o": static(100)}]}
    look = keyframes([(0, 0), (.35, 0), (.42, -2), (.58, -2), (.66, 2), (.80, 2), (.88, 0), (1, 0)], EASE_IN_OUT, 7, 4,
                     lambda v: [COMP[0] / 2 + v, COMP[1] / 2, 0])
    eyes = layer(1, "eyes", transform(p=look), frames, ty=4, shapes=[eye(-3.5), eye(3.5)])
    head = shape_layer(2, "face", transform(p=(COMP[0] / 2, COMP[1] / 2)), frames, [ellipse(18, 18), fill("tint", TINT)])
    return comp("buddy-face", *COMP, frames, [eyes, head])

# --- pulse: an 8 pt dot, and a ring (1.5 pt border, inside the 8 pt box) that grows to 2.6x while it fades: budRing 2 s ease-out
def pulse():
    frames = 2 * FPS
    ring_ks = transform(p=(COMP[0] / 2, COMP[1] / 2),
                        s=keyframes([(0, 100), (1, 260)], EASE_OUT, 2, 1, lambda v: [v, v, 100]),
                        o=keyframes([(0, 70), (1, 0)], EASE_OUT, 2, 1, lambda v: [v]))
    ring = shape_layer(2, "ring", ring_ks, frames, [ellipse(6.5, 6.5), stroke("tint", TINT, 1.5)])
    dot = shape_layer(1, "dot", transform(p=(COMP[0] / 2, COMP[1] / 2)), frames, [ellipse(8, 8), fill("tint", TINT)])
    return comp("buddy-pulse", *COMP, frames, [dot, ring])

# --- emoji: budWave 2.4 s ease-in-out, rotating about 70% 80% of the glyph's layout box (`box`, points). The bitmap is 3x and has
# `margin` pt around that box; the composition is centred on the box.
def emoji(name, png, box, margin, comp_size):
    frames = round(2.4 * FPS)
    w, h = box
    asset = {"id": "glyph", "w": (w + 2 * margin) * 3, "h": (h + 2 * margin) * 3, "u": "", "e": 1,
             "p": "data:image/png;base64," + base64.b64encode(png).decode()}
    cx, cy = comp_size[0] / 2, comp_size[1] / 2
    wave = keyframes([(0, 0), (.10, 16), (.20, -8), (.30, 16), (.40, -8), (.55, 0), (1, 0)], EASE_IN_OUT, 2.4, 1, lambda v: [v])
    ks = transform(p=(cx + .2 * w, cy + .3 * h), a=((margin + .7 * w) * 3, (margin + .8 * h) * 3), s=(100 / 3, 100 / 3), r=wave)
    img = layer(1, "glyph", ks, frames, ty=2, refId="glyph")
    return comp(name, *comp_size, frames, [img], [asset])

EMOJI = {"wave": "👋", "sparkle": "✨", "robot": "🤖", "cat": "🐱", "eyes": "👀"}

def bake_emoji(names, size, margin):
    with tempfile.TemporaryDirectory() as tmp:
        lines = subprocess.run(["swift", str(ROOT / "scripts/bake-emoji.swift"), tmp, str(size), str(margin)] + [f"{n}:{EMOJI[n]}" for n in names],
                               check=True, capture_output=True, text=True).stdout.split("\n")
        return {l.split()[0]: ((pathlib.Path(tmp) / f"{l.split()[0]}.png").read_bytes(), (int(l.split()[1]), int(l.split()[2]))) for l in lines if l}

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = {"buddy-face": face(), "buddy-pulse": pulse()}
    for n, (png, box) in bake_emoji(list(EMOJI), 15, 2).items():
        files[f"buddy-emoji-{n}"] = emoji(f"buddy-emoji-{n}", png, box, 2, COMP)
    # the first-launch hint's greeting: the same wave at 14 pt, in a composition as big as the glyph's box plus its margin
    # (the hint lays it out with a negative padding of that margin, so it takes the room of the box alone)
    png, box = bake_emoji(["wave"], 14, HELLO_MARGIN)["wave"]
    files["buddy-hello"] = emoji("buddy-hello", png, box, HELLO_MARGIN, (box[0] + 2 * HELLO_MARGIN, box[1] + 2 * HELLO_MARGIN))
    for name, data in files.items():
        path = OUT / f"{name}.json"
        path.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False) + "\n")
        print(f"{path.relative_to(ROOT)}  {path.stat().st_size / 1024:.1f} KB")

if __name__ == "__main__":
    sys.exit(main())

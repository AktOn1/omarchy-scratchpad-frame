"""Offline self-test of the ornament feature: the picture work (background to transparent, size, corner), how ornaments are stored and
removed, and the whole Make frame path with the box ticked, against stand-in local servers for the text AI and the image model.
Nothing leaves this computer and no real AI or image model runs. Run: python3 ornament_selftest.py   (also part of: frame-ai selftest)"""
import sys
sys.dont_write_bytecode = True
import base64
import http.server
import io
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.parse

HERE = os.path.dirname(os.path.realpath(__file__))
TMP = tempfile.mkdtemp(prefix="scratchpad-frame-ornament-selftest-")
STATE = os.path.join(TMP, "state")
os.environ["SCRATCHPAD_FRAME_STATE_DIR"] = STATE
for k in ("SCRATCHPAD_FRAME_AI_PROVIDER", "SCRATCHPAD_FRAME_AI_MODEL", "SCRATCHPAD_FRAME_AI_CMD"):
    os.environ.pop(k, None)
sys.path.insert(0, HERE)
import framedesign as M  # noqa: E402
import framelib as L  # noqa: E402
import imgprov as I  # noqa: E402
import ornament as O  # noqa: E402

OK = FAIL = 0


def check(name, cond, detail=""):
    global OK, FAIL
    if cond:
        OK += 1
    else:
        FAIL += 1
        print("FAIL", name, detail)


def raises(fn, word=""):
    try:
        fn()
    except L.Bad as e:
        return word.lower() in str(e).lower()
    return False


try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow is not installed: the ornament picture tests were skipped")
    print("0 ok, 0 failed (Pillow missing)")
    sys.exit(0)


def png_of(im):
    b = io.BytesIO()
    im.save(b, "PNG")
    return b.getvalue()


def art(bg=(0, 0, 0), corner="br", size=1024, noise=False):
    """a stand-in model picture: a gold scroll in one corner on a plain background"""
    im = Image.new("RGB", (size, size), bg)
    d = ImageDraw.Draw(im)
    x0, y0 = (size - 560, size - 560) if corner == "br" else (0, 0)
    d.rectangle((x0, y0 + 40, x0 + 540, y0 + 110), fill=(212, 175, 55))
    d.rectangle((x0 + 40, y0, x0 + 110, y0 + 540), fill=(212, 175, 55))
    d.ellipse((x0 + 150, y0 + 150, x0 + 330, y0 + 330), outline=(240, 200, 80), width=18)
    if noise:
        im = Image.frombytes("RGB", (size, size), os.urandom(size * size * 3))
    return png_of(im)


# ---- 1. the picture work (with every engine that is installed: Pillow, and ImageMagick as the fallback)
ENGINES = [e for e, ok in (("pillow", O._pil()), ("magick", O._magick())) if ok]
check("at least one picture engine is installed", bool(ENGINES), "need Pillow or ImageMagick")
for eng in ENGINES:
    tag = "[%s] " % eng
    out = O.process(art(), engine=eng)
    w, h = O.check_png(out)
    check(tag + "a stored ornament is exactly the fixed square size", (w, h) == (512, 512))
    a = Image.open(io.BytesIO(out)).convert("RGBA").getchannel("A")
    check(tag + "the background became transparent", a.getpixel((511, 511)) == 0 and a.getpixel((500, 500)) == 0)
    box = a.point([0 if v < 40 else 255 for v in range(256)]).getbbox()
    check(tag + "an ornament drawn bottom-right is turned to the top-left", box and box[0] <= 4 and box[1] <= 4, box)
    check(tag + "the ornament itself stays visible", a.getpixel((60, 60)) > 200 or a.getpixel((30, 30)) > 200)
    px = Image.open(io.BytesIO(out)).convert("RGBA").getpixel((60, 60)) if a.getpixel((60, 60)) > 200 else Image.open(io.BytesIO(out)).convert("RGBA").getpixel((30, 30))
    check(tag + "the ornament keeps its colour (gold, not black)", px[0] > 150 and px[2] < px[0] - 60, px)
    out2 = O.process(art(bg=(255, 255, 255), corner="tl"), engine=eng)
    check(tag + "a white background works too", O.check_png(out2) == (512, 512))
    check(tag + "an all-black picture is rejected as empty", raises(lambda: O.process(png_of(Image.new("RGB", (800, 800), (0, 0, 0))), engine=eng), "no visible ornament"))
    check(tag + "a picture with a busy background is rejected", raises(lambda: O.process(art(noise=True), engine=eng), "plain background"))
    check(tag + "junk bytes are rejected", raises(lambda: O.process(b"not a picture at all", engine=eng), "could not be read"))
    check(tag + "a tiny picture is rejected", raises(lambda: O.process(png_of(Image.new("RGB", (20, 20))), engine=eng), "too small"))
    check(tag + "a PNG header with junk inside is rejected", raises(lambda: O.process(O.PNG_MAGIC + b"junkjunkjunk" * 20, engine=eng), "could not be read"))
out = O.process(art())
check("check_png: wrong magic", raises(lambda: O.check_png(b"GIF89a" + b"\0" * 100), "not a png"))
check("check_png: wrong size", raises(lambda: O.check_png(png_of(Image.new("RGBA", (100, 100)))), "odd size"))
check("check_png: empty", raises(lambda: O.check_png(b""), "empty"))
check("a huge file is refused", raises(lambda: O.check_png(O.PNG_MAGIC + b"x" * (O.MAX_FILE + 1)), "too large"))
check("no engine gives a plain message", raises(lambda: O.process(art(), engine="none"), "pillow"))

# ---- 2. the prompt
check("a good ornament text passes", O.clean_prompt("  mossy vines, small ferns ") == "mossy vines, small ferns")
check("markup and code characters are dropped", "<" not in O.clean_prompt("<b>vines</b>; rm -rf $(x)") and "$" not in O.clean_prompt("vines $(x) `y`"))
check("a text without words gives nothing", O.clean_prompt("!!! 12 ???") == "" and O.clean_prompt(None) == "")
check("the text is capped", len(O.clean_prompt("leaf " * 100)) <= O.PROMPT_MAX)

# ---- 3. storing, ids, cleaning up
check("an id must be 12 hex digits", raises(lambda: O.path_of("../../etc/passwd")) and raises(lambda: O.path_of("ABCDEF123456")) and raises(lambda: O.path_of(None)))
ids = [O.store(out) for _ in range(3)]
check("stored under the state folder as <id>.png", all(os.path.isfile(os.path.join(STATE, "ornaments", i + ".png")) and O.ID_RE.fullmatch(i) for i in ids))
check("the ornaments folder is private", oct(os.stat(os.path.join(STATE, "ornaments")).st_mode & 0o777) == "0o700")
check("a bad file is never stored", raises(lambda: O.store(b"junk")) and len(O.listing()) == 3)
json.dump({"padA": {"style": "OWNART", "ornament": ids[0]}}, open(os.path.join(STATE, "looks.json"), "w"))
check("a saved look keeps its ornament when dropping", O.drop(ids[0]) is False and os.path.exists(O.path_of(ids[0])))
check("an unused ornament can be dropped", O.drop(ids[1]) is True and not os.path.exists(O.path_of(ids[1])))
gone = O.prune()
check("prune removes the ones no look uses", gone == [ids[2]] and [i for i, _ in O.listing()] == [ids[0]], gone)
open(os.path.join(O.dir_(), "a" * 12 + ".png.tmp"), "w").write("x")
os.utime(os.path.join(O.dir_(), "a" * 12 + ".png.tmp"), (time.time() - 600,) * 2)
open(os.path.join(O.dir_(), "notes.txt"), "w").write("mine")
O.prune()
check("prune clears old half-written files and leaves foreign files alone", not os.path.exists(os.path.join(O.dir_(), "a" * 12 + ".png.tmp")) and os.path.exists(os.path.join(O.dir_(), "notes.txt")))
many = [O.store(out) for _ in range(O.MAX_SETS + 4)]
for i, m in enumerate(many):
    os.utime(O.path_of(m), (time.time() - 1000 + i,) * 2)
O.prune(keep=[many[-1]], cap=O.MAX_SETS)
left = [i for i, _ in O.listing()]
check("a cap keeps only the newest sets (oldest removed first)", len(left) <= O.MAX_SETS and many[-1] in left and many[0] not in left, len(left))
os.remove(os.path.join(O.dir_(), "notes.txt"))
shutil.rmtree(STATE, ignore_errors=True)

# ---- 4. stand-in servers: one for the text AI and one for the image model (ComfyUI shaped)
SEEN = {"ai": [], "prompt": [], "n": 0}
ANSWER = {"text": "", "pic": b""}


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, body, ctype="application/json"):
        raw = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        p = urllib.parse.urlparse(self.path).path
        if p == "/object_info/CheckpointLoaderSimple":
            return self.reply({"CheckpointLoaderSimple": {"input": {"required": {"ckpt_name": [["mine.safetensors"]]}}}})
        if p.startswith("/history/"):
            return self.reply({"p1": {"status": {"completed": True, "status_str": "success"}, "outputs": {"9": {"images": [{"filename": "x.png", "subfolder": "", "type": "output"}]}}}})
        if p == "/view":
            return self.reply(ANSWER["pic"], "image/png")
        self.send_error(404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        if self.path == "/prompt":
            SEEN["prompt"].append(body)
            return self.reply({"prompt_id": "p1"})
        SEEN["ai"].append(body)
        self.reply({"choices": [{"message": {"content": ANSWER["text"]}}], "usage": {"prompt_tokens": 5, "completion_tokens": 7}})


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:%d" % srv.server_address[1]
AI = {"provider": "endpoint", "model": "m", "caps": {}, "endpoint": {"url": BASE + "/v1", "key_env": "", "key_file": ""}}
IMG = {"provider": "comfyui", "comfy": {"url": BASE, "workflow": "", "checkpoint": "mine.safetensors"},
       "endpoint": {"url": "", "model": "", "key_env": "", "key_file": "", "size": ""}, "custom": ""}
GOOD = '{"name": "Mossy night", "style": "FOLIAGE", "colors": {"accent": "#2e8b57", "background": "#0b1a12"}, "ornament": "curling fern fronds and tiny moss flowers"}'
ANSWER["pic"] = art()

# the default path: no image model contact at all
ANSWER["text"] = GOOD
r = M.make("calm night forest", AI)
check("box not ticked: normal recipe, no ornament", r["ok"] and r["recipe"]["style"] == "FOLIAGE" and "ornament" not in r["recipe"] and "ornamentText" not in r["recipe"], r)
check("box not ticked: the text AI is not even asked about ornaments", "short phrase" not in json.dumps(SEEN["ai"][-1]) and "ornament" not in json.dumps(SEEN["ai"][-1]).lower())
check("box not ticked: nothing went to the image model", SEEN["prompt"] == [] and not os.path.isdir(O.dir_()))

# ticked: the ornament is made and the recipe points at it by id
steps = []
r = M.make("calm night forest", AI, images=IMG, progress=steps.append)
rec = r.get("recipe", {})
check("box ticked: the recipe uses the made ornament", r["ok"] and rec.get("style") == "OWNART" and O.ID_RE.fullmatch(rec.get("ornament", "")), r)
check("box ticked: the ornament file exists and passed the checks", rec and O.check_png(open(O.path_of(rec["ornament"]), "rb").read()) == (512, 512))
check("box ticked: the colours are kept", rec.get("colors", {}).get("accent") == "#2e8b57")
check("box ticked: progress steps are reported", steps == ["ai", "image"], steps)
sent = json.dumps(SEEN["prompt"][-1])
check("only the ornament description reached the image model", "curling fern fronds" in sent and "calm night forest" not in sent and "FOLIAGE" not in sent and "#2e8b57" not in sent)
check("the recipe stays data only", set(rec) <= {"name", "style", "colors", "ornament", "ornamentText"} and all(isinstance(v, (str, dict)) for v in rec.values()), rec)
first = rec["ornament"]

# the image model fails: the frame still comes, with a plain note
for what, pic in (("junk", b"not a picture"), ("an empty picture", png_of(Image.new("RGB", (800, 800), (0, 0, 0))))):
    ANSWER["pic"] = pic
    r = M.make("calm night forest", AI, images=IMG)
    check("image model gives %s: the normal frame still comes" % what, r["ok"] and r["recipe"]["style"] == "FOLIAGE" and "ornament" not in r["recipe"] and "normal frame" in r.get("note", ""), r)
check("a failed ornament leaves no new file behind", [i for i, _ in O.listing()] == [first])
bad_IMG = dict(IMG, comfy=dict(IMG["comfy"], url="http://127.0.0.1:9"))
r = M.make("calm night forest", AI, images=bad_IMG)
check("image model not running: the normal frame and a plain note", r["ok"] and "ornament" not in r["recipe"] and "could not make the ornament" in r["note"], r)
ANSWER["pic"] = art()
ANSWER["text"] = '{"name": "Plain", "style": "FOLIAGE", "colors": {"accent": "#2e8b57"}}'
n = len(SEEN["prompt"])
r = M.make("calm night forest", AI, images=IMG)
check("the AI gave no ornament text: nothing is sent to the image model", r["ok"] and len(SEEN["prompt"]) == n and "no ornament description" in r["note"], r)
ANSWER["text"] = GOOD.replace("curling fern fronds and tiny moss flowers", "<script>alert(1)</script> $(rm -rf ~) `x` ferns")
r = M.make("x forest", AI, images=IMG)
t = r["recipe"].get("ornamentText", "")
check("code-like ornament text is cleaned before use", r["ok"] and not any(c in t for c in "<>$`;"), t)

# ---- 5. the command line
env = dict(os.environ, SCRATCHPAD_FRAME_AI_PROVIDER="")


def cli(*args):
    p = subprocess.run([sys.executable, os.path.join(HERE, "frame-ai")] + list(args), capture_output=True, text=True, env=env, timeout=60)
    return p.returncode, p.stdout, p.stderr


rc, so, _ = cli("image", "use", "comfyui", "--comfy-url", BASE, "--checkpoint", "mine.safetensors", "--ornaments", "1", "--json")
d = json.loads(so.strip().splitlines()[-1])
check("image use remembers the pick and the tick-box", rc == 0 and d["ornaments"] is True and d["choice"]["comfy"]["url"] == BASE, so)
rc, so, _ = cli("image", "providers", "--json")
d = json.loads(so.strip().splitlines()[-1])
check("image providers lists the three ways and the tick-box", [p["id"] for p in d["providers"]] == ["comfyui", "endpoint", "custom"] and d["ornaments"] is True, so)
rc, so, _ = cli("image", "checkpoints", "--json")
d = json.loads(so.strip().splitlines()[-1])
check("image checkpoints lists the server's checkpoints", rc == 0 and d["checkpoints"] == ["mine.safetensors"] and d["suggest"] == "mine.safetensors", so)
rc, so, _ = cli("image", "test", "--json")
d = json.loads(so.strip().splitlines()[-1])
check("image test says it works", rc == 0 and d["ok"] and "1 checkpoint" in d["message"], so)
rc, so, _ = cli("image", "use", "comfyui", "--comfy-url", "http://127.0.0.1:9", "--json")
rc, so, _ = cli("image", "test", "--json")
d = json.loads(so.strip().splitlines()[-1])
check("image test says plainly when the server is not there", rc == 1 and not d["ok"] and d["error"], so)
cli("image", "use", "comfyui", "--comfy-url", BASE, "--json")
rc, so, _ = cli("ornaments", "list", "--json")
d = json.loads(so.strip().splitlines()[-1])
check("making a new ornament removed the unused older one (no orphans)", len(d["ornaments"]) == 1 and d["ornaments"][0]["id"] != first, so)
first = d["ornaments"][0]["id"]
rc, so, _ = cli("ornaments", "drop", "../../etc/passwd", "--json")
check("ornaments drop refuses a path", rc == 1)
rc, so, _ = cli("ornaments", "drop", first, "--json")
check("ornaments drop deletes an unused ornament", rc == 0 and not os.path.exists(O.path_of(first)), so)
rc, so, _ = cli("ornaments", "prune", "--json")
check("ornaments prune leaves no orphans", rc == 0 and O.listing() == [], so)

srv.shutdown()
shutil.rmtree(TMP, ignore_errors=True)
print("%d ok, %d failed" % (OK, FAIL))
sys.exit(1 if FAIL else 0)

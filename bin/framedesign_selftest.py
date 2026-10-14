"""Offline self-test of bin/framedesign.py: what is sent, how a recipe is read, and that a bad recipe from the AI is rejected.
A tiny local web server stands in for the AI; nothing leaves this computer and no real AI is called.
Run: python3 bin/framedesign_selftest.py   (also part of: bin/frame-ai selftest)"""
import sys
sys.dont_write_bytecode = True
import http.server
import json
import os
import shutil
import tempfile
import threading

HERE = os.path.dirname(os.path.realpath(__file__))
TMP = tempfile.mkdtemp(prefix="scratchpad-frame-designer-selftest-")
os.environ["SCRATCHPAD_FRAME_STATE_DIR"] = os.path.join(TMP, "state")
for k in ("SCRATCHPAD_FRAME_AI_PROVIDER", "SCRATCHPAD_FRAME_AI_MODEL", "SCRATCHPAD_FRAME_AI_CMD"):
    os.environ.pop(k, None)
sys.path.insert(0, HERE)
import aiprov as P  # noqa: E402
import framelib as L  # noqa: E402
import framedesign as M  # noqa: E402

OK = FAIL = 0


def check(name, cond, detail=""):
    global OK, FAIL
    if cond:
        OK += 1
    else:
        FAIL += 1
        print("FAIL %s %s" % (name, detail))


def rejects(name, obj, word=""):
    try:
        M.validate(obj, {"OMARCHY": "", "FROST": "", "WOOD": ""})
        check(name, False, "was accepted: %r" % (obj,))
    except L.Bad as e:
        check(name, word.lower() in str(e).lower(), str(e))


# ---- 1. the style list comes from the real files
S = M.styles()
check("every picker style is listed", len(S) >= 45 and "OMARCHY" in S and "WOOD" in S and "CORALREEF" in S, len(S))
check("hidden TRY styles are left out", not any(n.startswith("TRY") for n in S))
check("styles carry their one-line description", S.get("OMARCHY") == "Plain band in your theme colours", S.get("OMARCHY"))

# ---- 2. what is sent is the description and the style list, nothing else
system, user = M.prompts("calm night forest", True)
check("the user part is just the description", user == "Frame I want: calm night forest", user)
check("the system part lists the styles and the colour names", "FROST: " in system and "darker_background" in system)
check("a small model is only asked for three colours", "magenta" not in M.prompts("x", False)[0].split("Styles:")[0] and "accent" in M.prompts("x", False)[0])
check("no model or vendor is named in the prompt", not any(w in system.lower() for w in ("claude", "gpt", "gemini", "openai", "anthropic")))
check("no machine or personal detail in the prompt", ("/ho" + "me/") not in system and os.environ.get("USER", "-nobody-") not in system.split())

# ---- 3. reading the AI's answer
check("json inside a code fence", M.extract_json('Sure!\n```json\n{"style": "FROST"}\n```\nEnjoy')["style"] == "FROST")
check("braces inside strings do not confuse it", M.extract_json('{"name": "a } b", "style": "WOOD"}')["style"] == "WOOD")
check("the first object is taken", M.extract_json('{"style": "WOOD"} and {"style": "FROST"}')["style"] == "WOOD")
for bad in ("no json here", "", "[1, 2]", '{"style": '):
    try:
        M.extract_json(bad)
        check("no object -> rejected: %r" % bad, False)
    except L.Bad:
        check("no object -> rejected: %r" % bad, True)

# ---- 4. a good recipe is cleaned, a bad one is rejected
KNOWN = {"OMARCHY": "", "FROST": "", "WOOD": ""}
r = M.validate({"name": "Mossy night", "style": "frost", "colors": {"accent": "#ABC", "background": "#101820", "bogus": "#fff", "text": "x"}}, KNOWN)
check("style is upper-cased, #abc expanded, unknown keys dropped", r == {"name": "Mossy night", "style": "FROST", "colors": {"accent": "#aabbcc", "background": "#101820"}}, r)
check("a recipe with only a style is fine", M.validate({"style": "WOOD"}, KNOWN) == {"name": "Wood", "style": "WOOD", "colors": {}})
check("the name loses odd characters and is short", M.validate({"style": "WOOD", "name": "<b>x</b>" + "y" * 100}, KNOWN)["name"] == "bxby" + "y" * 36)
rejects("not an object", ["FROST"], "not an object")
rejects("no style", {"colors": {}}, "style")
rejects("a style that does not exist", {"style": "NOPE"}, "does not exist")
rejects("a style that is a script", {"style": "FROST'); rm -rf ~"}, "does not exist")
rejects("a colour name instead of hex", {"style": "FROST", "colors": {"accent": "red"}}, "accent")
rejects("a colour that is code", {"style": "FROST", "colors": {"accent": "url(javascript:1)"}}, "accent")
rejects("a colour with too few digits", {"style": "FROST", "colors": {"accent": "#12345"}}, "accent")
rejects("a colour that is a number", {"style": "FROST", "colors": {"accent": 255}}, "accent")
rejects("colours that are a list", {"style": "FROST", "colors": ["#fff"]}, "colours")
rejects("style that is a number", {"style": 5}, "does not exist")

# ---- 5. the description is checked before anything is sent
for bad in ("", "   \n ", None):
    try:
        M.clean_description(bad)
        check("empty description rejected: %r" % bad, False)
    except L.Bad as e:
        check("empty description rejected: %r" % bad, "Describe" in str(e))
try:
    M.clean_description("word " * 500)
    check("a very long description is rejected", False)
except L.Bad:
    check("a very long description is rejected", True)
check("white space is tidied", M.clean_description("  calm \n  forest ") == "calm forest")

# ---- 6. end to end against a stand-in endpoint
SEEN = []
ANSWER = {"text": ""}


class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        SEEN.append(json.loads(self.rfile.read(n) or b"{}"))
        data = json.dumps({"choices": [{"message": {"content": ANSWER["text"]}}], "usage": {"prompt_tokens": 5, "completion_tokens": 7}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


srv = http.server.HTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
CH = {"provider": "endpoint", "model": "m", "caps": {}, "endpoint": {"url": "http://127.0.0.1:%d/v1" % srv.server_address[1], "key_env": "", "key_file": ""}}

ANSWER["text"] = 'Here you go:\n{"name": "Night forest", "style": "FOLIAGE", "colors": {"accent": "#2e8b57", "background": "#0b1a12"}}'
r = M.make("calm night forest", CH)
check("a good answer becomes a recipe", r["ok"] and r["recipe"]["style"] == "FOLIAGE" and r["recipe"]["colors"]["accent"] == "#2e8b57", r)
sent = json.dumps(SEEN[-1])
check("only the description and the style list were sent", SEEN[-1]["messages"][1]["content"] == "Frame I want: calm night forest" and "FOLIAGE" in sent)
check("an endpoint model is passed as typed, none invented", SEEN[-1]["model"] == "m")

n = len(SEEN)
r = M.make("", CH)
check("an empty box sends nothing", not r["ok"] and len(SEEN) == n and "Describe" in r["error"], r)

ANSWER["text"] = '{"name": "Bad", "style": "DOES_NOT_EXIST", "colors": {"accent": "#2e8b57"}}'
r = M.make("anything", CH)
check("a recipe with a style that does not exist is rejected", not r["ok"] and "recipe" not in r and "does not exist" in r["error"], r)
ANSWER["text"] = '{"style": "FOLIAGE", "colors": {"accent": "javascript:alert(1)"}}'
r = M.make("anything", CH)
check("a recipe with a code-like colour is rejected", not r["ok"] and "recipe" not in r, r)
ANSWER["text"] = "I cannot do that, sorry."
r = M.make("anything", CH)
check("an answer without a recipe is rejected with a plain message", not r["ok"] and "recipe" in r["error"], r)
check("a rejected answer never changes the saved state", not os.path.exists(os.path.join(os.environ["SCRATCHPAD_FRAME_STATE_DIR"], "looks.json")))

r = M.make("anything", dict(CH, endpoint={"url": "", "key_env": "", "key_file": ""}))
check("an AI that is not set up says what to do", not r["ok"] and "URL" in r["error"], r)
srv.shutdown()

# ---- 7. the CLI prints the same, as JSON
import subprocess  # noqa: E402
r = subprocess.run([sys.executable, os.path.join(HERE, "frame-ai"), "make", "", "--json"], capture_output=True, text=True, env=dict(os.environ, HOME=TMP))
d = json.loads(r.stdout.strip().splitlines()[-1])
check("frame-ai make with an empty box fails politely in JSON", r.returncode == 1 and d["ok"] is False and "Describe" in d["error"], r.stdout + r.stderr)

shutil.rmtree(TMP, ignore_errors=True)
print("%d ok, %d failed" % (OK, FAIL))
sys.exit(1 if FAIL else 0)

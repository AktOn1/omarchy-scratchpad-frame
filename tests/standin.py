#!/usr/bin/env python3
"""Stand-in servers for the VM check: one local web server that plays BOTH a text AI (OpenAI-style chat) and an image model
(ComfyUI-style), so the whole Make frame path can run without any real AI. Nothing leaves the machine.
  python3 standin.py PORT [--seen FILE]
The picture it returns is drawn here without any library: gold scrolls in the bottom-right corner on a plain black background.
Every request body is appended to FILE (default /tmp/standin-seen.jsonl) so a check can see what was sent where."""
import sys
sys.dont_write_bytecode = True
import http.server
import json
import struct
import urllib.parse
import zlib

SEEN = "/tmp/standin-seen.jsonl"
RECIPE = {"name": "Mossy night", "style": "FOLIAGE", "colors": {"accent": "#2e8b57", "background": "#0b1a12"},
          "ornament": "curling fern fronds and tiny moss flowers"}


def picture(size=768):
    """a PNG (RGB) of a gold scroll in the bottom-right corner on black"""
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            u, v = size - 1 - x, size - 1 - y            # distance from the bottom-right corner
            bar = (30 <= v <= 80 and u <= 460) or (30 <= u <= 80 and v <= 460)
            ring = 3200 <= (u - 190) ** 2 + (v - 190) ** 2 <= 4800
            row += bytes((212, 175, 55)) if bar or ring else bytes((0, 0, 0))
        rows.append(bytes(row))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))


PIC = picture()


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
            return self.reply({"CheckpointLoaderSimple": {"input": {"required": {"ckpt_name": [["standin-model.safetensors"]]}}}})
        if p.startswith("/history/"):
            return self.reply({"p1": {"status": {"completed": True, "status_str": "success"},
                                      "outputs": {"9": {"images": [{"filename": "x.png", "subfolder": "", "type": "output"}]}}}})
        if p == "/view":
            return self.reply(PIC, "image/png")
        self.send_error(404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        with open(SEEN, "a") as f:
            f.write(json.dumps({"path": self.path, "body": body}) + "\n")
        if self.path == "/prompt":
            return self.reply({"prompt_id": "p1"})
        self.reply({"choices": [{"message": {"content": json.dumps(RECIPE)}}], "usage": {"prompt_tokens": 5, "completion_tokens": 7}})


if __name__ == "__main__":
    if "--seen" in sys.argv:
        SEEN = sys.argv[sys.argv.index("--seen") + 1]
    http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()

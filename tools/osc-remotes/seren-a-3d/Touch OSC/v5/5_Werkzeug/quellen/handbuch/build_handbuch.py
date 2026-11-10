"""HANDBUCH.html = page frame (head, style, script) + body.html with the two pictures inlined."""
import base64, sys
from pathlib import Path
HERE = Path(__file__).parent
def body_html(src):
    b = src
    for key, img in (("__IMG_SPACE__", "img_space.jpg"), ("__IMG_ROOM__", "img_room.jpg"), ("__IMG_LOOKS__", "img_looks.jpg")):
        b = b.replace(key, base64.b64encode((HERE / img).read_bytes()).decode())
    return b
def build(old_body_src, new_body_src, frame):
    old = body_html(old_body_src)
    i = frame.index(old)
    return frame[:i] + body_html(new_body_src) + frame[i + len(old):]
if __name__ == "__main__":
    old_src, frame = Path(sys.argv[1]).read_text(), (HERE / "HANDBUCH.html").read_text()
    out = build(old_src, (HERE / "body.html").read_text(), frame)
    (HERE / "HANDBUCH.html").write_text(out)
    print("HANDBUCH.html", len(out))

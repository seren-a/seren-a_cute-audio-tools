"""MultiEQ.oxie16: the OXI App scene for E16_MultiEQ.lua, with pages 1 and 3 wired to the script
(turn IDs 1-16, push IDs 17-32 on both pages; the script tells them apart by page).
Built from a scene the OXI App exported (DAW-Link.oxie16) with tools/make_scene.py's minifier.

    python3 make_e16_scene.py TEMPLATE.oxie16 E16_MultiEQ.lua OUT.oxie16
"""
import json, sys
sys.path.insert(0, "/tmp/claude-0/-home-claude/1d4028fa-12da-5404-ac70-1ceecfe42680/scratchpad/e16repo/repo/tools")
from make_scene import minify, rename_locals, assigns

PAGES = {0: "MultiEQ", 2: "Comp"}                    # 0-based page index -> title
COMP_ABBR = ["Thr", "Rat", "Att", "Rel", "Knee", "Gain", "Look", "Omni",
             "Thr", "Rat", "Att", "Rel", "Knee", "Gain", "Solo", "Spur"]

def build(template, script, out):
    src = open(script, encoding="utf-8").read()
    code = rename_locals(minify(src))
    assert len(code.encode()) <= 8192, len(code)
    scene = json.load(open(template, encoding="utf-8"))
    a = assigns(src)
    import copy
    wired_tpl = copy.deepcopy(scene["pages"][0]["encoders"])   # page 1 of DAW-Link: wired, runs on the device
    scene["title"] = "MultiEQ"
    scene["code"] = {"code": code, "fullScript": src.replace("\n", "\r\n"), "scriptName": "E16_MultiEQ"}
    for pg, page in enumerate(scene["pages"]):
        wired = pg in PAGES
        page["title"] = PAGES.get(pg, f"P.{pg + 1}")
        for e, enc in enumerate(page["encoders"], start=1):
            t, p = enc["turn_actions"][0], enc["push_action"]
            if not wired:
                enc["name"] = enc["abbr"] = ""
                for act in enc["turn_actions"] + [p]:
                    act["type"], act["scriptId"] = 0, 0
                continue
            enc["turn_actions"] = copy.deepcopy(wired_tpl[e - 1]["turn_actions"])
            enc["push_action"] = p = copy.deepcopy(wired_tpl[e - 1]["push_action"])
            t = enc["turn_actions"][0]
            abbr = a[e]["abbr"] if pg == 0 else COMP_ABBR[e - 1]
            enc["name"] = enc["abbr"] = abbr
            t["type"], t["scriptId"] = 11, e                 # 11 = Script turn
            t["lower"], t["upper"] = 0, 127
            p["type"], p["scriptId"] = 12, 16 + e            # 12 = Script push
            for act in enc["turn_actions"][1:]:
                act["type"], act["scriptId"] = 0, 0
    json.dump(scene, open(out, "w", encoding="utf-8"), separators=(",", ":"))
    return scene, len(code)

if __name__ == "__main__":
    sc, n = build(*sys.argv[1:4])
    print("wrote", sys.argv[3], "script", n, "bytes; pages", [p["title"] for p in sc["pages"]][:4])

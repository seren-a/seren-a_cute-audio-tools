"""seren-a_E16.oxie16: ONE OXI App scene for seren_E16.lua, pages 1-4 wired to the script
(turn IDs 1-16, push IDs 17-32 on every page; the script tells them apart by page).
Built from a scene the OXI App exported (DAW-Link.oxie16) with tools/make_scene.py's minifier.

    python3 make_seren_e16.py TEMPLATE.oxie16 seren_E16.lua OUT.oxie16
"""
import copy, json, sys
sys.path.insert(0, "/tmp/claude-0/-home-claude/1d4028fa-12da-5404-ac70-1ceecfe42680/scratchpad/e16repo/repo/tools")
from make_scene import minify, rename_locals

# 0-based page index -> (title, 16 abbreviations shown before the DAW sends names)
PAGES = {
    0: ("DAW Link", ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "Q8"]),
    1: ("MultiEQ", ["A1", "A2", "A3", "Dir", "A4", "A5", "A6", "Omni", "B1", "B2", "B3", "B4", "B5", "B6", "Solo", "Spur"]),
    2: ("Comp", ["Thr", "Rat", "Att", "Rel", "Knee", "Mkup", "Look", "Omni", "Thr", "Rat", "Att", "Rel", "Knee", "Mkup", "Solo", "Spur"]),
    3: ("Reverb", ["Size", "Time", "Fade", "Mix", "LoF", "HiF", "Pres", "Omni", "C1", "C2", "C3", "C4", "C5", "CPre", "Solo", "Spur"]),
}


def build(template, script, out):
    src = open(script, encoding="utf-8").read()
    code = rename_locals(minify(src))
    assert len(code.encode()) <= 8192, len(code)
    scene = json.load(open(template, encoding="utf-8"))
    wired_tpl = copy.deepcopy(scene["pages"][0]["encoders"])   # page 1 of DAW-Link: wired, runs on the device
    scene["title"] = "seren.a E16"
    scene["code"] = {"code": code, "fullScript": src.replace("\n", "\r\n"), "scriptName": "seren_E16"}
    for pg, page in enumerate(scene["pages"]):
        title, abbrs = PAGES.get(pg, (f"P.{pg + 1}", None))
        page["title"] = title
        for e, enc in enumerate(page["encoders"], start=1):
            if not abbrs:
                enc["name"] = enc["abbr"] = ""
                for act in enc["turn_actions"] + [enc["push_action"]]:
                    act["type"], act["scriptId"] = 0, 0
                continue
            enc["turn_actions"] = copy.deepcopy(wired_tpl[e - 1]["turn_actions"])
            enc["push_action"] = p = copy.deepcopy(wired_tpl[e - 1]["push_action"])
            t = enc["turn_actions"][0]
            enc["name"] = enc["abbr"] = abbrs[e - 1]
            t["type"], t["scriptId"] = 11, e                 # 11 = Script turn
            t["lower"], t["upper"] = 0, 127
            p["type"], p["scriptId"] = 12, 16 + e            # 12 = Script push
            for act in enc["turn_actions"][1:]:
                act["type"], act["scriptId"] = 0, 0
    json.dump(scene, open(out, "w", encoding="utf-8"), separators=(",", ":"))
    return scene, len(code)


if __name__ == "__main__":
    sc, n = build(*sys.argv[1:4])
    print("wrote", sys.argv[3], "script", n, "bytes; pages", [p["title"] for p in sc["pages"]][:5])

"""Reads a Midi Fighter Utility .mfs file (Twister): global settings + one record per encoder.

Format (checked against the DJTT open-source firmware, config.c): header 00 42, then tag/value
pairs for the global settings (tag 0 = system MIDI channel, 33 = colour map, ...), then per
encoder `00 <n> 01 00 1E` + 15 tag/value pairs, tags 10-24 in this order:"""
import json, sys

FIELDS = ["has_detent", "movement", "switch_action_type", "switch_midi_channel", "switch_midi_number",
          "switch_midi_type", "encoder_midi_channel", "encoder_midi_number", "encoder_midi_type",
          "active_color", "inactive_color", "detent_color", "indicator_display_type", "is_super_knob",
          "encoder_shift_midi_channel"]
ENC_TYPES = {0: "note", 1: "cc", 2: "relative", 3: "cc+switch velocity", 4: "rel mouse drag", 5: "rel mouse scroll"}

def parse(data):
    first = data.index(bytes([0x00, 0x01, 0x01, 0x00, 0x1E]), 4)
    glob = {}
    i = 2
    while i + 1 < first:
        glob[data[i]] = data[i + 1]; i += 2
    encs = []
    i = first
    while i + 5 <= len(data):
        assert data[i] == 0 and data[i + 2:i + 5] == bytes([1, 0, 0x1E]), f"record at {i:#x}"
        n, body = data[i + 1], data[i + 5:i + 5 + 30]
        rec = {"encoder": n}
        for k in range(0, 30, 2):
            tag, val = body[k], body[k + 1]
            rec[FIELDS[tag - 10]] = val
        encs.append(rec); i += 35
    return glob, encs

if __name__ == "__main__":
    g, e = parse(open(sys.argv[1], "rb").read())
    print("global:", {k: v for k, v in sorted(g.items())})
    print("system MIDI channel (1-based):", g.get(0), " colour map:", "2026" if g.get(33) else "classic")
    print(len(e), "encoders")
    for r in e[:3] + e[16:17] + e[48:49]:
        print(r)
    types = {ENC_TYPES.get(r["encoder_midi_type"], r["encoder_midi_type"]) for r in e}
    chans = {r["encoder_midi_channel"] for r in e}
    print("encoder types:", types, " channels:", chans)
    print("CC per bank:", [[r["encoder_midi_number"] for r in e[b * 16:(b + 1) * 16]] for b in range(len(e) // 16)])
    print("active colours:", sorted({r["active_color"] for r in e}))
    json.dump({"global": g, "encoders": e}, open(sys.argv[2], "w"), indent=0) if len(sys.argv) > 2 else None

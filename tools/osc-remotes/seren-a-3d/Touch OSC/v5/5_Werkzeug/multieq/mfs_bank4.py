"""Writes a copy of a Midi Fighter Utility .mfs file with bank 4 set up for Reaper_MultiEQ.lua:
encoders relative (ENC 3FH/41H), movement direct, no detent, switch action CC Hold.
Everything else (CC numbers, channels, colours, banks 1-3, global settings) stays as it was.

    python3 mfs_bank4.py <in.mfs> <out.mfs>
"""
import sys
sys.path.insert(0, "/home/claude/mft-view")
import mfs_parse

SET = {10: 0,   # has_detent: off
       11: 0,   # movement: DIRECT
       12: 0,   # switch_action_type: CC_HOLD
       18: 2}   # encoder_midi_type: SEND_REL_ENC (ENC 3FH/41H)

def patch(data):
    data = bytearray(data)
    first = data.index(bytes([0x00, 0x01, 0x01, 0x00, 0x1E]), 4)
    i = first
    while i + 5 <= len(data):
        n = data[i + 1]
        if 49 <= n <= 64:
            for k in range(0, 30, 2):
                tag = data[i + 5 + k]
                if tag in SET:
                    data[i + 5 + k + 1] = SET[tag]
        i += 35
    return bytes(data)

if __name__ == "__main__":
    src = open(sys.argv[1], "rb").read()
    out = patch(src)
    open(sys.argv[2], "wb").write(out)
    g0, e0 = mfs_parse.parse(src); g1, e1 = mfs_parse.parse(out)
    assert g0 == g1 and e0[:48] == e1[:48] and len(src) == len(out)
    for a, b in zip(e0[48:], e1[48:]):
        diff = {k for k in a if a[k] != b[k]}
        assert diff <= {"has_detent", "movement", "switch_action_type", "encoder_midi_type"}, diff
        assert b["encoder_midi_type"] == 2 and b["switch_action_type"] == 0 and b["movement"] == 0
        assert b["encoder_midi_number"] == a["encoder_midi_number"] and b["switch_midi_channel"] == a["switch_midi_channel"]
    print("bank 4 patched; CC", [e["encoder_midi_number"] for e in e1[48:]][:3], "... channels", e1[48]["encoder_midi_channel"], e1[48]["switch_midi_channel"])

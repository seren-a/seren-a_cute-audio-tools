"""Nuendo v3 (Mock): Parameter nach Namen, nichts anderes wird angefasst."""
import json, subprocess, sys, os
D = os.path.dirname(os.path.abspath(__file__))
d = json.loads(subprocess.check_output(['node', os.path.join(D, 'scenario_v3.js'), os.path.join(D, '..', 'nuendo', 'serena_TouchOSC3D.js')]))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
flags = {x[4]: x[5] for x in d['titlesOut'] if x[3] == 3}
check(flags == {0: 9, 1: 5}, f'Flags: Spur 1 StereoEncoder + Rotator, Spur 2 MultiEncoder, Spur 3 nichts ({flags})')
check(d['orderOut'] == [], 'Ambisonics Order geht nie raus')
v = d['valuesOut']
def val14(msgs, st, cc):
    msb = [m[2] for m in msgs if m[0] == st and m[1] == cc]; lsb = [m[2] for m in msgs if m[0] == st and m[1] == cc + 32]
    return (msb[-1] * 128 + lsb[-1]) / 16383 if msb and lsb else None
check(abs(val14(v, 0xBC, 0) - 0.75) < 1e-3, 'Spur 1 Azimuth -> Kanal 13 CC 0')
check(abs(val14(v, 0xBC, 2) - 0.5625) < 1e-3, 'Spur 1 Width -> CC 2')
check(abs(val14(v, 0xBC, 4) - 0.25) < 1e-3, 'Spur 2 MultiEncoder Master Azimuth -> Objekt 2 Azimuth')
check(val14(v, 0xBC, 8) is None, 'Pro-Q-Parameter "Azimuth Angle" wird ignoriert')
check(abs(val14(v, 0xB6, 0) - 0.6) < 1e-3, 'Spur 1 Yaw -> Kanal 7 CC 0')
s = {x['label']: x['v'] for x in d['inSets']}
check(s == {'custom:Ov 1 I5 7': 0.3, 'custom:Ov 2 I5 5': 0.4, 'custom:Ov 1 I5 10': 0.7, 'custom:Ov 1 I6 4': 0.45},
      f'Eingaben landen nur auf erkannten Parametern ({s})')
so = d['selOut']
check(so[0][3] == 9 and so[0][4] == 4, 'gewählte Spur: MultiEncoder mit 4 Eingängen gemeldet')
check(abs(val14(so, 0xB8, 8) - 0.25) < 1e-3 and abs(val14(so, 0xB8, 10) - 1.0) < 1e-3, 'Eingang 3 Azimuth/Gain -> Kanal 9 CC 8/10')
check(abs(val14(so, 0xBF, 1) - 0.5) < 1e-3, 'Panner CC 1 = Master Azimuth beim MultiEncoder')
check([0xF0, 0x7D, 0x54, 15] + [ord(c) for c in '12.5'] + [0xF7] in so, 'Anzeigewert Yaw an den Panner')
ss = {x['label']: x['v'] for x in d['selSets']}
check(ss == {'custom:Sel I5 18': 0.8, 'custom:Sel I5 4': 0.55, 'custom:Sel I6 3': 0.65}, f'Eingaben gewählte Spur ({ss}); Width beim MultiEncoder: nichts')
check(len(d['log']) >= 7 and any('kein IEM' in l for l in d['log']), 'Monitor-Log meldet, was erkannt wurde')
# MultiPanner via Quick Controls, recognised by name (Isabella's QC order)
check(d['mpOut'] == [[186, 0, 95], [186, 32, 127], [186, 2, 32], [186, 34, 0], [224, 127, 127], [227, 0, 64], [233, 0, 0]],
      f"MP-QCs: X (QC7) und Z (QC6) in der Uebersicht, Panner X/RotZ/Size per Pitchbend ({d['mpOut']})")
yo = d['mpYOut']
check(len(yo) == 3 and yo[0][:2] == [186, 1] and yo[0][2] == round(0.8 * 16383) >> 7 and yo[2][:1] == [225] and ((yo[2][2] << 7) | yo[2][1]) == round(0.8 * 16383),
      f"MP Y gespiegelt: Nuendo 0.2 -> Oberflächen 0.8 (oben = vorn) ({yo})")
check(d['mpSets'] == [{'label': 'custom:Ov MP 1 QC5', 'v': 0.4}, {'label': 'custom:Sel MP QC8', 'v': 0.3}],
      f"MP-QCs: Geraet -> Y auf QC5 (gespiegelt: oben = vorn), Width auf QC8, Tilt X (nicht belegt) nichts ({d['mpSets']})")
check(any('X=QC7 Y=QC5 Z=QC6' in l for l in d['log']), 'MP-QCs im LOG')
# 32 objects: object 21 via SysEx 10, track types, bank = 16 channels
check(d['o20Out'] == [[240, 125, 79, 10, 0, 20, 0, 64, 0, 247]], f"Objekt 21: Azimuth per SysEx 10 ({d['o20Out']})")
check(len(d['o20Sets']) == 1 and d['o20Sets'][0]['label'] == 'custom:Ov 21 I5 8', f"Objekt 21: Elevation vom Geraet per SysEx 10 ({d['o20Sets']})")
check(d['typeOut'] == [[240, 125, 79, 3, 20, 17, 247]], f"FX-Kanal erkannt: Flags 1+16 ({d['typeOut']})")
check(d['bankOut'] == [[240, 125, 79, 5, 1, 247]] and d['triggered'] == 16, f"Bank weiter = 16 Kanaele ({d['bankOut']}, {d['triggered']} Schritte)")
# dearVR PRO in Insert 4 / Insert 5
def dvpos(msgs, o):
    r = {}
    for m in msgs:
        if m[:5] == [0xF0, 0x7D, 0x4F, 10, 3] and m[5] == o: r[m[6]] = (m[7] * 128 + m[8]) / 16383 * 64 - 32
    return r
dv = d['dvOut']
p3 = dvpos(dv, 3); p4 = dvpos(dv, 4)
check(abs(p3.get(0, 99) - 2) < 0.01 and abs(p3.get(1, 99) - 1) < 0.01 and abs(p3.get(2, 99) - 0.5) < 0.01,
      f'dearVR Insert 4, kartesisch: X 2 m rechts, Z 1 m vorn, Y 0,5 m hoch ({p3})')
check(abs(p4.get(0, 99) - 3) < 0.01 and abs(p4.get(1, 99)) < 0.01, f'dearVR Insert 5, polar: Az 90 / 3 m = 3 m rechts ({p4})')
rooms = [m for m in dv if m[:4] == [0xF0, 0x7D, 0x4F, 14]]
def rname(m): return ''.join(chr(c) for c in m[17:-1])
check(any(m[4] == 3 and rname(m) == 'Medium Room' and (m[5] * 128 + m[6]) == 380 for m in rooms)
      and any(m[4] == 4 and rname(m) == 'Studio Room' for m in rooms), f'Raum aus Preset-Tabelle (cmd 14) {[(m[4], rname(m)) for m in rooms]}')
check(not any(m[0] == 0xBC and m[1] in (12, 44) for m in dv), 'dearVR-Azimuth geht nicht als IEM-Azimuth raus')
check(d['dvSets'] == [], f"Oberflaechen verschieben dearVR nicht ({d['dvSets']})")
check([0xF0, 0x7D, 0x4F, 14, 3, 0xF7] in d['dvByp'], f"Insert 4 umgangen -> kein Raum mehr ({d['dvByp']})")
check(any('dearVR PRO (X/Y/Z, Az/El/Dist, Preset)' in l for l in d['dvLog']), f"LOG meldet dearVR ({[l for l in d['dvLog'] if 'dearVR' in l][:2]})")
# v5.5: Inserts 5-9
so5 = d['slotOut']
check(abs(val14(so5, 0xBC, 24) - 0.2) < 1e-3 and abs(val14(so5, 0xB6, 24) - 0.7) < 1e-3, 'Encoder in Insert 6, Rotator in Insert 9 werden gefunden')
check(d['slotSets'] == [{'label': 'custom:Ov 7 I9 3', 'v': 0.33}], f"Yaw vom Geraet landet in Insert 9 ({d['slotSets']})")
check(abs(val14(d['bypOut'], 0xBC, 28) - 0.9) < 1e-3, 'Insert 5 umgangen: Insert 6 zaehlt, sein Azimuth geht raus')
check(d['bypSets'] == [{'label': 'custom:Ov 8 I6 7', 'v': 0.44}], f"Eingabe geht an Insert 6 ({d['bypSets']})")
print("\nALL OK" if fails == 0 else f"\n{fails} FAILED")

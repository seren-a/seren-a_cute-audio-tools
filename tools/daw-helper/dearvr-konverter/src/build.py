import json,struct,os
HERE=os.path.dirname(os.path.abspath(__file__))
ORDER=["OutputMode","CoordinateSystem","Azimuth","Elevation","Distance","X","Y","Z","DirectGain","AzimuthScale","DistanceScale","Occlusion","VirtualAcoustics","RoomSize","ReverbON","ReverbGain","ReverbLowPass","ReverbHighPass","ReflectionON","ReflectionGain","ReflectionLowPass","ReflectionHighPass","RealTimeAuralization","TopWall","BottomWall","FrontWall","BackWall","LeftWall","RightWall","Bypass","BassBoost","PerformanceMode","StereoWidth","MasterGain","LfeGain","Clarity","xyPadView","xyPadZoom"]
src=json.load(open(os.path.join(HERE,'werkspresets_pro2.json')))
def f32(s):
    x=float(s)
    if x==int(x): return str(int(x))
    return ('%.9g'%struct.unpack('f',struct.pack('f',x))[0])
names=list(src); vals=[]
for n in names:
    d=dict(src[n]); assert list(d)==ORDER,(n,list(d)); vals.append([f32(d[k]) for k in ORDER])
html=open(os.path.join(HERE,'werkstatt.template.html'),encoding='utf-8').read().replace('__FACTORY_JSON__',json.dumps({"names":names,"vals":vals},ensure_ascii=False,separators=(',',':')))
assert html.splitlines()[3].strip()=='<meta charset="UTF-8">' or '<meta charset="UTF-8">' in html.splitlines()[3]
open(os.path.join(HERE,'..','dearvr-preset-werkstatt.html'),'w',encoding='utf-8').write(html)
print(len(html),len(names))

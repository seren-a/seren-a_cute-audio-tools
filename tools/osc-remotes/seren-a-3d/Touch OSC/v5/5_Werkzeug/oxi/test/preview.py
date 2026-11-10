import sys; sys.argv=['x']
exec(open('test_puzzle.py').read().split("rig = Rig(SETUP)")[0])
from PIL import Image, ImageDraw
def shot(rig, name):
    W=16*36+40; img=Image.new('RGB',(W, 8*36+40+64*4+20),(18,16,24)); d=ImageDraw.Draw(img)
    scr=rig.screen()
    for y in range(64):
        for x in range(128):
            if scr[y][x]=='#': d.rectangle([20+x*4,20+y*4,20+x*4+3,20+y*4+3],fill=(230,240,255))
    oy=40+64*4
    for y in range(8):
        for x in range(16):
            c=rig.grid.get((y,x),(0,0,0)); f=lambda v: {0:0,1:35,9:110,15:170}.get(v,255)
            d.rounded_rectangle([20+x*36,oy+y*36,20+x*36+30,oy+y*36+30],5,fill=tuple(f(v) for v in c),outline=(50,50,60))
    img.save(name)
S='/tmp/claude-0/-home-claude/1d4028fa-12da-5404-ac70-1ceecfe42680/scratchpad/'
rig = Rig(SETUP); rig.run(5); rig.pad(1,2); rig.knob(1,2); rig.run(3); shot(rig, S+'oxi_drehen.png'); rig.run(60); shot(rig, S+'oxi_puzzle.png')
rig.press(18); rig.run(3); shot(rig, S+'oxi_menu.png'); rig.press(14); rig.run(3); shot(rig, S+'oxi_menu2.png'); rig.press(18); rig.run(2)
rig.press(8); rig.run(3); rig.pad(1,1); rig.run(3); shot(rig, S+'oxi_send16.png')
rig.press(8); rig.run(3); rig.pad(3,0); rig.run(3); shot(rig, S+'oxi_send32.png')

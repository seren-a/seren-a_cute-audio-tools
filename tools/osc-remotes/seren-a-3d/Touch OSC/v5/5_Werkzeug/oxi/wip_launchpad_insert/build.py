"""core.lua + font.lua -> Reaper_OXI_Puzzle.lua"""
import os
H = os.path.dirname(os.path.abspath(__file__))
s = open(os.path.join(H, 'core.lua'), encoding='utf-8').read()
f = open(os.path.join(H, 'font.lua'), encoding='utf-8').read()
open(os.path.join(H, 'Reaper_OXI_Puzzle.lua'), 'w', encoding='utf-8').write(s.replace('--@@FONT@@', f))

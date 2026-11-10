"""Loads the built Twister View into the TouchOSC mock; helpers for tests."""
import importlib, os, sys
sys.path.insert(0, "/home/claude/mft-view")
import py2tosc

class View:
    def __init__(self, tosc, lua_version=None):
        lua = importlib.import_module("lupa." + (lua_version or os.environ.get("LUA", "lua51")))
        self.doc = py2tosc.load(tosc)
        self.L = lua.LuaRuntime(unpack_returned_tuples=True); self.g = self.L.globals()
        self.L.execute(open(os.path.join(os.path.dirname(__file__), 'tosc_mock.lua')).read())
        self.L.execute("""function sendMIDI(m, conns) local b = {} for i = 1, #m do b[i] = m[i] end
          sent[#sent+1] = {kind='midi', bytes=b} end""")
        for c in self.doc.walk():
            n = c.get("name")
            if n:
                f = c.frame
                self.g.makeControl(n, c.control_type.value, f.x, f.y, f.w, f.h, c.get("visible", True))
        # real TouchOSC: restricted globals (strict sandbox), callbacks the script doesn't define are optional
        for cb in ("init", "update", "onReceiveMIDI", "onReceiveNotify", "onReceiveOSC"):
            self.L.execute(f"function {cb}() end")
        self.L.execute(open(os.path.join(os.path.dirname(__file__), 'tosc_strict.lua')).read())
        self.L.execute(self.doc.root.get("script"))
        self.c = self.g.controls
        self.L.execute("init()")
        self.tick()
    def run(self, code): return self.L.execute(code)
    def tick(self, ms=16, n=1):
        for _ in range(n): self.run(f"clock = clock + {ms}; update()")
    def midi(self, *b):
        self.run("onReceiveMIDI({" + ",".join(str(int(x)) for x in b) + "}, {true})")
    def text(self, n): return self.c[n]['values']['text']
    def sent(self):
        out = [list(self.g.sent[i].bytes.values()) for i in range(1, len(self.g.sent) + 1) if self.g.sent[i].kind == 'midi']
        self.run("sent = {}"); return out
    def bar(self, s):
        return self.c[f'c{s}_bar']['frame']['w'] / self.c[f'c{s}_barbg']['frame']['w']
    def cells(self):
        return [(self.text(f'c{s}_name'), self.text(f'c{s}_val')) for s in range(1, 17)]

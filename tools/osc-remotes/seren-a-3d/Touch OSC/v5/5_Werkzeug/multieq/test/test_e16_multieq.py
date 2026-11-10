"""E16_MultiEQ.lua on the OXI E16 mock (Lua 5.4)."""
import importlib, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
MOCK = os.environ.get('E16MOCK', os.path.join(HERE, 'e16mock.lua'))
lua = importlib.import_module("lupa.lua54")
L = lua.LuaRuntime()
L.globals().MOCK = MOCK
L.globals().SCRIPT = os.path.join(HERE, '..', 'E16_MultiEQ.lua')
L.execute(open(os.path.join(HERE, 'test_e16_multieq.lua')).read())

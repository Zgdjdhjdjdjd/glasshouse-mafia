"""Run against an empty disposable PostgreSQL database with all game migrations applied.
Requires MAFIA_TEST_DB_URL. Never point this test at the live game database.
"""
import json, os, subprocess, secrets
BASE = ["psql", os.environ["MAFIA_TEST_DB_URL"], "-X", "-At", "-v", "ON_ERROR_STOP=1"]
def sql(q):
 r=subprocess.run(BASE+['-c',q],capture_output=True,text=True)
 if r.returncode: raise RuntimeError(r.stderr)
 return r.stdout.strip()
def lit(v):
 if v is None:return 'NULL'
 return "'"+str(v).replace("'","''")+"'"
def rpc(fn,args):
 q='SET ROLE anon; SELECT public.'+fn+'('+','.join(k+'=>'+lit(v) for k,v in args.items())+');'
 return json.loads(sql(q).splitlines()[-1])
admin=secrets.token_hex(32)
sql("INSERT INTO public.admin_sessions(token) VALUES(public._mafia_hash("+lit(admin)+"));")
players=[]
for i,role in enumerate(['mafia','mafia','mafia','doctor','detective','joker','civilian','civilian','civilian']):
 token=secrets.token_hex(32); name=['Mara','Nico','Luca','Doctor','Detective','Joker','Alex','Sam','Casey'][i]
 id=sql('INSERT INTO public.players(token,name,role) VALUES('+','.join(map(lit,[token,name,role]))+') RETURNING id;').splitlines()[0]
 players.append(dict(token=token,name=name,role=role,id=id))
sql("UPDATE public.game SET phase='playing' WHERE id=1;")
m,d,det,j,c=players[0],players[3],players[4],players[5],players[6]

def action(name, target=None, round=0):
 return rpc('mafia_night_admin',dict(p_admin=admin,p_action=name,p_target=target,p_round=round))
def state(player):
 return rpc('mafia_state',dict(p_token=player['token'],p_admin=None))
assert action('startNight')['ok']
for player in [m,d,det]:
 target=m if player==det else c
 assert rpc('mafia_night_action',dict(p_token=player['token'],p_target=target['id'],p_round=1))['ok']
assert state(det)['night']['feedback'] is None
assert not rpc('mafia_night_action',dict(p_token=m['token'],p_target=c['id'],p_round=1))['ok']
assert not rpc('mafia_night_action',dict(p_token=c['token'],p_target=m['id'],p_round=1))['ok']
assert not rpc('mafia_night_admin',dict(p_admin='invalid',p_action='closeNight',p_target=None,p_round=1))['ok']
assert action('closeNight',round=1)['ok']
assert action('resolveNight',c['id'],1)['ok']
assert state(c)['me']['alive']
assert state(d)['night']['feedback']['saved'] is True
assert state(det)['night']['feedback']['isMafia'] is True
assert state(m)['night']['feedback'] is None
assert 'nightChoices' not in json.dumps(state(c))
assert not action('resolveNight',j['id'],1)['ok']
assert action('startNight',round=1)['ok']
assert rpc('mafia_night_action',dict(p_token=d['token'],p_target=c['id'],p_round=2))['ok']
assert rpc('mafia_night_action',dict(p_token=det['token'],p_target=c['id'],p_round=2))['ok']
assert action('closeNight',round=2)['ok']
assert action('resolveNight',j['id'],2)['ok']
assert not state(j)['me']['alive']
assert state(d)['night']['feedback']['saved'] is False
assert state(det)['night']['feedback']['isMafia'] is False
assert state(c)['game']['winner'] is None
assert rpc('mafia_admin',dict(p_admin=admin,p_action='reset',p_player=None,p_value=None))['ok']
assert state(det)['night']['feedback'] is None
print('Night integration rules passed: privacy, admin control, protection, investigation, Joker and reset')

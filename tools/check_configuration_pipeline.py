"""Exercise Excel input parsing, validation, export and actual Godot configuration reads."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import export_balance as exporter

root = Path(__file__).resolve().parent.parent
schema = json.loads((root/'design/workbook-schema.json').read_text(encoding='utf-8'))
workbook = exporter.read_planner_bundle(root/'design/数值策划',schema)
documents = exporter.assemble(copy.deepcopy(workbook),schema)
exporter.validate(documents)
def fingerprint():
    return {name:hashlib.sha256((root/'data'/f'{name}.json').read_bytes()).hexdigest() for name in schema['documents']}
before = fingerprint()

def set_cell(sheet, match_column, match_value, value_column, value):
    headers = workbook[sheet][2]
    match = headers.index(match_column)
    target = headers.index(value_column)
    for row in workbook[sheet][3:]:
        if len(row)>match and row[match]==match_value:
            while len(row)<=target: row.append(None)
            row[target] = value
            return
    raise AssertionError(f'Missing test input: {sheet}/{match_value}')

set_cell('Parameters','key','balance.player.max_hp','value',110)
set_cell('Enemies','id','slime','hp',35)
set_cell('Upgrades','id','power','value',1.25)
set_cell('EquipmentStats','equipment_id','iron_sword','value',7)
set_cell('NodeRoster','position',1,'modifiers','fortified')
set_cell('NodeStates','id','fortified','defense_add',9)
changed = exporter.assemble(copy.deepcopy(workbook),schema)
exporter.validate(changed)
target = root/'builds/iteration-0.7/configuration-fixture'
target.mkdir(parents=True,exist_ok=True)
for name,document in changed.items(): (target/(name+'.json')).write_bytes(exporter.serialized(document))
engine = root/'.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
result = subprocess.run([str(engine),'--headless','--path',str(root),'--script','tools/configuration_probe.gd','--','--data-root=res://builds/iteration-0.7/configuration-fixture'],capture_output=True,text=True,encoding='utf-8',cwd=root,timeout=30)
if result.returncode or 'SCRIPT ERROR' in result.stdout+result.stderr: raise AssertionError(result.stdout+result.stderr)
line = next(line for line in result.stdout.splitlines() if line.startswith('CONFIG_PROBE:'))
actual = json.loads(line.removeprefix('CONFIG_PROBE:'))
expected = {'player_max_hp':110,'player_damage':28.5,'enemy_base_hp':35,'enemy_final_hp':37.8,'enemy_final_defense':9,'node':1}
assert all(abs(actual[key]-value)<1e-6 for key,value in expected.items()),actual
assert before==fingerprint(),'Temporary test changed release data on disk'

bad = copy.deepcopy(workbook)
bad['NodeRoster'][3][bad['NodeRoster'][2].index('enemies')] = 'missing_monster'
try:
    exporter.validate(exporter.assemble(bad,schema))
except (ValueError,KeyError): pass
else: raise AssertionError('Unknown monster reference was accepted')
bad = copy.deepcopy(workbook)
bad['Equipment'][3][bad['Equipment'][2].index('slot')] = 'missing_slot'
try:
    exporter.validate(exporter.assemble(bad,schema))
except (ValueError,KeyError): pass
else: raise AssertionError('Unknown equipment slot was accepted')
report={'passed':True,'scope':'Excel input cells parsed into documents; six changed values reflected by the actual Godot runtime; invalid cross references rejected; release files unchanged','actual':actual,'expected':expected,'release_fingerprints':before}
(root/'builds/iteration-0.7/configuration-pipeline.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PASS: Excel input changes affect actual runtime player, equipment, blessing, monster base and node-state values; release data unchanged')

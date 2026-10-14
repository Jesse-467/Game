"""Validate the Excel design source and export small deterministic runtime JSON files.

Uses the Python standard library. Excel is never read on Android.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent
NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
REL = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'

def column_index(address: str) -> int:
    n = 0
    for char in address:
        if not char.isalpha(): break
        n = n * 26 + ord(char.upper()) - 64
    return n - 1

def read_workbook(path: Path) -> dict[str, list[list]]:
    result = {}
    with zipfile.ZipFile(path) as archive:
        strings = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            for item in ET.fromstring(archive.read('xl/sharedStrings.xml')).findall('s:si', NS):
                strings.append(''.join(item.itertext()))
        links = {item.attrib['Id']: item.attrib['Target'] for item in ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))}
        workbook = ET.fromstring(archive.read('xl/workbook.xml'))
        for sheet in workbook.findall('s:sheets/s:sheet', NS):
            target = links[sheet.attrib[REL]]
            target = target.lstrip('/') if target.startswith('/') else 'xl/' + target
            rows = []
            for row in ET.fromstring(archive.read(target)).findall('s:sheetData/s:row', NS):
                number = int(row.attrib['r'])
                while len(rows) < number: rows.append([])
                values = rows[number - 1]
                for cell in row.findall('s:c', NS):
                    index = column_index(cell.attrib['r'])
                    while len(values) <= index: values.append(None)
                    kind = cell.attrib.get('t', 'n')
                    raw = cell.findtext('s:v', namespaces=NS)
                    if kind == 'inlineStr': value = ''.join(cell.find('s:is', NS).itertext())
                    elif kind == 's': value = strings[int(raw)]
                    elif kind == 'b': value = raw == '1'
                    elif kind == 'e': raise ValueError(f"{sheet.attrib['name']}!{cell.attrib['r']}: formula error {raw}")
                    elif raw is None: value = None
                    elif kind == 'str': value = raw
                    else:
                        value = float(raw)
                        if not math.isfinite(value): raise ValueError('Non-finite numeric input')
                        if value.is_integer(): value = int(value)
                    values[index] = value
            result[sheet.attrib['name']] = rows
    return result

def read_planner_bundle(directory: Path, schema: dict) -> dict:
    layout=json.loads((ROOT/'design/planner-schema.json').read_text(encoding='utf-8'))
    books={name:read_workbook(directory/name) for name in layout['books']}
    reverse={group:{name:key for key,name in mapping.items()} for group,mapping in layout['enums'].items()}
    def source_rows(spec):
        sheet=books[spec['book']][spec['sheet']]
        if sheet[2][:len(spec['fields'])]!=[field['label'] for field in spec['fields']]: raise ValueError(f"{spec['sheet']}: 请保留策划表列名")
        return [row for row in sheet[3:] if any(value is not None and value!='' for value in row)]
    # Names may change while the stable numeric content number stays the same.
    for table,spec in layout['tables'].items():
        fields={f['key']:(i,f) for i,f in enumerate(spec['fields'])}
        if 'id' not in fields or fields['id'][1].get('mode')!='number_id': continue
        name_key='name' if 'name' in fields else 'title' if 'title' in fields else ''
        if not name_key: continue
        for row in source_rows(spec):
            index,f=fields['id'];number=row[index]
            mapping=layout['entities'][f['group']]
            id=next((id for id,meta in mapping.items() if meta['number']==number),None)
            if id is None: raise ValueError(f"{spec['sheet']}: 新编号{number}尚未登记素材与机制")
            reverse.setdefault(f['group'],{})[row[fields[name_key][0]]]=id
    result={}
    for table,spec in layout['tables'].items():
        header=schema['tables'][table]['columns']
        matrix=[[],[],header]
        for raw in source_rows(spec):
            entry={}
            for index,f in enumerate(spec['fields']):
                value=raw[index] if index<len(raw) else None
                if value is None or value=='': continue
                mode=f.get('mode','')
                if mode.startswith('enum:'):
                    group=mode.removeprefix('enum:')
                    if schema['tables'][table]['types'].get(f['key'])=='csv':
                        names=str(value).replace('、',',').split(',')
                        try: value=[reverse[group][name.strip()] for name in names if name.strip()]
                        except KeyError as error: raise ValueError(f"{spec['sheet']}: 无法识别名称{error}") from error
                    else:
                        try: value=reverse[group][str(value)]
                        except KeyError as error: raise ValueError(f"{spec['sheet']}: 无法识别名称{value}") from error
                elif mode=='number_id':
                    value=next((id for id,meta in layout['entities'][f['group']].items() if meta['number']==value),None)
                    if value is None: raise ValueError(f"{spec['sheet']}: 内容编号尚未登记")
                elif mode=='plus_one': value-=1
                elif mode=='part': value=-1 if value=='主效果' else int(str(value).removeprefix('组合效果'))-1
                elif mode=='degrees': value=round(float(value)*math.pi/180,12)
                elif mode=='unlimited': value=0 if value=='不限' else value
                elif mode=='stat_value' and entry.get('stat') in ['crit_chance','elite_bonus','blast_fraction','slow_fraction']: value=round(float(value)/100,12)
                elif mode=='blessing_value':
                    if entry.get('effect') in ['damage_multiplier','move_speed_multiplier']: value=round(1+float(value),12)
                    elif entry.get('effect') in ['attack_interval_multiplier','stat_multiply']: value=round(1-float(value),12)
                    elif entry.get('stat')=='crit_chance': value=round(float(value)/100,12)
                entry[f['key']]=value
            key=[entry.get(field) for field in spec.get('key_fields',[])]
            if key in spec.get('default_keys',[]):
                defaults=spec['defaults'][spec['default_keys'].index(key)]
                entry={**defaults,**entry}
            elif not spec.get('key_fields') and len(matrix)-3<len(spec['defaults']): entry={**spec['defaults'][len(matrix)-3],**entry}
            matrix.append([','.join(entry[field]) if isinstance(entry.get(field),list) else entry.get(field) for field in header])
        result[table]=matrix
    parameters=[row.copy() for row in layout['defaults']['Parameters']]
    for item in layout['parameters']:
        sheet=books[item['book']][item['sheet']]
        row=next((row for row in sheet[3:] if row and row[0]==item['name']),None)
        if row is None or len(row)<2 or row[1] is None: raise ValueError('缺少策划参数：'+item['name'])
        value=row[1]
        if item['mode']=='bool':
            if value not in ['是','否']: raise ValueError('请选择是或否：'+item['name'])
            value=value=='是'
        elif item['mode']=='degrees': value=round(float(value)*math.pi/180,12)
        source=item['source'].copy();source['value']=value;parameters.append(source)
    columns=schema['tables']['Parameters']['columns']
    result['Parameters']=[[],[],columns]+[[row.get(key) for key in columns] for row in parameters]
    return result

def convert(value, kind: str, location: str):
    if value is None or value == '': return None
    if kind in ('int', 'number'):
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError(f'{location}: must be a numeric Excel cell')
        return value
    if kind == 'bool':
        if not isinstance(value, bool): raise ValueError(f'{location}: must be TRUE/FALSE')
        return value
    if not isinstance(value, str): raise ValueError(f'{location}: must be text')
    if kind == 'csv': return [part.strip() for part in value.split(',') if part.strip()]
    return value

def table_rows(workbook: dict, schema: dict, name: str) -> list[dict]:
    rows = workbook.get(name)
    if rows is None: raise ValueError(f'Missing sheet: {name}')
    spec = schema['tables'][name]
    header = rows[schema['header_row'] - 1]
    while header and header[-1] is None: header.pop()
    if header != spec['columns']:
        raise ValueError(f'{name}: keep the configured column names and order')
    result = []
    for number, cells in enumerate(rows[schema['header_row']:], schema['header_row'] + 1):
        if not any(value is not None and value != '' for value in cells): continue
        entry = {}
        for index, key in enumerate(spec['columns']):
            raw = cells[index] if index < len(cells) else None
            value = raw if name == 'Parameters' and key == 'value' else convert(raw, spec['types'][key], f'{name}!row{number}/{key}')
            if value is not None: entry[key] = value
        result.append(entry)
    return result

def set_path(document: dict, parts: list[str], value) -> None:
    for part in parts[:-1]: document = document.setdefault(part, {})
    document[parts[-1]] = value

def unique(rows: list[dict], key: str, label: str) -> dict:
    result = {}
    for row in rows:
        value = row[key]
        if value in result: raise ValueError(f'{label}: duplicate {key} {value}')
        result[value] = row
    return result

def assemble(workbook: dict, schema: dict) -> dict:
    tables = {name: table_rows(workbook, schema, name) for name in schema['tables']}
    docs = {id: {} for id in schema['documents']}
    versions = {}
    seen = set()
    for row in tables['Parameters']:
        key = row['key']
        if key in seen: raise ValueError(f'Duplicate parameter: {key}')
        seen.add(key)
        value = convert(row.get('value'), row['type'], key)
        if value is None: raise ValueError(f'Missing parameter: {key}')
        parts = key.split('.')
        if parts[0] == 'schema': versions[parts[1]] = value
        elif parts[0] == 'balance': set_path(docs['balance'], parts[1:], value)
        elif parts[0] == 'terrain': set_path(docs['arena_afflictions'], parts[1:], value)
        elif parts[0] == 'encounters': set_path(docs['encounters'], parts[1:], value)
        else: raise ValueError(f'Unknown parameter group: {parts[0]}')
    for id, version in versions.items(): docs[id]['schema_version'] = version
    chars = unique(tables['Characters'], 'id', 'Characters')
    for row in chars.values(): row['starting_stats'] = {}
    for row in tables['CharacterStats']: chars[row['character_id']]['starting_stats'][row['stat']] = row['value']
    docs['characters']['characters'] = list(chars.values())
    enemies = unique(tables['Enemies'], 'id', 'Enemies')
    phases = {}
    for row in tables['BossPhases']:
        owner, id = row.pop('enemy_id'), row.pop('phase_id')
        order = row.pop('order')
        phases[(owner,id)] = (order,dict(id=id,attacks=[],**row))
    actions = {}
    for row in tables['EnemyActions']:
        owner, phase = row.pop('enemy_id'), row.pop('phase_id')
        index, part = row.pop('attack_index'), row.pop('part_index')
        if 'spawn_enemy_id' in row: row['enemy_id'] = row.pop('spawn_enemy_id')
        key = (owner,phase,index,part)
        if key in actions: raise ValueError(f'Duplicate action: {key}')
        actions[key] = row
    grouped_offsets = {}
    for row in tables['AttackOffsets']:
        key = (row['enemy_id'],row['phase_id'],row['attack_index'],row['part_index'])
        grouped_offsets.setdefault(key, []).append((row['offset_index'],[row['x'],row['y']]))
    for key, points in grouped_offsets.items(): actions[key]['offsets'] = [point for _,point in sorted(points)]
    for key, action in sorted(actions.items()):
        owner, phase, index, part = key
        if part >= 0:
            parent = actions[(owner,phase,index,-1)]
            if parent['type'] != 'combo': raise ValueError('Sub-action requires a combo parent')
            parent.setdefault('attacks', []).append(action)
    for key, action in sorted(actions.items()):
        owner, phase, index, part = key
        if part >= 0: continue
        if phase == 'normal': enemies[owner]['attack'] = action
        elif phase == 'opening': enemies[owner].setdefault('attacks', []).append(action)
        else: phases[(owner,phase)][1]['attacks'].append(action)
    for (owner,id),(order,phase) in sorted(phases.items(), key=lambda entry:(entry[0][0],entry[1][0])):
        enemies[owner].setdefault('phases', []).append(phase)
    docs['enemies']['enemies'] = list(enemies.values())
    docs['upgrades']['upgrades'] = tables['Upgrades']
    docs['skills']['skills'] = tables['Skills']
    gear = unique(tables['Equipment'], 'id', 'Equipment')
    for row in gear.values(): row['stats'] = {}
    for row in tables['EquipmentStats']: gear[row['equipment_id']]['stats'][row['stat']] = row['value']
    docs['equipment'].update(equipment=list(gear.values()),slots={row['id']:row['name'] for row in tables['EquipmentSlots']},rarities=tables['Rarities'])
    terrain = sorted(tables['Terrain'],key=lambda row:row['rotation_order'])
    docs['arena_afflictions']['rotation'] = [row['id'] for row in terrain]
    docs['arena_afflictions']['afflictions'] = [{key:value for key,value in row.items() if key!='rotation_order'} for row in terrain]
    nodes = tables['NodeRoster']
    for row in nodes:
        row.setdefault('modifiers', [])
        row.setdefault('enemies', [])
    docs['encounters']['nodes'] = sorted(nodes,key=lambda row:row['position'])
    docs['encounters']['boss_rotation'] = [row['enemy_id'] for row in sorted(tables['BossRotation'],key=lambda row:row['order'])]
    modifiers = {}
    for row in tables['NodeStates']:
        id,name,targets = row.pop('id'),row.pop('name'),row.pop('targets')
        modifiers[id] = {'name':name,'targets':targets,'values':row}
    docs['encounters']['modifiers'] = modifiers
    return docs

def validate(docs: dict) -> None:
    b=docs['balance']
    enemy=unique(docs['enemies']['enemies'],'id','Enemies')
    chars=unique(docs['characters']['characters'],'id','Characters')
    skills=unique(docs['skills']['skills'],'id','Skills')
    unique(docs['upgrades']['upgrades'],'id','Upgrades')
    unique(docs['equipment']['equipment'],'id','Equipment')
    def number(value, label, minimum=0, integer=False):
        if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value) or value<minimum or (integer and value!=int(value)):
            raise ValueError(f'{label}: invalid numeric value {value}')
    for key in ['max_hp','move_speed','attack_damage','attack_interval_seconds']:
        number(b['player'][key],'player.'+key,minimum=0.001)
    for group,key in [('difficulty','node_duration_seconds'),('difficulty','boss_every_nodes'),('abilities','skill_cooldown_seconds'),('stat_rules','armor_scale'),('skill_progression','max_rank'),('skill_progression','choice_every_levels'),('equipment_rules','nodes_per_tier'),('meta','kills_per_crystal'),('combat','upgrade_offer_count')]: number(b[group][key],group+'.'+key,minimum=0.001)
    if b['difficulty']['spawn_distance_min']>=b['difficulty']['spawn_distance_max']: raise ValueError('Spawn distance minimum must be below maximum')
    for row in enemy.values():
        for key in ['hp','speed','radius']: number(row[key],row['id']+'.'+key,minimum=0.001)
        for key in ['damage','defense']: number(row[key],row['id']+'.'+key)
        for key in ['crit_resistance','slow_resistance']:
            number(row[key],row['id']+'.'+key)
            if row[key]>1: raise ValueError('Resistance probabilities must be in [0,1]')
        number(row['xp'],row['id']+'.xp',integer=True)
        if row['kind'] not in ['normal','elite','boss']: raise ValueError('Unknown enemy kind')
        if row['kind']=='normal': number(row['weight'],row['id']+'.weight',minimum=0.001)
        def check_action(action, parent=True):
            if parent:
                number(action['warning'],'warning',minimum=0.001)
                number(action['interval'],'interval',minimum=0.001)
            if action['type']=='combo':
                if not action.get('attacks'): raise ValueError('Combo requires sub-actions')
                for part in action['attacks']: check_action(part,False)
            elif action['type']=='summon':
                if action['enemy_id'] not in enemy: raise ValueError('Unknown summon enemy')
                number(action['count'],'summon count',minimum=1,integer=True)
            elif action['type'] not in ['slam','shockwave','charge','leap','hazard','bolt','fan','radial_burst']: raise ValueError('Unknown enemy action type')
            required={'slam':['radius','damage'],'shockwave':['inner_radius','radius','damage'],'charge':['speed','duration'],'leap':['radius','damage'],'hazard':['radius','duration','tick','damage'],'bolt':['speed'],'fan':['speed','count','spread'],'radial_burst':['speed','count']}
            for key in required.get(action['type'],[]): number(action[key],row['id']+'.'+action['type']+'.'+key,minimum=0 if key in ['damage','spread','inner_radius'] else 0.001,integer=key=='count')
        for action in row.get('attacks',[]): check_action(action)
        if 'attack' in row: check_action(row['attack'])
        for phase in row.get('phases',[]):
            if not 0<phase['hp_below']<1: raise ValueError('Invalid boss phase threshold')
            for action in phase['attacks']: check_action(action)
    for row in chars.values():
        if row['skill'] not in skills or skills[row['skill']]['character']!=row['id']: raise ValueError('Character starting skill must belong to that character')
    for row in skills.values():
        if row['character'] not in chars: raise ValueError('Unknown skill character')
        if row['kind'] not in ['nova','shield','projectiles','hazard']: raise ValueError('Unknown skill behavior')
        number(row['cooldown'],row['id']+'.cooldown',minimum=0.001)
    base_stats={'damage','max_hp','armor','move_speed','crit_chance','pickup_radius','attack_rate'}
    for row in docs['equipment']['equipment']:
        if row['slot'] not in docs['equipment']['slots']: raise ValueError('Unknown equipment slot')
        if row.get('character') and row['character'] not in chars: raise ValueError('Unknown equipment character')
        if not set(row['stats']).issubset(base_stats): raise ValueError('Equipment may only provide supported flat base stats')
        for key,value in row['stats'].items():
            if key not in ['move_speed','crit_chance']: number(value,row['id']+'.'+key)
        number(row['icon'],row['id']+'.icon',integer=True)
        if row['icon']>=8: raise ValueError('Equipment icon must reference the existing eight-cell atlas')
    nodes=docs['encounters']['nodes']
    if [row['position'] for row in nodes]!=list(range(1,len(nodes)+1)) or len(nodes)!=b['difficulty']['boss_every_nodes']: raise ValueError('Node positions must cover one full boss cycle')
    for row in nodes:
        for id in row['enemies']:
            if id not in enemy or enemy[id]['kind']!='normal': raise ValueError('Node ordinary pool must reference normal enemies')
        if row['elite_id'] not in enemy or enemy[row['elite_id']]['kind']!='elite': raise ValueError('Node elite must reference an elite enemy')
        if not 0<=row['elite_chance']<=1: raise ValueError('Elite probability must be in [0,1]')
        for id in row['modifiers']:
            if id not in docs['encounters']['modifiers']: raise ValueError('Unknown node modifier')
    for id in docs['encounters']['boss_rotation']:
        if id not in enemy or enemy[id]['kind']!='boss': raise ValueError('Boss rotation must reference bosses')
    afflictions=unique(docs['arena_afflictions']['afflictions'],'id','Terrain')
    if set(docs['arena_afflictions']['rotation'])!=set(afflictions): raise ValueError('Terrain rotation must cover all types')
    schedule=docs['arena_afflictions']['schedule']
    if not 1<=schedule['minimum_zone_count']<=schedule['early_maximum_zone_count']<=schedule['maximum_zone_count']<=len(afflictions): raise ValueError('Terrain zone count must fit the unique type pool')
    if not 0<schedule['active_min_seconds']<=schedule['active_max_seconds'] or schedule['warning_seconds']<=0 or schedule['recovery_seconds']<=0: raise ValueError('Terrain phase durations must advance')
    if not 0<schedule['radius_min']<=schedule['radius_max'] or not 0<schedule['max_visible_coverage']<1: raise ValueError('Invalid terrain radius or coverage budget')
    for row in afflictions.values():
        number(row['atlas_index'],row['id']+'.atlas_index',integer=True)
        if row['atlas_index']>=8: raise ValueError('Terrain must reference the eight-cell scene atlas')

def serialized(document: dict) -> bytes:
    return (json.dumps(document,ensure_ascii=False,indent=2)+'\n').encode('utf-8')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workbook',type=Path,help='Optional legacy technical workbook')
    parser.add_argument('--config-dir',type=Path,default=ROOT/'design/数值策划')
    parser.add_argument('--output-dir',type=Path,default=ROOT/'data')
    parser.add_argument('--check',action='store_true',help='Verify exported data matches Excel without changing files')
    args=parser.parse_args()
    schema=json.loads((ROOT/'design/workbook-schema.json').read_text(encoding='utf-8'))
    docs=assemble(read_workbook(args.workbook) if args.workbook else read_planner_bundle(args.config_dir,schema),schema)
    validate(docs)
    workbooks={args.workbook.name:hashlib.sha256(args.workbook.read_bytes()).hexdigest()} if args.workbook else {path.name:hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(args.config_dir.glob('*.xlsx'))}
    manifest={'schema_version':1,'profile':'release-hard','workbooks':workbooks,'workbook_sha256':hashlib.sha256(serialized(workbooks)).hexdigest(),'documents':{}}
    failures=[]
    for id,document in docs.items():
        data=serialized(document)
        manifest['documents'][id]={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
        path=args.output_dir/(id+'.json')
        if args.check:
            if not path.is_file() or json.loads(path.read_text(encoding='utf-8'))!=document: failures.append(id)
        else:
            args.output_dir.mkdir(parents=True,exist_ok=True)
            path.write_bytes(data)
    if args.check:
        existing=args.output_dir/'config-manifest.json'
        if not existing.is_file() or json.loads(existing.read_text(encoding='utf-8'))!=manifest: failures.append('config-manifest')
        if failures: raise ValueError('Excel/export mismatch: '+', '.join(failures)+'. Run python tools/export_balance.py.')
    else: (args.output_dir/'config-manifest.json').write_bytes(serialized(manifest))
    print(f"PASS: {len(docs)} runtime documents validated; profile=release-hard; {'matches Excel' if args.check else 'exported from Excel'}")

if __name__=='__main__':
    try: main()
    except (ValueError,KeyError,FileNotFoundError,zipfile.BadZipFile) as error:
        raise SystemExit(f'CONFIG ERROR: {error}')

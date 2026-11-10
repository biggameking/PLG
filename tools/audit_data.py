# Data-integrity audit: cross-references every id used vs defined.
import json, re, io, sys

def grab(path, const):
    s = io.open(path, encoding='utf-8').read()
    i = s.find('const %s = ' % const)
    if i < 0: return None
    i = s.find('=', i) + 1
    # find matching close of first { or [
    while s[i] in ' \n': i += 1
    op, cl = ('{','}') if s[i]=='{' else ('[',']')
    d = 0; j = i
    while True:
        if s[j] == op: d += 1
        elif s[j] == cl:
            d -= 1
            if d == 0: break
        j += 1
    lit = s[i:j+1]
    lit = re.sub(r',(\s*[}\]])', r'\1', lit)  # trailing commas
    try:
        return json.loads(lit)
    except Exception as e:
        return {'__PARSE_ERROR__': str(e)}

D = 'src/data/'
items   = grab(D+'items.gd','ITEMS')
recipes = grab(D+'items.gd','RECIPES')
skills  = grab(D+'skills.gd','SKILLS')
sp_base = grab(D+'species.gd','SPECIES')
sp_gen  = grab(D+'species_gen.gd','SPECIES')
zones   = grab(D+'species_gen.gd','ZONE')
structs = grab(D+'structures.gd','STRUCTURES')
tech    = grab(D+'structures.gd','TECH')
work    = grab(D+"work.gd","WORK_GLYPH")
passv   = grab(D+'passives.gd','PASSIVES')

bad = []
def chk(c, msg):
    if not c: bad.append(msg)

for name, d in [('ITEMS',items),('RECIPES',recipes),('SKILLS',skills),('SPECIES',sp_base),
                ('SPECIES_gen',sp_gen),('ZONE',zones),('STRUCTURES',structs),('TECH',tech),
                ('WORK_TYPES',work),('PASSIVES',passv)]:
    chk(d is not None and '__PARSE_ERROR__' not in str(d), 'PARSE FAIL %s: %s' % (name, str(d)[:100] if d else 'missing'))
if bad:
    for b in bad: print('FATAL', b); sys.exit(1)

species = dict(sp_base); species.update(sp_gen)
worktypes = set(work.keys()) if isinstance(work, dict) else set(work)

# species refs
for sid, sp in species.items():
    for sk in sp.get('skills', []):
        chk(sk[1] in skills, '%s skill %s not in SKILLS' % (sid, sk[1]))
    for dr in sp.get('drops', []):
        chk(dr[0] in items, '%s drop %s not in ITEMS' % (sid, dr[0]))
    for wt in sp.get('work', {}):
        chk(wt in worktypes, '%s work %s not in WORK_TYPES' % (sid, wt))
    for el in sp.get('elements', []):
        chk(el in ('neutral','fire','water','grass','electric','ice','ground','dark','dragon'),
            '%s element %s invalid' % (sid, el))
    chk('capturePower' in sp, '%s missing capturePower' % sid)

# zone pools
for z, pool in zones.items():
    for sid in pool:
        chk(sid in species, 'ZONE %s references missing species %s' % (z, sid))

# recipes
for r in recipes:
    chk(r['out'][0] in items, 'recipe %s output %s not in ITEMS' % (r['id'], r['out'][0]))
    for c in r.get('cost', []):
        chk(c[0] in items, 'recipe %s cost %s not in ITEMS' % (r['id'], c[0]))
    # 'hand' = bare-handed crafting, needs no structure
    chk(r.get('station') in structs or r.get('station') in (None, 'hand'), 'recipe %s station %s not in STRUCTURES' % (r['id'], r.get('station')))

# structures
for sid, s in structs.items():
    for c in s.get('cost', []):
        chk(c[0] in items, 'structure %s cost %s not in ITEMS' % (sid, c[0]))
    for pr in s.get('job', {}).get('produces', []):
        chk(pr[0] in items, 'structure %s produces %s not in ITEMS' % (sid, pr[0]))
    wt = s.get('job', {}).get('workType')
    if wt: chk(wt in worktypes, 'structure %s workType %s invalid' % (sid, wt))

# tech
for t in tech:
    for u in t.get('unlocks', []):
        chk(u in structs, 'tech %s unlocks missing structure %s' % (t['id'], u))

# sprite coverage: every species needs an entry in gen_assets SPRITES
ga = io.open('tools/gen_assets.py', encoding='utf-8').read()
for sid in species:
    chk('"%s"' % sid in ga or "'%s'" % sid in ga, 'no sprite def for %s' % sid)
# every sphere usable item has spherePower — the launcher flings spheres,
# it isn't one, so it gets a pass by name
for iid, it in items.items():
    if ('sphere' in iid and iid != 'sphere_launcher') or it.get('spherePower'):
        chk('spherePower' in it, 'item %s sphere-like but no spherePower' % iid)

print('AUDIT DONE: %d species, %d items, %d recipes, %d structures, %d tech' %
      (len(species), len(items), len(recipes), len(structs), len(tech)))
if bad:
    print('--- %d VIOLATIONS ---' % len(bad))
    for b in bad: print(' *', b)
    sys.exit(2)
print('ALL CLEAN')

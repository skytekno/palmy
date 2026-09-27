#!/usr/bin/env python3
"""Dependency-free structural validation of this design package; not a live API test."""
from pathlib import Path
import csv,json,re,collections
from decimal import Decimal,ROUND_FLOOR

root=Path(__file__).resolve().parent
spec=json.loads((root/'openapi.json').read_text())
assert spec['openapi']=='3.0.3'
assert spec['info']['title']=='Palmy API'
refs=[]; operations=[]
def walk(x):
    if isinstance(x,dict):
        if '$ref' in x:
            target=spec
            for key in x['$ref'].removeprefix('#/').split('/'):
                target=target[key.replace('~1','/').replace('~0','~')]
            refs.append(x['$ref'])
        if x.get('type')=='object' and 'properties' in x:
            assert set(x.get('required',[]))<=set(x['properties']), x
        if x.get('type')=='string' and 'pattern' in x:
            re.compile(x['pattern'])
            if 'example' in x: assert re.fullmatch(x['pattern'],x['example'])
        for v in x.values(): walk(v)
    elif isinstance(x,list):
        for v in x: walk(v)
walk(spec)
for path,methods in spec['paths'].items():
    assert not any(x in path.lower() for x in ('berdua','conversation-card','family-journal'))
    for method,o in methods.items():
        operations.append(o['operationId'])
        ps=[spec['components']['parameters'][p['$ref'].split('/')[-1]] if '$ref'in p else p for p in o.get('parameters',[])]
        assert len({(p['in'],p['name']) for p in ps})==len(ps),(method,path,'duplicate parameter')
        assert set(re.findall(r'\{(.*?)\}',path))=={p['name'] for p in ps if p['in']=='path'}
        assert all(p['required'] for p in ps if p['in']=='path')
        assert any(c.startswith('2') for c in o['responses'])
        if method=='post': assert any(p['name']=='Idempotency-Key' for p in ps)
        if path.startswith('/households/'): assert spec.get('security') and o.get('security',spec['security'])
assert len(operations)==len(set(operations))

# Financial specification fixtures, independent of UI or SQL execution.
assert Decimal('1000')+Decimal('50')==Decimal('1050')
assert Decimal('2000')-Decimal('500')==Decimal('1500')
assert Decimal('1500')-Decimal('500')+Decimal('1500')==Decimal('2500')
assert Decimal('1000000')*Decimal('1.10')**2==Decimal('1210000')
def split(total,bps):
    units=Decimal(total)*100
    assert units==units.to_integral_value() and sum(bps)==10000
    exact=[units*Decimal(b)/10000 for b in bps]
    allocated=[int(x.to_integral_value(rounding=ROUND_FLOOR)) for x in exact]
    order=sorted(range(len(bps)),key=lambda i:(-(exact[i]-allocated[i]),i))
    for i in order[:int(units)-sum(allocated)]: allocated[i]+=1
    return [Decimal(x)/100 for x in allocated]
assert split('1234.56',[5000,5000])==[Decimal('617.28')]*2
assert sum(split('0.01',[3333,3333,3334]))==Decimal('0.01')
assert sum(split('1234.57',[5000,5000]))==Decimal('1234.57')
money_pattern=spec['components']['schemas']['Money']['pattern']
for val in ('0','1','1234.56','9999999999999999.99'): assert re.fullmatch(money_pattern,val)
for val in ('-1','1.001','NaN','Infinity','1e3','10000000000000000'): assert not re.fullmatch(money_pattern,val)

sql=(root/'schema.sql').read_text()
tables=set(re.findall(r'CREATE TABLE palmy\.(\w+)',sql))
targets=set(re.findall(r'REFERENCES palmy\.(\w+)',sql))
assert targets<=tables,targets-tables
assert sql.count('BEGIN;')==1 and sql.rstrip().endswith('COMMIT;')
assert sql.count('$$')%2==0
assert 'DEFERRABLE INITIALLY DEFERRED' in sql and 'WITH CHECK' in sql
assert 'posted_lines_immutable' in sql and 'payment_exceeds_remaining' in sql
assert 'negative_asset_position' in sql and 'insufficient_free_cash' in sql
erd=(root/'palmy-erd.mmd').read_text()
erd_tables=set(re.findall(r'^  (\w+) \{',erd,re.M))
assert erd_tables==tables,(tables-erd_tables,erd_tables-tables)
dictionary=(root/'database-dictionary.md').read_text()
assert set(re.findall(r'^## (\w+)$',dictionary,re.M))==tables

coverage=list(csv.DictReader((root/'coverage.csv').open()))
assert len({r['id'] for r in coverage})==len(coverage)
counts=collections.Counter(r['status'] for r in coverage)
assert counts['EXCLUDED']==3
for md in root.glob('*.md'):
    assert md.read_text().count('```')%2==0,md.name
    for target in re.findall(r'\]\(([^)]+)\)',md.read_text()):
        if target=='artifact-validation.json': continue  # written below only after all checks pass
        if not target.startswith(('https://','http://','#')):
            assert (md.parent/target.split('#')[0]).exists(),(md.name,target)
result={'openapi':'structural checks passed; not full metaschema validation','operations':len(operations),'schemas':len(spec['components']['schemas']),'resolved_references':len(refs),'database_tables':len(tables),'sql':'structural checks passed; PostgreSQL execution not performed','erd':'table inventory matches DDL; renderer not executed','financial_specification_fixtures':'passed','coverage_rows':len(coverage),'coverage_statuses':dict(counts),'markdown_links_and_fences':'passed'}
(root/'artifact-validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))

import json, math, re, pathlib
import argparse
import pandas as pd
import numpy as np

parser=argparse.ArgumentParser(description='Create MY DERBY estimated horse abilities from KRA result CSV')
parser.add_argument('source_csv',type=pathlib.Path,help='CSV exported from historical race results')
parser.add_argument('--output-dir',type=pathlib.Path,default=pathlib.Path('.'))
args=parser.parse_args()
SRC=args.source_csv
OUT=args.output_dir
OUT.mkdir(parents=True,exist_ok=True)
KEYS=['start','speed','acceleration','stamina','finishing','power','grit','stability','recovery']
NATIVE=['서울','부경','부산경남']
df=pd.read_csv(SRC, low_memory=False,dtype={'hrNo':str,'rcDate':str,'birthday':str})
df['hrNo']=df['hrNo'].str.strip().str.zfill(7)
df['hrName']=df['hrName'].fillna('').astype(str).str.rsplit(']',n=1).str[-1].str.strip()
df['hrName']=df['hrName'].str.replace(r'\s+',' ',regex=True)
df['meet']=df['meet'].replace({'부산경남':'부경'})
for c in ['rcDist','rcTime','age','ord','rating','wgBudam','seS1fAccTime','buS1fTime','seG3fAccTime','seG1fAccTime','bu_3fGTime','bu_1fGTime','sjS1fOrd','sjG3fOrd','sjG1fOrd','chulNo']:
 df[c]=pd.to_numeric(df[c],errors='coerce')
df['rcDate']=pd.to_numeric(df['rcDate'],errors='coerce').fillna(0).astype(int)
df['rcNo']=pd.to_numeric(df['rcNo'],errors='coerce').fillna(0).astype(int)
# One historical observation per race; prefer the row with a valid timing.
df=df.sort_values(['hrNo','rcDate','rcNo','rcTime']).drop_duplicates(['hrNo','rcDate','meet','rcNo'],keep='last')
df=df[(df.rcTime.between(50,170)) & df.rcDist.between(800,3300) & df.age.between(2,14) & df.ord.between(1,18)].copy()
df['year']=df.rcDate.astype(str).str[:4].astype(int)
df['S1F']=np.where(df.meet.eq('부경'),df.buS1fTime,df.seS1fAccTime)
df['G3F']=np.where(df.meet.eq('부경'),df.bu_3fGTime,df.rcTime-df.seG3fAccTime)
df['G1F']=np.where(df.meet.eq('부경'),df.bu_1fGTime,df.rcTime-df.seG1fAccTime)
for field,lo,hi in [('S1F',11,22),('G3F',31,54),('G1F',11,19)]:
 df.loc[~df[field].between(lo,hi),field]=np.nan
# Reference races: distance + meet + year, falling back to distance + meet.
for field in ['rcTime','S1F','G3F','G1F']:
 ref1=df.groupby(['meet','rcDist','year'])[field].transform('median')
 n1=df.groupby(['meet','rcDist','year'])[field].transform('count')
 ref2=df.groupby(['meet','rcDist'])[field].transform('median')
 ref3=df.groupby('rcDist')[field].transform('median')
 base=ref1.where(n1>=35,ref2).fillna(ref3)
 val=df[field]
 # Differences measured in seconds; rate adjusted by distance for absolute speed.
 denom={'rcTime':base*.035,'S1F':1.2,'G3F':4.8,'G1F':2.1}[field]
 normalized=(base-val)/denom
 df['z_'+field]=normalized.clip(-2.6,2.6)
# Grade enhancement: race strength at same timing (not comparable to an official handicap rating).
def grade_adjust(x):
 s=str(x)
 if 'OPEN' in s or '대상' in s or '특별' in s:return 12
 m=re.search(r'([1-6])\s*등급',s)
 return {1:12,2:9,3:6,4:3,5:0,6:-3}.get(int(m.group(1)),0) if m else 0

df['grade_boost']=df['rank'].map(grade_adjust)
df['finish_norm']=(1-(df.ord-1)/11).clip(0,1)
df['rating_norm']=pd.to_numeric(df['rating'],errors='coerce').fillna(0).clip(0,120)
df['race_quality']=(51+14*df.z_rcTime+df.grade_boost+9*(df.finish_norm-.5)).clip(12,98)
df['s1_quality']=(50+13*df.z_S1F+5*(df['sjS1fOrd'].fillna(6).rsub(6)/5)).clip(15,95)
df['g3_quality']=(50+12*df.z_G3F).clip(15,95)
df['g1_quality']=(50+12*df.z_G1F).clip(15,95)
df['closing_gain']=(df['sjS1fOrd']-df['ord']).clip(-8,8)
df['is_wet']=df['track'].fillna('').astype(str).str.extract(r'\((\d+)\s*%\)',expand=False).astype(float).ge(12)
records=[]
for hrno,g in df.groupby('hrNo',sort=True):
 g=g.sort_values(['rcDate','rcNo']).reset_index(drop=True)
 n=len(g); latest=g.iloc[-1]; recent=g.tail(min(5,n)); first=g.head(min(5,n))
 def avg(x,defv=50.0):
  a=pd.to_numeric(x,errors='coerce').dropna();return float(a.mean()) if len(a)>0 else defv
 def wavg(x,defv=50.0):
  a=pd.to_numeric(x,errors='coerce').to_numpy(dtype=float)
  m=np.isfinite(a)
  if not m.any():return defv
  w=np.linspace(.8,1.6,len(a))
  return float(np.average(a[m],weights=w[m]))
 quality_recent=wavg(recent.race_quality)
 quality_peak=avg(g.race_quality.nlargest(min(4,n)))
 quality_career=avg(g.race_quality)
 quality=.48*quality_recent+.32*quality_peak+.20*quality_career
 recent_start=wavg(recent.s1_quality)
 recent_g3=wavg(recent.g3_quality)
 recent_g1=wavg(recent.g1_quality)
 early_pos=avg(recent['sjS1fOrd'].dropna(),6)
 closing=avg(recent.closing_gain.fillna(0),0)
 max_dist=int(g.rcDist.max())
 long=g[g.rcDist>=1700]; short=g[g.rcDist<=1300]
 qlong=avg(long.race_quality,quality) if len(long)>=2 else quality-6
 qshort=avg(short.race_quality,quality) if len(short)>=2 else quality-6
 consistency=50+min(20,n*1.15)-min(24,float(g.race_quality.std() if n>=2 else 12)*.7)
 grit=50+8*closing/3 +10*(avg(recent.finish_norm)-.5)+6*(quality_recent-quality_career)/20
 start=0.52*recent_start + .18*(65-early_pos*2) + .30*quality
 speed=quality*.80+ .20*(50+12*avg(g.z_rcTime))
 acceleration=.55*recent_start+.30*recent_g3+.15*(50+closing*3)
 stamina=.48*quality +.25*qlong+.17*quality_peak+.10*(50+max(0,max_dist-1300)/25)
 finishing=.48*recent_g1+.28*recent_g3+.24*(50+closing*4)
 power=.55*quality+.20*(50+(avg(g.wgBudam)-54)*2)+.25*quality_peak
 stability=.70*consistency+.30*quality_recent
 # a weak proxy from return after short time intervals, otherwise shrink toward prior 52.
 days=pd.to_datetime(g.rcDate.astype(str),format='%Y%m%d',errors='coerce').diff().dt.days
 good_return=((days>=7)&(days<=35))
 if good_return.sum()>=3:
  delta=g.race_quality.diff();rec=52+min(10,max(-10,float(delta[good_return].mean())*.8))
 else:rec=52
 recovery=.72*rec+.28*(50+min(12,n/3))
 raw=dict(zip(KEYS,[start,speed,acceleration,stamina,finishing,power,grit,stability,recovery]))
 cur={k:int(np.clip(round(.88*v+ .12*quality),23,94)) for k,v in raw.items()}
 # Grower's ceiling: gap decreases with age. Data-derived trend is limited to +/- 4 points.
 age=int(latest.age)
 growth={2:20,3:14,4:9,5:5,6:3,7:2,8:1,9:0,10:0}.get(age,0)
 age_quality=g.groupby('age').race_quality.mean()
 if len(age_quality)>=2:
  momentum=float((age_quality.iloc[-1]-age_quality.iloc[0])/3)
 else:momentum=0
 growth_adjust=float(np.clip(momentum,-3,5))
 if n<4:growth_adjust+=2 # low confidence: range wider, not a high guarantee
 pot={k:int(np.clip(max(cur[k],cur[k]+growth+growth_adjust + (1 if k in ('start','speed','acceleration','finishing') and age<=3 else 0)),cur[k],98)) for k in KEYS}
 # For older horses, displayed maximum historical peak (not planned future physiological gains).
 if age>=7:pot={k:max(cur[k],min(98,cur[k]+2)) for k in KEYS}
 count_win=int((g.ord==1).sum());count_top3=int((g.ord<=3).sum())
 confidence=round(min(.95,.20+.17*math.log1p(n)+(.08 if n>=10 else 0)),3)
 evidence_tags=[]
 def add(code,score,evidence):evidence_tags.append({'code':code,'score':int(score),'evidence':evidence})
 if recent_start>=65 and early_pos<=4.5:add('FAST_START',min(95,round(recent_start+7)),'초반 200m 및 초기 위치')
 if recent_g1>=64 and closing>=.6:add('LATE_KICK',min(95,round(recent_g1+7)),'마지막 200m 및 순위 상승')
 if len(long)>=3 and qlong>=quality+3:add('STAYER',round(min(95,qlong+5)),'1700m 이상 실적 우위')
 if len(short)>=3 and qshort>=quality+3:add('SPRINTER',round(min(95,qshort+5)),'1300m 이하 실적 우위')
 if n>=8 and count_top3/n>=.42 and consistency>=50:add('CONSISTENT',round(min(95,consistency+7)),'최근 포함 통산 입상률 및 편차')
 if n>=8 and float(g.race_quality.std())>15:add('VARIABLE_FORM',75,'경주별 능력 발휘 편차')
 if age_quality.size>=2 and float(age_quality.iloc[-1]-age_quality.iloc[0])>7:add('LATE_DEVELOPMENT',75,'연령별 기록 상승')
 if count_win>=3 and (g.grade_boost>=9).sum()>=2:add('BIG_RACE_EXPERIENCE',75,'상위등급 우승 경험')
 if recent.closing_gain.mean()>=1.5 and n>=4:add('TRAFFIC_RECOVERY',73,'중간~결승 순위 만회')
 if len(evidence_tags)==0:add('UNDETERMINED',50,'측정가능한 특성 증거 부족')
 evidence_tags=evidence_tags[:4]
 # distance fit: actual history when >=2 at distance, otherwise category-level shrinkage
 affinity={}
 for target in [1000,1200,1300,1400,1600,1700,1800,2000,2300]:
  gd=g[g.rcDist==target]
  nearby=g[(g.rcDist-target).abs()<=200]
  own=avg(gd.race_quality,quality) if len(gd)>0 else None
  neighbors=avg(nearby.race_quality,quality) if len(nearby)>0 else quality
  if len(gd)>=2: score=.7*own+.3*quality
  elif len(gd)==1:score=.4*own+.6*quality
  else:score=.23*neighbors+.77*quality-abs(target-int(g.rcDist.median()))/270
  affinity[str(target)]=int(np.clip(round(score+20),35,100))
 last_sex=str(latest.sex)
 sex={'수':'MALE','암':'FEMALE','거':'GELDING'}.get(last_sex,'MALE')
 rec={
  'hrNo':hrno,'hrName':str(latest.hrName),'sex':sex,'age':age,'birthday':str(latest.birthday).split('.')[0],
  'meet':str(latest.meet),'firstRaceDate':int(g.rcDate.min()),'lastRaceDate':int(latest.rcDate),
  'runs':n,'wins':count_win,'top3':count_top3,'lastRank':str(latest['rank']),
  'current':cur,'potential':pot,'distanceAffinity':affinity,
  'hiddenTraits':{'model':'observed_form_v1','inferred':True,'confidence':confidence,'tags':evidence_tags},
  'metadata':{'source':'KRA_result_export_csv','model_version':'kra_v1','performance_recent':round(quality_recent,1),'performance_peak':round(quality_peak,1),'performance_total':round(quality_career,1),'observed_races':n,'last_observed_age':age,'evidence_confidence':confidence,'potential_is_estimate':True},
 }
 records.append(rec)
assert len(records)==df.hrNo.nunique()
assert len({r['hrNo'] for r in records})==len(records)
assert all(']' not in r['hrName'] and r['hrName'] for r in records)
assert all(all(r['potential'][k]>=r['current'][k] for k in KEYS) for r in records)
# The user-facing CSV is a convenient review of assigned ratings and their provenance.
tab=[]
for r in records:
 row={k:r[k] for k in ['hrNo','hrName','sex','age','meet','firstRaceDate','lastRaceDate','runs','wins','top3']}
 row.update({'현재_'+k:r['current'][k] for k in KEYS})
 row.update({'최대성장_'+k:r['potential'][k] for k in KEYS})
 row['히든특성']=' / '.join(x['code'] for x in r['hiddenTraits']['tags'])
 row['추정신뢰도']=r['hiddenTraits']['confidence']
 tab.append(row)
out=pd.DataFrame(tab)
out.to_csv(OUT/'my_derby_horse_abilities.csv',index=False,encoding='utf-8-sig')
with open(OUT/'my_derby_horse_abilities.jsonl','w',encoding='utf8') as f:
 for r in records:f.write(json.dumps(r,ensure_ascii=False,separators=(',',':'))+'\n')
report={'rows':len(df),'horses':len(records),'name_bracket_removed':int(pd.read_csv(SRC,usecols=['hrName']).hrName.astype(str).str.contains(']',regex=False).sum()),
'current_means':{k:round(np.mean([r['current'][k] for r in records]),1) for k in KEYS},
'potential_means':{k:round(np.mean([r['potential'][k] for r in records]),1) for k in KEYS},
'model':'kra_v1','minDate':int(df.rcDate.min()),'maxDate':int(df.rcDate.max()),
'sexes':{str(k):int(v) for k,v in out.sex.value_counts().items()},'runs_summary':{str(k):float(v) for k,v in out.runs.describe().items()},
'oldest':int(out.age.max()),'maxAgeDistribution':{str(k):int(v) for k,v in out.age.value_counts().sort_index().items()}}
(OUT/'my_derby_horse_abilities_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2))
print(out.head(7).to_string(index=False))
print('outputs',[(p.name,p.stat().st_size) for p in OUT.glob('my_derby_*') if p.is_file() and p.name.startswith('my_derby_horse_abilities')])
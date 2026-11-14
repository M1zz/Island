import sys, statistics, collections
from island import *

def report(b=None, n=1000, veteran=False, quiet=False):
    rows = {}
    for name, bot in BOTS.items():
        res = collections.Counter(); days = []; lv = collections.defaultdict(list); deathday=[]
        for seed in range(1, n+1):
            j = {"knownRegions": set(REGIONS)} if veteran else None
            e = simulate(seed, bot, b, j)
            o = e.s.outcome
            if o[0] == "rescued": res["rescued"] += 1; days.append(o[1])
            elif o[0] == "died": res["died:"+o[2]] += 1; deathday.append(o[1])
            else: res["storm"] += 1
            for sk in SKILLS: lv[sk].append(e.level(sk))
        rows[name] = (res, days, lv, deathday)
        if not quiet:
            d = f"avg {statistics.mean(days):.1f} / med {statistics.median(days)}" if days else "-"
            print(f"{name:8} rescued {res['rescued']/n:6.1%}  storm {res['storm']/n:6.1%}  "
                  f"died {sum(v for k,v in res.items() if k.startswith('died'))/n:6.1%} "
                  f"{dict((k,v) for k,v in res.items() if k.startswith('died'))}  rescueDay {d}  "
                  f"lv " + " ".join(f"{s[:3]}={statistics.mean(lv[s]):.1f}" for s in SKILLS))
    return rows

if __name__ == "__main__":
    print("== fresh =="); report()
    print("== veteran (journal knows all regions) =="); report(veteran=True)

import collections, statistics
from island import *
def diag(b=None, n=400, bot=planner_bot, veteran=False):
    miss=collections.Counter(); first=collections.defaultdict(list)
    for seed in range(1,n+1):
        e=Engine(seed,b,{"knownRegions":set(REGIONS)} if veteran else None); brng=RNG(seed^0xA5A5A5A5A5A5A5A5)
        seen=set()
        while e.s.outcome is None:
            e.perform(bot(e,brng))
            s=e.s
            for st in s.structures:
                if st not in seen: seen.add(st); first[st].append(s.day)
            if "summit" in s.discovered and "summit" not in seen: seen.add("summit"); first["summit"].append(s.day)
            for sk in ["crafting","survival","exploration"]:
                for L in (1,2,3):
                    key=f"{sk}{L}"
                    if e.level(sk)>=L and key not in seen: seen.add(key); first[key].append(s.day)
        s=e.s
        if s.outcome[0]!="rescued":
            if "summit" not in s.discovered: miss["summit"]+=1
            if "signalFrame" not in s.structures: miss["frame"]+=1
            if s.count("dryWood")<30: miss["drywood"]+=1
            if e.level("survival")<2: miss["surv2"]+=1
    print("missing at end:",dict(miss))
    for k,v in sorted(first.items(), key=lambda kv: statistics.mean(kv[1])):
        print(f"  {k:12} reached {len(v)/n:5.0%}  avg day {statistics.mean(v):.1f}")
if __name__=="__main__": diag()

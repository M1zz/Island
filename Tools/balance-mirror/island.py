"""Line-by-line Python mirror of IslandCore (Swift) for balancing in an environment without Swift.
Keep RNG call order identical to GameEngine.swift."""
import math
from dataclasses import dataclass, field

M64 = (1 << 64) - 1


class RNG:
    def __init__(self, seed):
        self.state = seed & M64

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & M64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
        return z ^ (z >> 31)

    def unit(self):
        return (self.next() >> 11) * (2.0 ** -53)

    def chance(self, p):
        return self.unit() < p

    def index(self, n):
        return min(int(self.unit() * n), n - 1)


def clamp(v, lo, hi):
    return min(max(v, lo), hi)


@dataclass
class Balance:
    hoursPerDay: int = 12
    stormDay: int = 21
    thirstDecayPerDay: float = 30.0
    hungerDecayPerDay: float = 15.0
    drinkRestore: float = 35.0
    mealRestore: float = 25.0
    cookedMealRestore: float = 35.0
    drinkThreshold: float = 65.0
    eatThreshold: float = 75.0
    dehydrationDamage: float = 25.0
    starvationDamage: float = 10.0
    dailyRegen: float = 5.0
    fatiguePerHour: float = 4.0
    exploreFatiguePerHour: float = 7.0
    sleepRecovery: float = 45.0
    shelterSleepRecovery: float = 65.0
    rainSleepPenalty: float = 20.0
    dawnHour: int = 6
    middayStart: int = 10
    middayEnd: int = 15
    rainChillPerHour: float = 1.0
    sunWarmthPerHour: float = 2.0
    fireWarmth: float = 15.0
    nightChill: float = 10.0
    fireNightWarmth: float = 7.5
    shelterNightWarmth: float = 5.0
    rainNightChill: float = 5.0
    shiverThreshold: float = 20.0
    shiverFatigue: float = 10.0
    hypothermiaDamage: float = 20.0
    sunHeatWorking: float = 10.0
    sunHeatResting: float = 6.0
    shadeCoolPerHour: float = 6.0
    waterCool: float = 10.0
    sweatThreshold: float = 70.0
    heatThirstPerHour: float = 1.5
    heatstrokeDamage: float = 20.0
    heatstrokeFatigue: float = 20.0
    awakeFatiguePerHour: float = 1.0
    restRecoveryPerHour: float = 4.0
    fatiguePerLostHour: float = 20.0
    rainChance: float = 0.25
    rawWaterSicknessChance: float = 0.12
    palmFallChance: float = 0.08
    sicknessDamage: float = 15.0
    sicknessFatigue: float = 20.0
    injuryDamage: float = 15.0
    foodSpoilThreshold: int = 6
    xpScale: float = 30.0
    xpExponent: float = 1.5
    maxLevel: int = 10
    noveltyMultiplier: float = 2.0
    failMultiplier: float = 1.5
    repeatPenaltyBase: float = 0.7
    difficultyStep: float = 0.25
    yieldPerLevel: float = 0.2
    signalDryWood: int = 30
    signalMinSurvival: int = 2
    signalFailureWoodLoss: int = 10
    journalExploreBonus: float = 0.25


SKILLS = ["foraging", "crafting", "exploration", "survival"]
REGIONS = ["beach", "palmGrove", "stream", "jungle", "ridge", "summit"]
REQ = dict(beach=0, palmGrove=0, stream=0, jungle=0, ridge=1, summit=2)
DIFF = dict(beach=0, palmGrove=0, stream=1, jungle=1, ridge=2, summit=3)
TRAVEL = dict(beach=0, palmGrove=0, stream=1, jungle=1, ridge=2, summit=3)
NEIGH = dict(beach=["palmGrove", "stream"], palmGrove=["jungle"], stream=["jungle"],
             jungle=["ridge"], ridge=["summit"], summit=[])
YIELD = dict(beach=dict(food=1.5, wood=1.5, fiber=0, stone=0, cleanWater=0.6),
             palmGrove=dict(food=2.5, wood=2, fiber=3, stone=0, cleanWater=1),
             stream=dict(food=1.5, wood=1, fiber=1, stone=1),
             jungle=dict(food=2.5, wood=4, fiber=2, stone=0),
             ridge=dict(food=0, wood=1, fiber=0, stone=3),
             summit=dict(food=0, wood=0, fiber=0, stone=0))
# recipe: (reqLevel, cost, hours, xp, output, reqStructure, reqRegion)
RECIPES = {
    "dryingRack": (0, [("wood", 6), ("fiber", 4)], 2, 30, ("structure", "dryingRack"), None, None),
    "shelter": (1, [("wood", 12), ("fiber", 8)], 4, 40, ("structure", "shelter"), None, None),
    "clayPot": (1, [("fiber", 2)], 3, 30, ("structure", "clayPot"), None, "stream"),
    "signalFrame": (3, [("wood", 15), ("fiber", 10), ("stone", 4)], 4, 60, ("structure", "signalFrame"), None, "ridge"),
    "dryWood": (0, [("wood", 3)], 1, 10, ("items", "dryWood", 3), "dryingRack", None),
    "stoneAxe": (0, [("wood", 2), ("fiber", 2), ("stone", 1)], 2, 12, ("structure", "stoneAxe"), None, None),
    "rope": (1, [("fiber", 6)], 2, 12, ("structure", "rope"), None, None),
    "torch": (1, [("dryWood", 2), ("fiber", 2)], 2, 12, ("structure", "torch"), None, None),
    "map": (0, [("wood", 2)], 1, 15, ("structure", "map"), None, None),
}
RECIPE_ORDER = ["dryingRack", "shelter", "clayPot", "signalFrame", "dryWood", "stoneAxe", "rope", "torch", "map"]
# The tool you must carry to get into a region at all.
TOOL = dict(jungle="stoneAxe", ridge="rope", summit="torch")

ALL_ACTIONS = []
for r in REGIONS:
    for it in ["cleanWater", "food", "wood", "fiber", "stone"]:
        if YIELD[r].get(it, 0) > 0:
            ALL_ACTIONS.append(("gather", it, r))
ALL_ACTIONS += [("fish",), ("fetchWater",)]
ALL_ACTIONS += [("explore", r) for r in REGIONS if r != "beach"]
ALL_ACTIONS += [("craft", rc) for rc in RECIPE_ORDER]
ALL_ACTIONS += [("makeFire",), ("lightSignal",), ("sleep",)]


def xp_to_next(level, b):
    return b.xpScale * math.pow(level + 1, b.xpExponent)


class State:
    def __init__(self, b):
        self.day = 1
        self.hoursLeft = b.hoursPerDay
        self.weather = "clear"
        self.thirst, self.hunger, self.fatigue, self.health = 100.0, 100.0, 0.0, 100.0
        self.temperature = 50.0
        self.inv = dict(cleanWater=3, food=3)
        self.xp = {}
        self.discovered = {"beach"}
        self.structures = set()
        self.fireLitToday = False
        self.hoursSpentToday = 0
        self.actionsToday = {}
        self.firstTimes = set()
        self.outcome = None

    def count(self, it):
        return self.inv.get(it, 0)

    def add(self, it, n):
        self.inv[it] = self.inv.get(it, 0) + n


class Engine:
    def __init__(self, seed, b=None, journal=None):
        self.b = b or Balance()
        self.journal = journal or {"knownRegions": {"beach"}}
        self.rng = RNG(seed)
        self.s = State(self.b)
        self.start_day()

    def level(self, sk):
        rem = self.s.xp.get(sk, 0.0)
        lv = 0
        while lv < self.b.maxLevel:
            need = xp_to_next(lv, self.b)
            if rem < need:
                break
            rem -= need
            lv += 1
        return lv

    def hours(self, a):
        k = a[0]
        if k == "gather": return 2 + TRAVEL[a[2]]
        if k == "rest": return 1
        if k == "fish": return 3
        if k == "fetchWater": return 1 + TRAVEL["stream"]
        if k == "explore": return 3 + TRAVEL[a[1]]
        if k == "craft":
            rr = RECIPES[a[1]][6]
            return RECIPES[a[1]][2] + (TRAVEL[rr] if rr else 0)
        if k == "makeFire": return 1
        if k == "lightSignal": return 2 + TRAVEL["summit"]
        return 0

    def can(self, a):
        s, b = self.s, self.b
        if s.outcome is not None: return False
        k = a[0]
        if k == "sleep": return True
        if self.hours(a) > s.hoursLeft: return False
        if k == "rest": return True
        if k == "gather": return a[2] in s.discovered and YIELD[a[2]][a[1]] > 0
        if k == "fish": return True
        if k == "fetchWater": return "stream" in s.discovered
        if k == "explore":
            r = a[1]
            return (r not in s.discovered and any(r in NEIGH[d] for d in s.discovered)
                    and self.level("exploration") >= REQ[r]
                    and (r not in TOOL or TOOL[r] in s.structures))
        if k == "craft":
            req, cost, _, _, out, rs, rr = RECIPES[a[1]]
            if out[0] == "structure" and out[1] in s.structures: return False
            if rs and rs not in s.structures: return False
            if rr and rr not in s.discovered: return False
            if self.level("crafting") < req: return False
            return all(s.count(i) >= n for i, n in cost)
        if k == "makeFire":
            return not s.fireLitToday and (s.count("dryWood") > 0 or s.count("wood") > 0)
        if k == "lightSignal":
            return ("summit" in s.discovered and "signalFrame" in s.structures
                    and s.count("dryWood") >= b.signalDryWood
                    and self.level("survival") >= b.signalMinSurvival)
        return False

    def available(self):
        return [a for a in ALL_ACTIONS if self.can(a)]

    def roll_yield(self, base, sk):
        mult = 1 + self.b.yieldPerLevel * self.level(sk)
        var = 0.7 + 0.6 * self.rng.unit()
        return int(math.floor(base * mult * var + 0.5))

    def gain(self, base, sk, diff, failed, key):
        b, s = self.b, self.s
        before = self.level(sk)
        novelty = 1.0
        if key not in s.firstTimes:
            s.firstTimes.add(key)
            novelty = b.noveltyMultiplier
        dm = clamp(1 + b.difficultyStep * (diff - before), 0.5, 2.0)
        fm = b.failMultiplier if failed else 1.0
        reps = s.actionsToday.get(key, 0)
        rm = math.pow(b.repeatPenaltyBase, reps)
        s.actionsToday[key] = reps + 1
        s.xp[sk] = s.xp.get(sk, 0.0) + base * novelty * dm * fm * rm

    def perform(self, a):
        if not self.can(a): return False
        s, b, k = self.s, self.b, a[0]
        if k == "sleep":
            self.end_day()
            return True
        if k == "rest":
            s.hoursLeft -= 1
            s.fatigue = min(100, s.fatigue + b.awakeFatiguePerHour)
            struck = self.pass_hours(1, not a[1], False)
            if s.health <= 0: s.outcome = ("died", s.day, "heatstroke" if struck else "injuries")
            return True
        cost = self.hours(a)
        s.hoursLeft -= cost
        fph = b.exploreFatiguePerHour if k == "explore" else b.fatiguePerHour
        s.fatigue = min(100, s.fatigue + fph * cost)
        ok = True
        if k == "gather":
            it, r = a[1], a[2]
            n = self.roll_yield(YIELD[r][it], "foraging")
            s.add(it, n)
            ok = n > 0
            if it == "cleanWater" and self.rng.chance(b.palmFallChance * max(0.25, 1 - 0.15 * self.level("foraging"))):
                s.health -= b.injuryDamage
            self.gain(10, "foraging", DIFF[r], not ok, f"gather.{it}.{r}")
        elif k == "fish":
            lv = self.level("foraging")
            ok = self.rng.chance(clamp(0.35 + 0.08 * lv, 0.05, 0.95))
            if ok: s.add("food", 3 + lv // 2)
            self.gain(12, "foraging", 1, not ok, "fish")
        elif k == "fetchWater":
            s.add("water", 3 + self.level("survival") // 3)
            self.gain(4, "survival", 0, False, "fetchWater")
        elif k == "explore":
            r = a[1]
            lv = self.level("exploration")
            bonus = b.journalExploreBonus if r in self.journal["knownRegions"] else 0
            ok = self.rng.chance(clamp(0.4 + 0.15 * (lv - DIFF[r]) + bonus, 0.05, 0.95))
            rain = 0.05 if s.weather == "rain" else 0
            if self.rng.chance(clamp(0.12 + 0.06 * (DIFF[r] - lv) + rain, 0.02, 0.5)):
                s.health -= b.injuryDamage
            if ok: s.discovered.add(r)
            self.gain(25, "exploration", DIFF[r], not ok, f"explore.{r}")
        elif k == "craft":
            req, cost_, _, xp, out, _, _ = RECIPES[a[1]]
            lv = self.level("crafting")
            ok = self.rng.chance(clamp(0.65 + 0.12 * (lv - req), 0.1, 0.98))
            if ok:
                for i, n in cost_: s.add(i, -n)
                if out[0] == "structure": s.structures.add(out[1])
                else: s.add(out[1], out[2])
            self.gain(xp, "crafting", req, not ok, f"craft.{a[1]}")
        elif k == "makeFire":
            lv = self.level("survival")
            dry = s.count("dryWood") > 0
            s.add("dryWood" if dry else "wood", -1)
            p = 0.3 + 0.12 * lv - (0 if dry else 0.25)
            raining = s.weather == "rain"
            if raining: p -= 0.1 if "shelter" in s.structures else 0.25
            ok = self.rng.chance(clamp(p, 0.05, 0.95))
            s.fireLitToday = ok
            if ok and s.temperature < 50: s.temperature = min(50, s.temperature + b.fireWarmth)
            self.gain(15, "survival", 1 + (1 if raining else 0), not ok, "makeFire")
            self.boil()
        elif k == "lightSignal":
            lv = self.level("survival")
            rp = 0.3 if s.weather == "rain" else 0
            ok = self.rng.chance(clamp(0.55 + 0.15 * (lv - b.signalMinSurvival) - rp, 0.05, 0.95))
            if ok: s.outcome = ("rescued", s.day)
            else: s.add("dryWood", -b.signalFailureWoodLoss)
            self.gain(40, "survival", 3, not ok, "lightSignal")
        if k == "fetchWater" and s.temperature > 50: s.temperature = max(50, s.temperature - b.waterCool)
        struck = self.pass_hours(cost, self.open_sky(a), True)
        if s.outcome is None and s.health <= 0:
            s.outcome = ("died", s.day, "heatstroke" if struck else "injuries")
        return ok

    def open_sky(self, a):
        k = a[0]
        opened = lambda r: r in ("beach", "ridge", "summit")
        if k == "gather": return opened(a[2])
        if k == "explore": return opened(a[1])
        if k in ("fish", "lightSignal"): return True
        if k == "fetchWater": return False
        if k == "craft":
            region = RECIPES[a[1]][6]
            return opened(region) if region else "shelter" not in self.s.structures
        if k == "makeFire": return "shelter" not in self.s.structures
        return False

    def pass_hours(self, hours, open_, working):
        s, b = self.s, self.b
        s.hoursSpentToday += hours
        self.wear(hours)
        start = b.dawnHour + b.hoursPerDay - s.hoursLeft - hours
        for hour in range(start, start + hours):
            t = s.temperature
            if s.weather == "rain": t -= b.rainChillPerHour
            elif t < 50: t = min(50, t + b.sunWarmthPerHour)
            elif not open_: t = max(50, t - b.shadeCoolPerHour)
            elif b.middayStart <= hour < b.middayEnd: t += b.sunHeatWorking if working else b.sunHeatResting
            s.temperature = clamp(t, 0, 100)
            if t > b.sweatThreshold: s.thirst = max(0, s.thirst - b.heatThirstPerHour)
        struck = s.temperature >= 100
        if struck:
            s.health -= b.heatstrokeDamage
            s.fatigue = min(100, s.fatigue + b.heatstrokeFatigue)
            s.temperature = 80
        self.drink()
        return struck

    def wear(self, hours):
        s, b = self.s, self.b
        share = hours / b.hoursPerDay
        s.thirst = max(0, s.thirst - b.thirstDecayPerDay * share)
        s.hunger = max(0, s.hunger - b.hungerDecayPerDay * share)

    def boil(self):
        s = self.s
        if s.fireLitToday and "clayPot" in s.structures and s.count("water") > 0:
            s.add("cleanWater", s.count("water"))
            s.inv["water"] = 0

    def drink(self):
        s, b = self.s, self.b
        while s.thirst <= b.drinkThreshold and s.count("water") + s.count("cleanWater") > 0:
            clean = s.count("cleanWater") > 0
            s.add("cleanWater" if clean else "water", -1)
            s.thirst = min(100, s.thirst + b.drinkRestore)
            if not clean:
                ch = b.rawWaterSicknessChance * max(0, 1 - 0.08 * self.level("survival"))
                if self.rng.chance(ch):
                    s.health -= b.sicknessDamage
                    s.fatigue = min(100, s.fatigue + b.sicknessFatigue)

    def end_day(self):
        s, b = self.s, self.b
        shelter = "shelter" in s.structures
        f = s.fatigue - b.restRecoveryPerHour * s.hoursLeft
        f -= b.shelterSleepRecovery if shelter else b.sleepRecovery
        if s.weather == "rain" and not shelter: f += b.rainSleepPenalty
        for _ in range(max(0, b.hoursPerDay - s.hoursSpentToday)):
            t = s.temperature
            if s.weather == "rain":
                if not shelter: t -= b.rainChillPerHour
            elif t < 50: t = min(50, t + b.sunWarmthPerHour)
            else: t = max(50, t - b.shadeCoolPerHour)
            s.temperature = clamp(t, 0, 100)
        chill = b.nightChill
        if s.fireLitToday: chill -= b.fireNightWarmth
        if shelter: chill -= b.shelterNightWarmth
        if s.weather == "rain" and not shelter: chill += b.rainNightChill
        s.temperature = max(0, min(50, s.temperature) - max(0, chill))
        if s.temperature < b.shiverThreshold: f += b.shiverFatigue
        s.fatigue = clamp(f, 0, 100)
        self.wear(max(0, b.hoursPerDay - s.hoursSpentToday))
        self.boil()
        self.drink()
        meal = b.cookedMealRestore if s.fireLitToday else b.mealRestore
        while s.hunger <= b.eatThreshold and s.count("food") > 0:
            s.add("food", -1)
            s.hunger = min(100, s.hunger + meal)
        if s.count("food") > b.foodSpoilThreshold: s.add("food", -1)
        if s.thirst <= 0: s.health -= b.dehydrationDamage
        if s.hunger <= 0: s.health -= b.starvationDamage
        if s.temperature <= 0: s.health -= b.hypothermiaDamage
        if s.thirst > 50 and s.hunger > 50 and 25 < s.temperature < 75 and s.fatigue < 50:
            s.health = min(100, s.health + b.dailyRegen)
        if s.health <= 0:
            cause = "dehydration" if s.thirst <= 0 else ("starvation" if s.hunger <= 0 else ("exposure" if s.temperature <= 0 else "injuries"))
            s.outcome = ("died", s.day, cause)
            return
        s.day += 1
        if s.day >= b.stormDay:
            s.outcome = ("storm",)
            return
        self.start_day()

    def start_day(self):
        s, b = self.s, self.b
        s.weather = "rain" if self.rng.chance(b.rainChance) else "clear"
        if s.weather == "rain":
            s.thirst = min(100, s.thirst + self.b.drinkRestore)
            if "clayPot" in s.structures: s.add("cleanWater", 3)
        s.fireLitToday = False
        s.hoursSpentToday = 0
        s.actionsToday = {}
        lost = int(s.fatigue / b.fatiguePerLostHour)
        s.hoursLeft = max(2, b.hoursPerDay - lost)


# ---- Bots (mirror Bots.swift) ----

def first(e, plan):
    for a in plan:
        if e.can(a): return a
    return ("sleep",)


def random_bot(e, rng):
    acts = e.available()
    return acts[rng.index(len(acts))]


def forager_bot(e, rng):
    s = e.s
    plan = []
    water = s.count("water") + s.count("cleanWater")
    if water < 4: plan.append(("fetchWater",))
    plan += [("explore", "stream"), ("explore", "palmGrove")]
    if water < 2: plan += [("gather", "cleanWater", "palmGrove"), ("gather", "cleanWater", "beach")]
    if s.count("food") < 6:
        plan += [("gather", "food", "palmGrove"), ("fish",), ("gather", "food", "beach")]
    plan.append(("sleep",))
    return first(e, plan)


GATHER_SPOTS = {
    "wood": ["jungle", "palmGrove", "beach"],
    "fiber": ["palmGrove", "jungle", "stream"],
    "stone": ["ridge", "stream"],
    "food": ["palmGrove", "jungle", "beach"],
}
BUILD_ORDER = ["stoneAxe", "dryingRack", "rope", "clayPot", "torch", "shelter", "signalFrame"]


def planner_bot(e, rng):
    s, b = e.s, e.b
    plan = [("lightSignal",)]
    if s.temperature > 75: plan += [("fetchWater",), ("rest", True)]
    water = s.count("water") + s.count("cleanWater")
    if water < 4: plan.append(("fetchWater",))
    if "stream" not in s.discovered: plan.append(("explore", "stream"))
    if water < 2: plan += [("gather", "cleanWater", "palmGrove"), ("gather", "cleanWater", "beach")]
    if s.count("food") < 4:
        plan += [("gather", "food", r) for r in GATHER_SPOTS["food"]] + [("fish",)]
    if "palmGrove" not in s.discovered: plan.append(("explore", "palmGrove"))
    if s.temperature < 25 and not s.fireLitToday and s.actionsToday.get("makeFire", 0) < 2:
        plan.append(("makeFire",))
    plan += [("craft", r) for r in BUILD_ORDER]
    plan += [("explore", "jungle"), ("explore", "ridge"), ("explore", "summit")]
    if not s.fireLitToday and s.actionsToday.get("makeFire", 0) < 2 and s.count("dryWood") > 0:
        plan.append(("makeFire",))
    nxt = next((r for r in BUILD_ORDER if r not in s.structures), None)
    if nxt:
        for item, n in RECIPES[nxt][1]:
            if s.count(item) < n:
                plan += [("gather", item, r) for r in GATHER_SPOTS.get(item, [])]
    if s.count("dryWood") < b.signalDryWood + 3:
        plan.append(("craft", "dryWood"))
        plan += [("gather", "wood", r) for r in GATHER_SPOTS["wood"]]
    if s.count("food") < 6:
        plan += [("gather", "food", r) for r in GATHER_SPOTS["food"]] + [("fish",)]
    plan.append(("sleep",))
    return first(e, plan)


BOTS = {"random": random_bot, "forager": forager_bot, "planner": planner_bot}


def simulate(seed, bot, b=None, journal=None):
    e = Engine(seed, b, journal)
    brng = RNG(seed ^ 0xA5A5A5A5A5A5A5A5)
    n = 0
    while e.s.outcome is None and n < 10000:
        e.perform(bot(e, brng))
        n += 1
    return e

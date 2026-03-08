#!/usr/bin/env python3
"""
Training monitor — checks islands every 5 minutes, tracks progress,
detects breakthroughs, and appends analysis to markdown log.

Usage:
    python3 scripts/monitor_training.py [--interval 300] [--dashboard http://localhost:8081]
"""

import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
TRACKER_PATH = PROJECT_ROOT / "output" / "training_tracker.json"
ANALYSIS_PATH = PROJECT_ROOT / "output" / "training_analysis.md"
DASHBOARD_URL = "http://localhost:8081"
CHECK_INTERVAL = 300  # 5 minutes


def fetch_island_stats():
    try:
        with urllib.request.urlopen(f"{DASHBOARD_URL}/api/island-stats", timeout=30) as r:
            return json.loads(r.read())
    except Exception as e:
        print(f"  Failed to fetch stats: {e}")
        return None


def fetch_island_networks():
    try:
        with urllib.request.urlopen(f"{DASHBOARD_URL}/api/island-networks", timeout=30) as r:
            return json.loads(r.read())
    except Exception:
        return None


def load_tracker():
    if TRACKER_PATH.exists():
        with open(TRACKER_PATH) as f:
            return json.load(f)
    return {"checks": [], "breakthroughs": []}


def save_tracker(tracker):
    TRACKER_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(TRACKER_PATH, "w") as f:
        json.dump(tracker, f, indent=2)


def build_check_entry(stats, networks):
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    entry = {"timestamp": now, "islands": {}}

    for k, v in sorted(stats.items()):
        if not v:
            continue
        last = v[-1]
        best = max(g["bestFitness"] for g in v)
        dmg = max(abs(g["hp"]["p2Delta"]) for g in v if g.get("hp"))
        ent = last.get("combo", {}).get("entropy", 0) if last.get("combo") else 0
        uniq = last.get("combo", {}).get("unique", 0) if last.get("combo") else 0
        p1d = last["hp"]["p1Delta"] if last.get("hp") else 0

        net_info = {}
        if networks and k in networks and networks[k]:
            net_last = networks[k][-1]
            net_info = {
                "geneCount": net_last.get("geneCount", 0),
                "hiddenNodes": len([n for n in net_last.get("nodes", []) if n["type"] == "hidden"]),
            }

        entry["islands"][k] = {
            "generation": last["generation"],
            "bestFitness": round(best, 1),
            "maxDamage": dmg,
            "species": last["species"],
            "entropy": round(ent, 2),
            "uniquePatterns": uniq,
            "p1Delta": p1d,
            **net_info,
        }

    return entry


def detect_breakthroughs(tracker, entry):
    new_breakthroughs = []
    if not tracker["checks"]:
        return new_breakthroughs

    prev = tracker["checks"][-1]
    for island, data in entry["islands"].items():
        prev_dmg = prev.get("islands", {}).get(island, {}).get("maxDamage", 0)
        prev_fit = prev.get("islands", {}).get(island, {}).get("bestFitness", 0)

        if data["maxDamage"] > prev_dmg and data["maxDamage"] > 20:
            new_breakthroughs.append({
                "timestamp": entry["timestamp"],
                "island": island,
                "generation": data["generation"],
                "previousDamage": prev_dmg,
                "newDamage": data["maxDamage"],
                "fitness": data["bestFitness"],
                "entropy": data["entropy"],
                "type": "damage",
            })
        elif data["bestFitness"] > prev_fit * 1.2 and data["bestFitness"] > 120:
            new_breakthroughs.append({
                "timestamp": entry["timestamp"],
                "island": island,
                "generation": data["generation"],
                "previousFitness": prev_fit,
                "newFitness": data["bestFitness"],
                "fitness": data["bestFitness"],
                "entropy": data["entropy"],
                "type": "fitness",
            })

    return new_breakthroughs


def write_analysis(entry, breakthroughs, check_num):
    ANALYSIS_PATH.parent.mkdir(parents=True, exist_ok=True)
    ts = entry["timestamp"]

    with open(ANALYSIS_PATH, "a") as f:
        f.write(f"\n---\n\n## Check {check_num} — {ts}\n\n")

        # Summary table
        f.write("| Island | Gen | Fitness | P2 Dmg | Species | Entropy | Unique | Genes | Hidden | P1 Delta |\n")
        f.write("|--------|-----|---------|--------|---------|---------|--------|-------|--------|----------|\n")
        for k, d in sorted(entry["islands"].items()):
            f.write(f"| {k} | {d['generation']} | {d['bestFitness']:.1f} | {d['maxDamage']} | "
                    f"{d['species']} | {d['entropy']:.2f} | {d['uniquePatterns']} | "
                    f"{d.get('geneCount', '?')} | {d.get('hiddenNodes', '?')} | {d['p1Delta']:+d} |\n")

        # Breakthroughs
        if breakthroughs:
            f.write("\n### Breakthroughs Detected\n\n")
            for b in breakthroughs:
                if b["type"] == "damage":
                    f.write(f"- **{b['island']}** Gen {b['generation']}: "
                            f"P2 damage {b['previousDamage']}→{b['newDamage']} "
                            f"(fitness={b['fitness']:.1f}, entropy={b['entropy']:.2f})\n")
                else:
                    f.write(f"- **{b['island']}** Gen {b['generation']}: "
                            f"fitness {b['previousFitness']:.1f}→{b['newFitness']:.1f} "
                            f"(entropy={b['entropy']:.2f})\n")

        # Per-island commentary
        f.write("\n### Analysis\n\n")
        leader = max(entry["islands"].items(), key=lambda x: x[1]["bestFitness"])
        for k, d in sorted(entry["islands"].items()):
            is_leader = k == leader[0]
            tag = " (LEADER)" if is_leader else ""

            if d["maxDamage"] > 20:
                status = "Breakthrough"
            elif d["entropy"] > 1.0:
                status = "Exploring"
            else:
                status = "Plateaued"

            f.write(f"**{k}**{tag} [{status}]: "
                    f"fitness={d['bestFitness']:.1f}, dealing {d['maxDamage']} damage, "
                    f"{d['species']} species, entropy={d['entropy']:.2f} ({d['uniquePatterns']} patterns)")

            if d.get("geneCount"):
                f.write(f", network={d['geneCount']} genes/{d.get('hiddenNodes', 0)} hidden")

            if d["p1Delta"] > 0:
                f.write(f", char-switching (+{d['p1Delta']} P1 HP)")
            elif d["p1Delta"] == 0 and d["maxDamage"] > 20:
                f.write(f", pure offense (no char-switch)")

            f.write("\n\n")


def run_check():
    print(f"[{datetime.now().strftime('%H:%M:%S')}] Checking training progress...")

    stats = fetch_island_stats()
    if not stats:
        print("  No data available.")
        return False

    networks = fetch_island_networks()
    tracker = load_tracker()
    entry = build_check_entry(stats, networks)
    breakthroughs = detect_breakthroughs(tracker, entry)

    tracker["breakthroughs"].extend(breakthroughs)
    tracker["checks"].append(entry)
    save_tracker(tracker)

    check_num = len(tracker["checks"])
    write_analysis(entry, breakthroughs, check_num)

    # Print summary
    for k, d in sorted(entry["islands"].items()):
        marker = " ***" if any(b["island"] == k for b in breakthroughs) else ""
        print(f"  {k}: Gen {d['generation']:3d} | fit={d['bestFitness']:7.1f} | "
              f"dmg={d['maxDamage']:3d} | sp={d['species']:2d} | ent={d['entropy']:.2f}{marker}")

    if breakthroughs:
        for b in breakthroughs:
            print(f"  *** BREAKTHROUGH: {b['island']} — {b['type']} jump at Gen {b['generation']}")

    # Check if training is still running
    import subprocess
    result = subprocess.run(
        ["kubectl", "--context", "kind-saiyan", "get", "pods",
         "--field-selector=status.phase=Running", "-o", "name"],
        capture_output=True, text=True, timeout=5
    )
    running = len([p for p in result.stdout.strip().split("\n") if "train-batch" in p]) if result.returncode == 0 else 0

    if running == 0:
        print("  No training pods running — training may be complete.")
        return False

    print(f"  ({running} pods running, next check in {CHECK_INTERVAL}s)")
    return True


def _update_config(interval, dashboard):
    global CHECK_INTERVAL, DASHBOARD_URL
    CHECK_INTERVAL = interval
    DASHBOARD_URL = dashboard


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--interval", type=int, default=CHECK_INTERVAL)
    parser.add_argument("--dashboard", type=str, default=DASHBOARD_URL)
    parser.add_argument("--once", action="store_true", help="Run once and exit")
    args = parser.parse_args()

    _update_config(args.interval, args.dashboard)

    print(f"Training monitor started (interval={CHECK_INTERVAL}s)")
    print(f"Tracker: {TRACKER_PATH}")
    print(f"Analysis: {ANALYSIS_PATH}")

    while True:
        still_running = run_check()
        if args.once or not still_running:
            break
        time.sleep(CHECK_INTERVAL)

    print("Monitor stopped.")


if __name__ == "__main__":
    main()

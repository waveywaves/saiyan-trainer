#!/bin/bash
# Periodic training monitor — checks every 5 minutes, logs breakthroughs
LOG_FILE="output/training_monitor.log"
mkdir -p output

check_training() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "=== CHECK: $timestamp ===" | tee -a "$LOG_FILE"

  curl -s http://localhost:8081/api/island-stats 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
prev_bests = {}
for k,v in sorted(d.items()):
  if not v: continue
  last=v[-1]
  best=max(g['bestFitness'] for g in v)
  dmg=max(abs(g['hp']['p2Delta']) for g in v if g.get('hp'))
  ent=last.get('combo',{}).get('entropy',0) if last.get('combo') else 0
  print(f'  {k}: Gen {last[\"generation\"]:3d} | fitness={best:7.1f} | P2_dmg={dmg:3d} | species={last[\"species\"]:2d} | entropy={ent:.2f}')

  # Detect breakthroughs (fitness jumps > 10%)
  prev_dmg = 0
  for i,g in enumerate(v):
    if not g.get('hp'): continue
    cur_dmg = abs(g['hp']['p2Delta'])
    if i > 0 and cur_dmg > prev_dmg * 1.3 and cur_dmg > 20:
      print(f'    *** BREAKTHROUGH Gen {g[\"generation\"]}: damage {prev_dmg}->{cur_dmg} fitness={g[\"bestFitness\"]:.1f}')
    prev_dmg = max(prev_dmg, cur_dmg)
" 2>/dev/null | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
}

echo "Training monitor started. Checking every 5 minutes." | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

while true; do
  check_training

  # Check if any pods are still running
  running=$(kubectl --context kind-saiyan get pods --field-selector=status.phase=Running -o name 2>/dev/null | grep train-batch | wc -l)
  if [ "$running" -eq 0 ]; then
    echo "=== TRAINING COMPLETE ===" | tee -a "$LOG_FILE"
    check_training
    break
  fi

  sleep 300  # 5 minutes
done

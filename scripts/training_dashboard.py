#!/usr/bin/env python3
"""
Saiyan Trainer - Live Training Dashboard

Serves a web dashboard that visualizes NEAT training progress in real-time.
Reads from output/training.log and output/checkpoints/.

Usage:
    python3 scripts/training_dashboard.py [--port 8080] [--log output/training.log]

Then open http://localhost:8080 in your browser.
"""

import http.server
import json
import os
import re
import sys
import subprocess
import threading
import argparse
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
LOG_FILE = PROJECT_ROOT / "output" / "training.log"
CHECKPOINT_DIR = PROJECT_ROOT / "output" / "checkpoints"

def parse_training_log(log_path):
    """Parse training.log into structured generation data."""
    generations = []
    if not log_path.exists():
        return generations

    gen_pattern = re.compile(
        r'Gen (\d+): best=([-\d.]+) \(all-time=([-\d.]+)\), species=(\d+), genomes=(\d+)'
    )
    hp_pattern = re.compile(
        r'HP: P1 (\d+)->(\d+) \(([+-]\d+)\), P2 (\d+)->(\d+) \(([+-]\d+)\), frames=(\d+)'
    )
    combo_pattern = re.compile(
        r'Combo: entropy=([\d.]+), unique=(\d+), mashing=(true|false)'
    )
    time_pattern = re.compile(r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})')

    current_gen = None
    for line in open(log_path, 'r'):
        gen_match = gen_pattern.search(line)
        if gen_match:
            time_match = time_pattern.match(line)
            current_gen = {
                'generation': int(gen_match.group(1)),
                'bestFitness': float(gen_match.group(2)),
                'allTimeBest': float(gen_match.group(3)),
                'species': int(gen_match.group(4)),
                'genomes': int(gen_match.group(5)),
                'timestamp': time_match.group(1) if time_match else '',
                'hp': None,
                'combo': None,
            }
            generations.append(current_gen)
            continue

        if current_gen:
            hp_match = hp_pattern.search(line)
            if hp_match:
                current_gen['hp'] = {
                    'p1Start': int(hp_match.group(1)),
                    'p1End': int(hp_match.group(2)),
                    'p1Delta': int(hp_match.group(3)),
                    'p2Start': int(hp_match.group(4)),
                    'p2End': int(hp_match.group(5)),
                    'p2Delta': int(hp_match.group(6)),
                    'frames': int(hp_match.group(7)),
                }

            combo_match = combo_pattern.search(line)
            if combo_match:
                current_gen['combo'] = {
                    'entropy': float(combo_match.group(1)),
                    'unique': int(combo_match.group(2)),
                    'mashing': combo_match.group(3) == 'true',
                }

    # Deduplicate (same gen can appear multiple times from restarts)
    seen = {}
    for g in generations:
        seen[g['generation']] = g
    return sorted(seen.values(), key=lambda g: g['generation'])


DASHBOARD_HTML = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Saiyan Trainer - Training Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: #0a0a1a;
    color: #e0e0e0;
    min-height: 100vh;
  }
  .header {
    background: linear-gradient(135deg, #1a1a3e 0%, #0d0d2b 100%);
    padding: 20px 30px;
    border-bottom: 2px solid #ff6b00;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .header h1 { font-size: 24px; color: #ff6b00; text-transform: uppercase; letter-spacing: 2px; }
  .header .status { font-size: 14px; color: #888; }
  .header .status .live { color: #00ff88; animation: pulse 2s infinite; }
  @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
  .stats-bar {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 15px; padding: 20px 30px; background: #0d0d25;
  }
  .stat-card { background: #1a1a3e; border-radius: 8px; padding: 15px; border-left: 3px solid #ff6b00; }
  .stat-card .label { font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 1px; }
  .stat-card .value { font-size: 28px; font-weight: bold; color: #fff; margin-top: 4px; }
  .stat-card .value.positive { color: #00ff88; }
  .stat-card .value.negative { color: #ff4444; }
  .charts { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; padding: 20px 30px; }
  .chart-container { background: #1a1a3e; border-radius: 8px; padding: 20px; }
  .chart-container h3 { font-size: 14px; color: #ff6b00; margin-bottom: 10px; text-transform: uppercase; letter-spacing: 1px; }
  .chart-container canvas { max-height: 250px; }
  .full-width { grid-column: 1 / -1; }
  .view-toggle {
    display: flex; gap: 10px; padding: 15px 30px; background: #0d0d25;
  }
  .view-toggle button {
    padding: 8px 20px; border: 1px solid #ff6b00; background: transparent;
    color: #ff6b00; border-radius: 4px; cursor: pointer; font-size: 13px;
    text-transform: uppercase; letter-spacing: 1px; transition: all 0.2s;
  }
  .view-toggle button.active { background: #ff6b00; color: #000; }
  .view-toggle button:hover { background: rgba(255,107,0,0.2); }
  .vnc-panel {
    padding: 0 30px 20px; display: none;
  }
  .vnc-panel.visible { display: block; }
  .vnc-panel iframe {
    width: 100%; height: 500px; border: 2px solid #252550;
    border-radius: 8px; background: #000;
  }
  .vnc-panel .vnc-header {
    display: flex; justify-content: space-between; align-items: center;
    padding: 10px 0;
  }
  .vnc-panel .vnc-header h3 { font-size: 14px; color: #ff6b00; text-transform: uppercase; letter-spacing: 1px; }
  .vnc-panel .vnc-url { font-size: 12px; color: #666; font-family: monospace; }
  .hp-table { padding: 20px 30px; }
  .hp-table table { width: 100%; border-collapse: collapse; background: #1a1a3e; border-radius: 8px; overflow: hidden; }
  .hp-table th { background: #252550; padding: 10px 15px; text-align: left; font-size: 12px; color: #888; text-transform: uppercase; }
  .hp-table td { padding: 8px 15px; border-top: 1px solid #252550; font-size: 13px; font-family: 'SF Mono', 'Fira Code', monospace; }
  .hp-table tr:hover { background: #252550; }
  .dmg-dealt { color: #00ff88; }
  .dmg-taken { color: #ff4444; }
  @media (max-width: 768px) { .charts { grid-template-columns: 1fr; } .stats-bar { grid-template-columns: repeat(2, 1fr); } }
</style>
</head>
<body>

<div class="header">
  <h1>Saiyan Trainer</h1>
  <div class="status">
    <span class="live" id="live-indicator">LIVE</span>
    <span id="update-time">Updating...</span>
  </div>
</div>

<div class="view-toggle">
  <button class="active" id="btn-charts" onclick="showView('charts')">Charts</button>
  <button id="btn-game" onclick="showView('game')">Live Game</button>
  <button onclick="window.open('http://localhost:6080/vnc.html?autoconnect=true&resize=scale','_blank')">Open VNC (New Tab)</button>
  <button id="btn-split" onclick="showView('split')">Split View</button>
</div>

<div class="vnc-panel" id="vnc-panel">
  <div class="vnc-header">
    <h3>Live Training Pods</h3>
    <div id="pod-selector" style="display:flex;gap:8px;flex-wrap:wrap;"></div>
  </div>
  <div id="no-pods-msg" style="color:#666;padding:20px;text-align:center;">Scanning for training pods...</div>
  <div id="active-pod-label" style="display:none;padding:8px 0;font-size:12px;font-family:monospace;">
    <span style="color:#888;">Connected to:</span> <span id="active-pod-name" style="color:#00ff88;"></span>
    <span id="active-pod-source" style="color:#666;margin-left:10px;"></span>
  </div>
  <iframe id="vnc-frame" src="" allow="autoplay"></iframe>
</div>

<div id="charts-section">
<div class="stats-bar" id="stats-bar">
  <div class="stat-card"><div class="label">Generation</div><div class="value" id="stat-gen">-</div></div>
  <div class="stat-card"><div class="label">Best Fitness</div><div class="value" id="stat-fitness">-</div></div>
  <div class="stat-card"><div class="label">All-Time Best</div><div class="value positive" id="stat-alltime">-</div></div>
  <div class="stat-card"><div class="label">Species</div><div class="value" id="stat-species">-</div></div>
  <div class="stat-card"><div class="label">P2 Damage Dealt</div><div class="value positive" id="stat-p2dmg">-</div></div>
  <div class="stat-card"><div class="label">P1 Damage Taken</div><div class="value negative" id="stat-p1dmg">-</div></div>
</div>

<div class="charts">
  <div class="chart-container full-width">
    <h3>Fitness Over Generations</h3>
    <canvas id="fitnessChart"></canvas>
  </div>
  <div class="chart-container">
    <h3>Species Count</h3>
    <canvas id="speciesChart"></canvas>
  </div>
  <div class="chart-container">
    <h3>HP Deltas (Best Genome)</h3>
    <canvas id="hpChart"></canvas>
  </div>
</div>

<div class="hp-table">
  <table>
    <thead>
      <tr><th>Gen</th><th>Fitness</th><th>Species</th><th>P2 Damage</th><th>P1 Damage</th><th>Frames</th><th>Entropy</th><th>Time</th></tr>
    </thead>
    <tbody id="gen-table"></tbody>
  </table>
</div>

</div><!-- end charts-section -->

<script>
function showView(view) {
  const chartsSection = document.getElementById('charts-section');
  const vncPanel = document.getElementById('vnc-panel');
  const vncFrame = document.getElementById('vnc-frame');
  const btnCharts = document.getElementById('btn-charts');
  const btnGame = document.getElementById('btn-game');
  const btnSplit = document.getElementById('btn-split');

  btnCharts.className = ''; btnGame.className = ''; btnSplit.className = '';

  if (view === 'charts') {
    chartsSection.style.display = 'block';
    vncPanel.className = 'vnc-panel';
    vncFrame.src = '';
    btnCharts.className = 'active';
  } else if (view === 'game') {
    chartsSection.style.display = 'none';
    vncPanel.className = 'vnc-panel visible';
    if (!vncFrame.src || vncFrame.src === '') vncFrame.src = 'http://localhost:6080/vnc.html?autoconnect=true&resize=scale';
    btnGame.className = 'active';
  } else if (view === 'split') {
    chartsSection.style.display = 'block';
    vncPanel.className = 'vnc-panel visible';
    if (!vncFrame.src || vncFrame.src === '') vncFrame.src = 'http://localhost:6080/vnc.html?autoconnect=true&resize=scale';
    btnSplit.className = 'active';
  }
}

const chartDefaults = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { labels: { color: '#888', font: { size: 11 } } } },
  scales: {
    x: { ticks: { color: '#666' }, grid: { color: '#1a1a3e' } },
    y: { ticks: { color: '#666' }, grid: { color: '#252550' } }
  }
};

const fitnessChart = new Chart(document.getElementById('fitnessChart'), {
  type: 'line',
  data: {
    labels: [],
    datasets: [
      { label: 'Best Fitness', data: [], borderColor: '#ff6b00', backgroundColor: 'rgba(255,107,0,0.1)', fill: true, tension: 0.3 },
      { label: 'All-Time Best', data: [], borderColor: '#00ff88', backgroundColor: 'transparent', borderDash: [5,5], tension: 0 }
    ]
  },
  options: chartDefaults
});

const speciesChart = new Chart(document.getElementById('speciesChart'), {
  type: 'bar',
  data: { labels: [], datasets: [{ label: 'Species', data: [], backgroundColor: '#4488ff', borderRadius: 3 }] },
  options: chartDefaults
});

const hpChart = new Chart(document.getElementById('hpChart'), {
  type: 'bar',
  data: {
    labels: [],
    datasets: [
      { label: 'P2 Damage Dealt', data: [], backgroundColor: '#00ff88' },
      { label: 'P1 Damage Taken', data: [], backgroundColor: '#ff4444' }
    ]
  },
  options: chartDefaults
});

function escapeText(str) {
  const div = document.createElement('span');
  div.textContent = str;
  return div.textContent;
}

function updateDashboard(data) {
  if (!data || data.length === 0) return;
  const latest = data[data.length - 1];

  document.getElementById('stat-gen').textContent = latest.generation;
  document.getElementById('stat-fitness').textContent = latest.bestFitness.toFixed(1);
  document.getElementById('stat-alltime').textContent = latest.allTimeBest.toFixed(1);
  document.getElementById('stat-species').textContent = latest.species;
  document.getElementById('stat-p2dmg').textContent = latest.hp ? latest.hp.p2Delta : '-';
  document.getElementById('stat-p1dmg').textContent = latest.hp ? latest.hp.p1Delta : '-';

  const labels = data.map(g => g.generation);
  fitnessChart.data.labels = labels;
  fitnessChart.data.datasets[0].data = data.map(g => g.bestFitness);
  fitnessChart.data.datasets[1].data = data.map(g => g.allTimeBest);
  fitnessChart.update('none');

  speciesChart.data.labels = labels;
  speciesChart.data.datasets[0].data = data.map(g => g.species);
  speciesChart.update('none');

  const hpData = data.filter(g => g.hp);
  hpChart.data.labels = hpData.map(g => g.generation);
  hpChart.data.datasets[0].data = hpData.map(g => Math.abs(g.hp.p2Delta));
  hpChart.data.datasets[1].data = hpData.map(g => Math.abs(g.hp.p1Delta));
  hpChart.update('none');

  // Build table rows safely using DOM methods
  const tbody = document.getElementById('gen-table');
  while (tbody.firstChild) tbody.removeChild(tbody.firstChild);
  data.slice(-20).reverse().forEach(g => {
    const tr = document.createElement('tr');
    const cells = [
      g.generation,
      g.bestFitness.toFixed(1),
      g.species,
      g.hp ? g.hp.p2Delta : '-',
      g.hp ? g.hp.p1Delta : '-',
      g.hp ? g.hp.frames : '-',
      g.combo ? g.combo.entropy.toFixed(2) : '-',
      g.timestamp ? g.timestamp.split(' ')[1] || '-' : '-'
    ];
    cells.forEach((val, i) => {
      const td = document.createElement('td');
      td.textContent = String(val);
      if (i === 3) td.className = 'dmg-dealt';
      if (i === 4) td.className = 'dmg-taken';
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });

  document.getElementById('update-time').textContent =
    'Updated: ' + new Date().toLocaleTimeString();
}

async function poll() {
  try {
    const res = await fetch('/api/stats');
    const data = await res.json();
    updateDashboard(data);
    document.getElementById('live-indicator').textContent = 'LIVE';
    document.getElementById('live-indicator').style.color = '#00ff88';
  } catch (e) {
    document.getElementById('live-indicator').textContent = 'OFFLINE';
    document.getElementById('live-indicator').style.color = '#ff4444';
  }
}

let currentPodUrl = null;
let currentPodName = null;

function setActivePod(name, source, url) {
  currentPodUrl = url;
  currentPodName = name;
  const label = document.getElementById('active-pod-label');
  document.getElementById('active-pod-name').textContent = name;
  document.getElementById('active-pod-source').textContent = '(' + source + ')';
  label.style.display = 'block';
  document.getElementById('vnc-frame').src = url;
}

async function pollPods() {
  try {
    const res = await fetch('/api/pods');
    const pods = await res.json();
    const selector = document.getElementById('pod-selector');
    const noPodsMsg = document.getElementById('no-pods-msg');
    const frame = document.getElementById('vnc-frame');

    while (selector.firstChild) selector.removeChild(selector.firstChild);

    const runningPods = pods.filter(p => p.phase === 'Running' && p.vncUrl);
    if (runningPods.length === 0) {
      noPodsMsg.style.display = 'block';
      noPodsMsg.textContent = 'No training pods found. Start training to see live view.';
      frame.style.display = 'none';
      return;
    }

    noPodsMsg.style.display = 'none';
    frame.style.display = 'block';

    runningPods.forEach(pod => {
      const btn = document.createElement('button');
      const label = pod.taskrun || pod.name;
      btn.textContent = label;
      btn.style.cssText = 'padding:6px 14px;border:1px solid #4488ff;background:transparent;color:#4488ff;border-radius:4px;cursor:pointer;font-size:12px;';
      if (pod.vncUrl === currentPodUrl) {
        btn.style.background = '#4488ff';
        btn.style.color = '#000';
      }
      btn.addEventListener('click', function() {
        setActivePod(label, pod.source, pod.vncUrl);
        pollPods(); // refresh button styles
      });
      selector.appendChild(btn);
    });

    // Auto-select first pod if none selected
    if (!currentPodUrl && runningPods.length > 0) {
      const first = runningPods[0];
      const label = first.taskrun || first.name;
      setActivePod(label, first.source, first.vncUrl);
    }
  } catch (e) {
    // silently fail
  }
}

poll();
pollPods();
setInterval(poll, 5000);
setInterval(pollPods, 10000);
</script>
</body>
</html>
'''


# Track active port-forwards: {pod_name: {"port": local_port, "process": Popen}}
active_forwards = {}
next_vnc_port = 7000

def get_training_pods():
    """Discover training pods via kubectl — finds pods with the mGBA image or saiyan label."""
    pods = []

    # Try Tekton TaskRun pods first
    try:
        result = subprocess.run(
            ["kubectl", "--context", "kind-saiyan", "get", "pods",
             "-l", "app.kubernetes.io/managed-by=tekton-pipelines",
             "-o", "json"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            for item in data.get("items", []):
                name = item["metadata"]["name"]
                phase = item["status"].get("phase", "Unknown")
                taskrun = item["metadata"].get("labels", {}).get("tekton.dev/taskRun", "")
                pods.append({
                    "name": name,
                    "phase": phase,
                    "taskrun": taskrun,
                    "source": "tekton",
                })
    except Exception:
        pass

    # Only Tekton TaskRun pods — no local Docker containers

    return pods


def ensure_port_forward(pod_name):
    """Start a kubectl port-forward for a pod's noVNC port (6080)."""
    global next_vnc_port
    if pod_name in active_forwards:
        proc = active_forwards[pod_name]["process"]
        if proc.poll() is None:  # still running
            return active_forwards[pod_name]["port"]
        # Process died, clean up
        del active_forwards[pod_name]

    local_port = next_vnc_port
    next_vnc_port += 1

    try:
        proc = subprocess.Popen(
            ["kubectl", "--context", "kind-saiyan", "port-forward",
             f"pod/{pod_name}", f"{local_port}:6080"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        active_forwards[pod_name] = {"port": local_port, "process": proc}
        return local_port
    except Exception:
        return None


def get_k8s_metrics():
    """Read metrics.json from training pods via kubectl exec."""
    metrics = []
    try:
        # Find running training pods
        result = subprocess.run(
            ["kubectl", "--context", "kind-saiyan", "get", "pods",
             "-l", "app.kubernetes.io/managed-by=tekton-pipelines",
             "-o", "jsonpath={range .items[?(@.status.phase=='Running')]}{.metadata.name}{' '}{end}"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            for pod_name in result.stdout.strip().split():
                if "train-batch" not in pod_name:
                    continue
                # Read metrics.json from pod
                exec_result = subprocess.run(
                    ["kubectl", "--context", "kind-saiyan", "exec", pod_name,
                     "--", "cat", "/workspace/data/output/results/metrics.json"],
                    capture_output=True, text=True, timeout=10
                )
                if exec_result.returncode == 0 and exec_result.stdout.strip():
                    try:
                        pod_metrics = json.loads(exec_result.stdout)
                        for m in pod_metrics:
                            m["pod"] = pod_name
                        metrics.extend(pod_metrics)
                    except json.JSONDecodeError:
                        pass
    except Exception:
        pass
    return metrics


def format_prometheus_metrics(metrics):
    """Format metrics as Prometheus exposition format."""
    lines = [
        "# HELP saiyan_best_fitness Best fitness score per generation",
        "# TYPE saiyan_best_fitness gauge",
        "# HELP saiyan_avg_fitness Average fitness score per generation",
        "# TYPE saiyan_avg_fitness gauge",
        "# HELP saiyan_species_count Number of NEAT species per generation",
        "# TYPE saiyan_species_count gauge",
        "# HELP saiyan_generation Current generation number",
        "# TYPE saiyan_generation counter",
        "# HELP saiyan_p2_damage Damage dealt to opponent by best genome",
        "# TYPE saiyan_p2_damage gauge",
        "# HELP saiyan_gene_count Number of genes in best genome",
        "# TYPE saiyan_gene_count gauge",
    ]
    for m in metrics:
        batch = m.get("batch", 0)
        gen = m.get("generation", 0)
        pod = m.get("pod", "local")
        labels = f'batch="{batch}",generation="{gen}",pod="{pod}"'
        lines.append(f'saiyan_best_fitness{{{labels}}} {m.get("bestFitness", 0)}')
        lines.append(f'saiyan_avg_fitness{{{labels}}} {m.get("avgFitness", 0):.2f}')
        lines.append(f'saiyan_species_count{{{labels}}} {m.get("species", 0)}')
        lines.append(f'saiyan_generation{{{labels}}} {gen}')
        if m.get("p2HpStart") is not None and m.get("p2HpEnd") is not None:
            damage = m["p2HpStart"] - m["p2HpEnd"]
            lines.append(f'saiyan_p2_damage{{{labels}}} {damage}')
        lines.append(f'saiyan_gene_count{{{labels}}} {m.get("geneCount", 0)}')
    return "\n".join(lines) + "\n"


class DashboardHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(DASHBOARD_HTML.encode())
        elif self.path == '/api/stats':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            # Combine local log stats + K8s pod metrics
            local_data = parse_training_log(LOG_FILE)
            k8s_data = get_k8s_metrics()
            # Convert k8s metrics to same format as local stats
            for m in k8s_data:
                local_data.append({
                    "generation": m.get("generation", 0),
                    "bestFitness": m.get("bestFitness", 0),
                    "allTimeBest": m.get("maxFitness", 0),
                    "species": m.get("species", 0),
                    "genomes": m.get("genomes", 0),
                    "timestamp": m.get("timestamp", ""),
                    "hp": {
                        "p1Start": m.get("p1HpStart", 0),
                        "p1End": m.get("p1HpEnd", 0),
                        "p1Delta": (m.get("p1HpEnd", 0) or 0) - (m.get("p1HpStart", 0) or 0),
                        "p2Start": m.get("p2HpStart", 0),
                        "p2End": m.get("p2HpEnd", 0),
                        "p2Delta": (m.get("p2HpEnd", 0) or 0) - (m.get("p2HpStart", 0) or 0),
                        "frames": m.get("frames", 0),
                    } if m.get("p1HpStart") is not None else None,
                    "combo": None,
                    "source": "k8s:" + m.get("pod", ""),
                })
            self.wfile.write(json.dumps(local_data).encode())
        elif self.path == '/api/pods':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            pods = get_training_pods()
            for pod in pods:
                if pod["source"] == "tekton" and pod["phase"] == "Running":
                    port = ensure_port_forward(pod["name"])
                    if port:
                        pod["vncUrl"] = f"http://localhost:{port}/vnc.html?autoconnect=true&resize=scale"
            self.wfile.write(json.dumps(pods).encode())
        elif self.path == '/api/k8s-metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            metrics = get_k8s_metrics()
            self.wfile.write(json.dumps(metrics).encode())
        elif self.path == '/metrics':
            # Prometheus scrape endpoint
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4')
            self.end_headers()
            local_data = parse_training_log(LOG_FILE)
            k8s_data = get_k8s_metrics()
            all_metrics = k8s_data
            # Add local metrics too
            for g in local_data:
                if g.get("bestFitness") is not None:
                    m = {
                        "batch": 0, "generation": g["generation"],
                        "bestFitness": g["bestFitness"], "avgFitness": 0,
                        "species": g["species"], "pod": "local",
                    }
                    if g.get("hp"):
                        m["p2HpStart"] = g["hp"].get("p2Start")
                        m["p2HpEnd"] = g["hp"].get("p2End")
                    all_metrics.append(m)
            self.wfile.write(format_prometheus_metrics(all_metrics).encode())
        else:
            self.send_error(404)

    def log_message(self, format, *args):
        pass


def main():
    parser = argparse.ArgumentParser(description='Saiyan Trainer Dashboard')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--log', type=str, default=str(LOG_FILE))
    args = parser.parse_args()

    _update_log_file(Path(args.log))
    _start_server(args.port)


def _update_log_file(path):
    global LOG_FILE
    LOG_FILE = path


def _start_server(port):

    server = http.server.HTTPServer(('0.0.0.0', port), DashboardHandler)
    print(f'Dashboard: http://localhost:{port}')
    print(f'Reading: {LOG_FILE}')
    print('Press Ctrl+C to stop')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nStopped.')


if __name__ == '__main__':
    main()

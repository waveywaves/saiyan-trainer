#!/usr/bin/env python3
"""
Saiyan Trainer - Live Training Dashboard

Serves a web dashboard that visualizes NEAT training progress in real-time.
Reads from output/training.log and output/checkpoints/.

Usage:
    python3 scripts/training_dashboard.py [--port 8080] [--log output/training.log]

Then open http://localhost:8080 in your browser.
"""

import atexit
import http.server
import json
import os
import re
import signal
import sys
import subprocess
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
    with open(log_path, 'r') as f:
        for line in f:
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
<title>Saiyan Trainer Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
  *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

  :root {
    --bg-primary: #0a0a1a;
    --bg-secondary: #0f0f28;
    --bg-card: #141432;
    --bg-card-hover: #1a1a40;
    --bg-sidebar: #0c0c22;
    --border-subtle: #1e1e44;
    --border-active: #ff6b00;
    --accent: #ff6b00;
    --accent-dim: rgba(255, 107, 0, 0.15);
    --accent-glow: rgba(255, 107, 0, 0.3);
    --green: #00ff88;
    --green-dim: rgba(0, 255, 136, 0.15);
    --red: #ff4444;
    --red-dim: rgba(255, 68, 68, 0.15);
    --blue: #4488ff;
    --blue-dim: rgba(68, 136, 255, 0.15);
    --text-primary: #e8e8f0;
    --text-secondary: #8888aa;
    --text-muted: #555577;
    --font-sans: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif;
    --font-mono: 'SF Mono', 'Fira Code', 'JetBrains Mono', 'Cascadia Code', monospace;
    --sidebar-width: 240px;
    --radius: 10px;
    --radius-sm: 6px;
  }

  html, body { height: 100%; }
  body {
    font-family: var(--font-sans);
    background: var(--bg-primary);
    color: var(--text-primary);
    display: flex;
    overflow: hidden;
  }

  /* ---- Sidebar ---- */
  .sidebar {
    width: var(--sidebar-width);
    min-width: var(--sidebar-width);
    background: var(--bg-sidebar);
    border-right: 1px solid var(--border-subtle);
    display: flex;
    flex-direction: column;
    height: 100vh;
    position: relative;
    z-index: 10;
  }
  .sidebar-brand {
    padding: 24px 20px 20px;
    border-bottom: 1px solid var(--border-subtle);
  }
  .sidebar-brand h1 {
    font-size: 18px;
    font-weight: 700;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 3px;
  }
  .sidebar-brand .subtitle {
    font-size: 11px;
    color: var(--text-muted);
    margin-top: 4px;
    letter-spacing: 1px;
    text-transform: uppercase;
  }
  .sidebar-nav {
    flex: 1;
    padding: 12px 0;
    overflow-y: auto;
  }
  .nav-section-label {
    font-size: 10px;
    font-weight: 600;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 1.5px;
    padding: 16px 20px 8px;
  }
  .nav-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 20px;
    cursor: pointer;
    color: var(--text-secondary);
    font-size: 13px;
    font-weight: 500;
    transition: all 0.15s ease;
    border-left: 3px solid transparent;
    text-decoration: none;
  }
  .nav-item:hover {
    background: var(--accent-dim);
    color: var(--text-primary);
  }
  .nav-item.active {
    color: var(--accent);
    background: var(--accent-dim);
    border-left-color: var(--accent);
  }
  .nav-item svg {
    width: 18px;
    height: 18px;
    flex-shrink: 0;
    opacity: 0.7;
  }
  .nav-item.active svg { opacity: 1; }

  .sidebar-footer {
    padding: 16px 20px;
    border-top: 1px solid var(--border-subtle);
    font-size: 11px;
  }
  .sidebar-footer .status-dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--green);
    margin-right: 6px;
    animation: pulse-dot 2s infinite;
  }
  .sidebar-footer .status-dot.offline { background: var(--red); animation: none; }
  .sidebar-footer .status-text { color: var(--text-muted); }
  @keyframes pulse-dot {
    0%, 100% { opacity: 1; box-shadow: 0 0 0 0 rgba(0, 255, 136, 0.4); }
    50% { opacity: 0.7; box-shadow: 0 0 0 4px rgba(0, 255, 136, 0); }
  }

  /* ---- Main Content ---- */
  .main {
    flex: 1;
    overflow-y: auto;
    overflow-x: hidden;
    height: 100vh;
    scrollbar-width: thin;
    scrollbar-color: var(--border-subtle) transparent;
  }
  .main::-webkit-scrollbar { width: 6px; }
  .main::-webkit-scrollbar-track { background: transparent; }
  .main::-webkit-scrollbar-thumb { background: var(--border-subtle); border-radius: 3px; }

  .page { display: none; padding: 28px 32px 48px; }
  .page.active { display: block; }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 24px;
  }
  .page-header h2 {
    font-size: 22px;
    font-weight: 700;
    color: var(--text-primary);
  }
  .page-header .timestamp {
    font-size: 12px;
    color: var(--text-muted);
    font-family: var(--font-mono);
  }

  /* ---- Stat Cards ---- */
  .stat-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 16px;
    margin-bottom: 24px;
  }
  .stat-card {
    background: var(--bg-card);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius);
    padding: 20px;
    transition: all 0.2s ease;
    position: relative;
    overflow: hidden;
  }
  .stat-card::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 2px;
    background: var(--accent);
    opacity: 0;
    transition: opacity 0.2s;
  }
  .stat-card:hover {
    border-color: var(--accent);
    background: var(--bg-card-hover);
  }
  .stat-card:hover::before { opacity: 1; }
  .stat-card .stat-label {
    font-size: 11px;
    font-weight: 600;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-bottom: 8px;
  }
  .stat-card .stat-value {
    font-size: 32px;
    font-weight: 700;
    font-family: var(--font-mono);
    color: var(--text-primary);
    line-height: 1;
  }
  .stat-card .stat-trend {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    margin-top: 8px;
    font-size: 12px;
    font-weight: 500;
    padding: 2px 8px;
    border-radius: 20px;
  }
  .stat-card .stat-trend.up {
    color: var(--green);
    background: var(--green-dim);
  }
  .stat-card .stat-trend.down {
    color: var(--red);
    background: var(--red-dim);
  }
  .stat-card .stat-trend.neutral {
    color: var(--text-muted);
    background: rgba(85, 85, 119, 0.15);
  }
  .stat-card.accent-green .stat-value { color: var(--green); }
  .stat-card.accent-red .stat-value { color: var(--red); }
  .stat-card.accent-blue .stat-value { color: var(--blue); }

  /* ---- Chart Panels ---- */
  .chart-panel {
    background: var(--bg-card);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius);
    padding: 20px 24px;
    margin-bottom: 20px;
  }
  .chart-panel .chart-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-bottom: 16px;
  }
  .chart-panel canvas { width: 100% !important; }
  .chart-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 20px;
    margin-bottom: 20px;
  }

  /* ---- Data Table ---- */
  .data-table-wrapper {
    background: var(--bg-card);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius);
    overflow: hidden;
  }
  .data-table-wrapper .table-header {
    padding: 16px 20px;
    border-bottom: 1px solid var(--border-subtle);
  }
  .data-table-wrapper .table-header h3 {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .data-table {
    width: 100%;
    border-collapse: collapse;
  }
  .data-table th {
    padding: 10px 16px;
    text-align: left;
    font-size: 10px;
    font-weight: 600;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 1px;
    background: var(--bg-secondary);
    border-bottom: 1px solid var(--border-subtle);
  }
  .data-table td {
    padding: 10px 16px;
    font-size: 13px;
    font-family: var(--font-mono);
    color: var(--text-secondary);
    border-bottom: 1px solid rgba(30, 30, 68, 0.5);
  }
  .data-table tbody tr { transition: background 0.1s; }
  .data-table tbody tr:hover { background: var(--bg-card-hover); }
  .data-table .cell-positive { color: var(--green); }
  .data-table .cell-negative { color: var(--red); }

  /* ---- Live Training Page ---- */
  .pod-card-grid {
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
    margin-bottom: 20px;
  }
  .pod-select-card {
    background: var(--bg-card);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-sm);
    padding: 14px 20px;
    cursor: pointer;
    transition: all 0.15s ease;
    min-width: 180px;
  }
  .pod-select-card:hover {
    border-color: var(--blue);
    background: var(--bg-card-hover);
  }
  .pod-select-card.selected {
    border-color: var(--accent);
    background: var(--accent-dim);
  }
  .pod-select-card .pod-card-name {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
    margin-bottom: 4px;
    word-break: break-all;
  }
  .pod-select-card .pod-card-meta {
    font-size: 11px;
    color: var(--text-muted);
    font-family: var(--font-mono);
  }

  .vnc-container {
    background: var(--bg-card);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius);
    overflow: hidden;
  }
  .vnc-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 20px;
    border-bottom: 1px solid var(--border-subtle);
    background: var(--bg-secondary);
  }
  .vnc-toolbar .connected-label {
    font-size: 12px;
    color: var(--text-muted);
    font-family: var(--font-mono);
  }
  .vnc-toolbar .connected-label .pod-name { color: var(--green); }
  .vnc-frame-wrap {
    position: relative;
    width: 100%;
    padding-bottom: 56.25%; /* 16:9 */
    background: #000;
  }
  .vnc-frame-wrap iframe {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    border: none;
  }
  .vnc-empty-state {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 300px;
    color: var(--text-muted);
    font-size: 14px;
    flex-direction: column;
    gap: 8px;
  }
  .vnc-empty-state svg { opacity: 0.3; width: 48px; height: 48px; }

  /* ---- Pods Page ---- */
  .status-badge {
    display: inline-flex;
    align-items: center;
    padding: 3px 10px;
    border-radius: 20px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.5px;
    text-transform: uppercase;
  }
  .status-badge.running { background: var(--green-dim); color: var(--green); }
  .status-badge.succeeded { background: var(--blue-dim); color: var(--blue); }
  .status-badge.failed { background: var(--red-dim); color: var(--red); }
  .status-badge.pending { background: rgba(255,200,0,0.15); color: #ffcc00; }
  .status-badge.unknown { background: rgba(85,85,119,0.15); color: var(--text-muted); }

  .vnc-link {
    color: var(--blue);
    text-decoration: none;
    font-size: 12px;
    font-family: var(--font-mono);
    transition: color 0.15s;
  }
  .vnc-link:hover { color: var(--accent); text-decoration: underline; }

  /* ---- Metrics Page ---- */
  .metric-link-card {
    background: var(--bg-card);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius);
    padding: 24px;
    margin-bottom: 20px;
  }
  .metric-link-card h3 {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-primary);
    margin-bottom: 8px;
  }
  .metric-link-card a {
    color: var(--blue);
    font-family: var(--font-mono);
    font-size: 13px;
    word-break: break-all;
  }
  .metric-link-card a:hover { color: var(--accent); }
  .metric-link-card p {
    font-size: 12px;
    color: var(--text-muted);
    margin-top: 6px;
  }

  .json-viewer {
    background: var(--bg-secondary);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius);
    padding: 20px;
    max-height: 500px;
    overflow: auto;
    font-family: var(--font-mono);
    font-size: 12px;
    line-height: 1.6;
    color: var(--text-secondary);
    white-space: pre-wrap;
    word-break: break-all;
  }

  /* ---- Mobile Sidebar Toggle ---- */
  .mobile-header {
    display: none;
    position: fixed;
    top: 0; left: 0; right: 0;
    height: 56px;
    background: var(--bg-sidebar);
    border-bottom: 1px solid var(--border-subtle);
    z-index: 20;
    align-items: center;
    padding: 0 16px;
  }
  .mobile-header .menu-btn {
    background: none;
    border: none;
    color: var(--text-primary);
    cursor: pointer;
    padding: 8px;
  }
  .mobile-header .menu-btn svg { width: 24px; height: 24px; }
  .mobile-header h1 {
    font-size: 16px;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 2px;
    margin-left: 12px;
  }
  .sidebar-overlay {
    display: none;
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.5);
    z-index: 9;
  }

  @media (max-width: 768px) {
    .mobile-header { display: flex; }
    .sidebar {
      position: fixed;
      left: -260px;
      transition: left 0.25s ease;
      z-index: 15;
    }
    .sidebar.open { left: 0; }
    .sidebar.open + .sidebar-overlay { display: block; }
    .main { padding-top: 56px; }
    .page { padding: 20px 16px 48px; }
    .stat-grid { grid-template-columns: repeat(2, 1fr); }
    .chart-row { grid-template-columns: 1fr; }
  }
</style>
</head>
<body>

<!-- Mobile Header -->
<div class="mobile-header">
  <button class="menu-btn" onclick="toggleSidebar()">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/></svg>
  </button>
  <h1>Saiyan Trainer</h1>
</div>

<!-- Sidebar -->
<nav class="sidebar" id="sidebar">
  <div class="sidebar-brand">
    <h1>Saiyan Trainer</h1>
    <div class="subtitle">NEAT Training Dashboard</div>
  </div>
  <div class="sidebar-nav">
    <div class="nav-section-label">Dashboard</div>
    <a class="nav-item active" data-page="overview" onclick="navigate('overview', this)">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
      Overview
    </a>
    <a class="nav-item" data-page="live" onclick="navigate('live', this)">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg>
      Live Training
    </a>
    <a class="nav-item" data-page="islands" onclick="navigate('islands', this)">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="6" cy="6" r="3"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="18" r="3"/><line x1="9" y1="6" x2="15" y2="6" stroke-dasharray="2"/><line x1="6" y1="9" x2="6" y2="15" stroke-dasharray="2"/><line x1="18" y1="9" x2="18" y2="15" stroke-dasharray="2"/><line x1="9" y1="18" x2="15" y2="18" stroke-dasharray="2"/></svg>
      Islands
    </a>
    <a class="nav-item" data-page="networks" onclick="navigate('networks', this)">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="5" cy="6" r="2"/><circle cx="5" cy="12" r="2"/><circle cx="5" cy="18" r="2"/><circle cx="12" cy="9" r="2"/><circle cx="12" cy="15" r="2"/><circle cx="19" cy="12" r="2"/><line x1="7" y1="6" x2="10" y2="9"/><line x1="7" y1="12" x2="10" y2="9"/><line x1="7" y1="12" x2="10" y2="15"/><line x1="7" y1="18" x2="10" y2="15"/><line x1="14" y1="9" x2="17" y2="12"/><line x1="14" y1="15" x2="17" y2="12"/></svg>
      Networks
    </a>
    <div class="nav-section-label">Infrastructure</div>
    <a class="nav-item" data-page="pods" onclick="navigate('pods', this)">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="5" width="20" height="14" rx="2"/><line x1="2" y1="10" x2="22" y2="10"/><circle cx="6" cy="7.5" r="1" fill="currentColor"/><circle cx="10" cy="7.5" r="1" fill="currentColor"/></svg>
      Pods
    </a>
    <a class="nav-item" data-page="metrics" onclick="navigate('metrics', this)">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>
      Metrics
    </a>
  </div>
  <div class="sidebar-footer">
    <span class="status-dot" id="status-dot"></span>
    <span id="status-label" style="color:var(--green);font-weight:600;">LIVE</span>
    <div class="status-text" id="update-time" style="margin-top:4px;">Connecting...</div>
  </div>
</nav>
<div class="sidebar-overlay" id="sidebar-overlay" onclick="toggleSidebar()"></div>

<!-- Main Content -->
<div class="main">

  <!-- ======================== OVERVIEW PAGE ======================== -->
  <div class="page active" id="page-overview">
    <div class="page-header">
      <h2>Overview</h2>
      <div class="timestamp" id="overview-timestamp">--</div>
    </div>

    <div class="stat-grid">
      <div class="stat-card">
        <div class="stat-label">Generation</div>
        <div class="stat-value" id="stat-gen">--</div>
        <div class="stat-trend neutral" id="trend-gen">--</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Best Fitness</div>
        <div class="stat-value" id="stat-fitness">--</div>
        <div class="stat-trend neutral" id="trend-fitness">--</div>
      </div>
      <div class="stat-card accent-blue">
        <div class="stat-label">Species</div>
        <div class="stat-value" id="stat-species">--</div>
        <div class="stat-trend neutral" id="trend-species">--</div>
      </div>
      <div class="stat-card accent-green">
        <div class="stat-label">Damage Dealt</div>
        <div class="stat-value" id="stat-dmg-dealt">--</div>
        <div class="stat-trend neutral" id="trend-dmg">--</div>
      </div>
    </div>

    <div class="chart-panel">
      <div class="chart-title">Fitness Over Generations</div>
      <div style="height:280px;"><canvas id="fitnessChart"></canvas></div>
    </div>

    <div class="chart-row">
      <div class="chart-panel">
        <div class="chart-title">Species Count</div>
        <div style="height:220px;"><canvas id="speciesChart"></canvas></div>
      </div>
      <div class="chart-panel">
        <div class="chart-title">HP Deltas (Best Genome)</div>
        <div style="height:220px;"><canvas id="hpChart"></canvas></div>
      </div>
    </div>

    <div class="data-table-wrapper">
      <div class="table-header"><h3>Recent Generations</h3></div>
      <table class="data-table">
        <thead>
          <tr>
            <th>Gen</th><th>Fitness</th><th>All-Time</th><th>Species</th>
            <th>P2 Dmg</th><th>P1 Dmg</th><th>Frames</th><th>Entropy</th><th>Time</th>
          </tr>
        </thead>
        <tbody id="gen-table"></tbody>
      </table>
    </div>
  </div>

  <!-- ======================== LIVE TRAINING PAGE ======================== -->
  <div class="page" id="page-live">
    <div class="page-header">
      <h2>Live Training</h2>
      <div style="display:flex;gap:8px;">
        <button onclick="setVncMode('single')" id="btn-single" style="padding:6px 12px;border:1px solid var(--accent);background:transparent;color:var(--accent);border-radius:4px;cursor:pointer;font-size:11px;">SINGLE</button>
        <button onclick="setVncMode('grid')" id="btn-grid" style="padding:6px 12px;border:1px solid var(--accent);background:var(--accent);color:#000;border-radius:4px;cursor:pointer;font-size:11px;">GRID VIEW</button>
      </div>
    </div>

    <div id="live-pod-selector" class="pod-card-grid"></div>

    <div class="vnc-container" id="vnc-container">
      <div class="vnc-toolbar" id="vnc-toolbar" style="display:none;">
        <div class="connected-label">
          Connected to: <span class="pod-name" id="vnc-pod-name">--</span>
        </div>
      </div>
      <div id="vnc-empty" class="vnc-empty-state">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
        <span>No training pods detected</span>
        <span style="font-size:12px;">Start a Tekton training pipeline to see the live view</span>
      </div>
      <div class="vnc-frame-wrap" id="vnc-frame-wrap" style="display:none;">
        <iframe id="vnc-frame" src="" allow="autoplay"></iframe>
      </div>
      <div id="vnc-grid" style="display:none;display:grid;grid-template-columns:repeat(auto-fit,minmax(400px,1fr));gap:10px;"></div>
    </div>
  </div>

  <!-- ======================== PODS PAGE ======================== -->
  <div class="page" id="page-pods">
    <div class="page-header">
      <h2>Tekton Pods</h2>
      <div class="timestamp" id="pods-timestamp">--</div>
    </div>

    <div class="data-table-wrapper">
      <div class="table-header"><h3>Training Pods</h3></div>
      <table class="data-table">
        <thead>
          <tr><th>Pod Name</th><th>Status</th><th>TaskRun</th><th>Source</th><th>VNC</th></tr>
        </thead>
        <tbody id="pods-table"></tbody>
      </table>
    </div>
  </div>

  <!-- ======================== ISLANDS PAGE ======================== -->
  <div class="page" id="page-islands">
    <div class="page-header">
      <h2>Island Comparison</h2>
      <button onclick="downloadIslandData()" style="background:var(--accent);color:#fff;border:none;padding:8px 16px;border-radius:6px;cursor:pointer;font-size:13px;">Export JSON</button>
    </div>

    <div class="chart-panel">
      <div class="chart-title">Fitness Progression (All Islands)</div>
      <canvas id="island-fitness-chart" height="300"></canvas>
    </div>

    <div class="chart-panel">
      <div class="chart-title">P2 Damage Dealt (All Islands)</div>
      <canvas id="island-damage-chart" height="250"></canvas>
    </div>

    <div class="chart-panel">
      <div class="chart-title">Species Count (All Islands)</div>
      <canvas id="island-species-chart" height="250"></canvas>
    </div>

    <div class="chart-panel">
      <div class="chart-title">Island Summary</div>
      <table style="width:100%;border-collapse:collapse;color:var(--fg);" id="island-table">
        <thead>
          <tr style="border-bottom:1px solid var(--border);">
            <th style="padding:8px;text-align:left;">Island</th>
            <th style="padding:8px;text-align:right;">Gens</th>
            <th style="padding:8px;text-align:right;">Best Fitness</th>
            <th style="padding:8px;text-align:right;">P2 Damage</th>
            <th style="padding:8px;text-align:right;">Species</th>
            <th style="padding:8px;text-align:right;">Entropy</th>
          </tr>
        </thead>
        <tbody></tbody>
      </table>
    </div>

    <div class="chart-panel">
      <div class="chart-title">Raw Island Data</div>
      <div class="json-viewer" id="json-island-viewer">Loading...</div>
    </div>
  </div>

  <!-- ======================== NETWORKS PAGE ======================== -->
  <div class="page" id="page-networks">
    <div class="page-header">
      <h2>Network Evolution</h2>
    </div>

    <div class="chart-panel" style="padding:16px;">
      <div style="display:flex;align-items:center;gap:16px;margin-bottom:12px;flex-wrap:wrap;">
        <label style="color:var(--fg-dim);font-size:13px;">Island:
          <select id="net-island-select" onchange="renderSelectedNetwork()" style="background:var(--card);color:var(--fg);border:1px solid var(--border);padding:4px 8px;border-radius:4px;margin-left:4px;"></select>
        </label>
        <label style="color:var(--fg-dim);font-size:13px;">Generation:
          <input type="range" id="net-gen-slider" min="0" max="0" value="0" oninput="renderSelectedNetwork()" style="width:200px;vertical-align:middle;">
          <span id="net-gen-label" style="color:var(--fg);font-weight:600;margin-left:4px;">0</span>
        </label>
        <span id="net-info" style="color:var(--fg-dim);font-size:12px;"></span>
      </div>
      <canvas id="network-canvas" width="800" height="400" style="width:100%;background:var(--bg);border-radius:8px;border:1px solid var(--border);"></canvas>
    </div>

    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(380px,1fr));gap:16px;">
      <div class="chart-panel">
        <div class="chart-title">Gene Count</div>
        <canvas id="gene-count-chart" height="200"></canvas>
      </div>
      <div class="chart-panel">
        <div class="chart-title">Hidden Nodes</div>
        <canvas id="hidden-nodes-chart" height="200"></canvas>
      </div>
    </div>
  </div>

  <!-- ======================== METRICS PAGE ======================== -->
  <div class="page" id="page-metrics">
    <div class="page-header">
      <h2>Metrics</h2>
    </div>

    <div class="metric-link-card">
      <h3>Prometheus Endpoint</h3>
      <a href="/metrics" target="_blank">/metrics</a>
      <p>Exposes training metrics in Prometheus exposition format. Add this endpoint to your Prometheus scrape config.</p>
    </div>

    <div class="metric-link-card">
      <h3>Raw Kubernetes Metrics</h3>
      <a href="/api/k8s-metrics" target="_blank">/api/k8s-metrics</a>
      <p>Returns raw JSON metrics collected from training pods via kubectl exec.</p>
    </div>

    <div class="chart-panel">
      <div class="chart-title">Raw JSON Metrics</div>
      <div class="json-viewer" id="json-metrics-viewer">Loading...</div>
    </div>
  </div>

</div><!-- end .main -->

<script>
/* ---- Navigation ---- */
function navigate(page, el) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  document.getElementById('page-' + page).classList.add('active');
  if (el) el.classList.add('active');
  if (page === 'metrics') loadMetrics();
  if (page === 'islands') loadIslands();
  if (page === 'networks') loadNetworks();
  closeSidebar();
}
function toggleSidebar() {
  document.getElementById('sidebar').classList.toggle('open');
}
function closeSidebar() {
  document.getElementById('sidebar').classList.remove('open');
}

/* ---- Chart.js Defaults ---- */
Chart.defaults.color = '#555577';
Chart.defaults.font.family = "system-ui, -apple-system, sans-serif";
Chart.defaults.font.size = 11;

const gridColor = 'rgba(30, 30, 68, 0.8)';
const baseChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 600, easing: 'easeOutQuart' },
  plugins: {
    legend: { labels: { color: '#8888aa', usePointStyle: true, pointStyle: 'circle', padding: 16, font: { size: 11 } } },
    tooltip: {
      backgroundColor: '#1a1a40',
      titleColor: '#e8e8f0',
      bodyColor: '#8888aa',
      borderColor: '#1e1e44',
      borderWidth: 1,
      cornerRadius: 8,
      padding: 12,
      displayColors: true,
      usePointStyle: true,
    }
  },
  scales: {
    x: { ticks: { color: '#555577', maxTicksLimit: 20 }, grid: { color: gridColor, drawBorder: false } },
    y: { ticks: { color: '#555577' }, grid: { color: gridColor, drawBorder: false } }
  }
};

/* ---- Fitness Chart ---- */
const fitnessChart = new Chart(document.getElementById('fitnessChart'), {
  type: 'line',
  data: {
    labels: [],
    datasets: [
      {
        label: 'Best Fitness',
        data: [],
        borderColor: '#ff6b00',
        backgroundColor: (ctx) => {
          const g = ctx.chart.ctx.createLinearGradient(0, 0, 0, ctx.chart.height);
          g.addColorStop(0, 'rgba(255, 107, 0, 0.25)');
          g.addColorStop(1, 'rgba(255, 107, 0, 0.0)');
          return g;
        },
        fill: true,
        tension: 0.4,
        borderWidth: 2,
        pointRadius: 0,
        pointHitRadius: 10,
      },
      {
        label: 'All-Time Best',
        data: [],
        borderColor: '#00ff88',
        backgroundColor: 'transparent',
        borderDash: [6, 4],
        borderWidth: 1.5,
        tension: 0,
        pointRadius: 0,
        pointHitRadius: 10,
      }
    ]
  },
  options: { ...baseChartOptions }
});

/* ---- Species Chart ---- */
const speciesChart = new Chart(document.getElementById('speciesChart'), {
  type: 'bar',
  data: {
    labels: [],
    datasets: [{
      label: 'Species',
      data: [],
      backgroundColor: 'rgba(68, 136, 255, 0.6)',
      hoverBackgroundColor: 'rgba(68, 136, 255, 0.85)',
      borderRadius: 4,
      borderSkipped: false,
    }]
  },
  options: { ...baseChartOptions, plugins: { ...baseChartOptions.plugins, legend: { display: false } } }
});

/* ---- HP Deltas Chart ---- */
const hpChart = new Chart(document.getElementById('hpChart'), {
  type: 'bar',
  data: {
    labels: [],
    datasets: [
      { label: 'P2 Damage Dealt', data: [], backgroundColor: 'rgba(0, 255, 136, 0.6)', hoverBackgroundColor: 'rgba(0, 255, 136, 0.85)', borderRadius: 4, borderSkipped: false },
      { label: 'P1 Damage Taken', data: [], backgroundColor: 'rgba(255, 68, 68, 0.5)', hoverBackgroundColor: 'rgba(255, 68, 68, 0.8)', borderRadius: 4, borderSkipped: false }
    ]
  },
  options: baseChartOptions
});

/* ---- Trend Helpers ---- */
let previousStats = null;

function trendArrow(current, previous) {
  if (previous === null || previous === undefined) return { text: '--', cls: 'neutral' };
  const diff = current - previous;
  if (diff > 0) return { text: '+' + diff.toFixed(1) + ' ^', cls: 'up' };
  if (diff < 0) return { text: diff.toFixed(1) + ' v', cls: 'down' };
  return { text: '0', cls: 'neutral' };
}

function setTrend(id, trend) {
  const el = document.getElementById(id);
  el.textContent = trend.text;
  el.className = 'stat-trend ' + trend.cls;
}

/* ---- Update Dashboard ---- */
function updateDashboard(data) {
  if (!data || data.length === 0) return;
  const latest = data[data.length - 1];
  const prev = data.length >= 2 ? data[data.length - 2] : null;

  // Stat cards
  document.getElementById('stat-gen').textContent = latest.generation;
  document.getElementById('stat-fitness').textContent = latest.bestFitness.toFixed(1);
  document.getElementById('stat-species').textContent = latest.species;
  const dmgDealt = latest.hp ? Math.abs(latest.hp.p2Delta) : 0;
  document.getElementById('stat-dmg-dealt').textContent = latest.hp ? dmgDealt : '--';

  // Trends
  if (prev) {
    setTrend('trend-gen', { text: 'Gen ' + latest.generation, cls: 'neutral' });
    setTrend('trend-fitness', trendArrow(latest.bestFitness, prev.bestFitness));
    setTrend('trend-species', trendArrow(latest.species, prev.species));
    const prevDmg = prev.hp ? Math.abs(prev.hp.p2Delta) : 0;
    setTrend('trend-dmg', trendArrow(dmgDealt, prevDmg));
  }

  // Timestamp
  document.getElementById('overview-timestamp').textContent =
    'Updated: ' + new Date().toLocaleTimeString();

  // Fitness chart
  const labels = data.map(g => g.generation);
  fitnessChart.data.labels = labels;
  fitnessChart.data.datasets[0].data = data.map(g => g.bestFitness);
  fitnessChart.data.datasets[1].data = data.map(g => g.allTimeBest);
  fitnessChart.update();

  // Species chart
  speciesChart.data.labels = labels;
  speciesChart.data.datasets[0].data = data.map(g => g.species);
  speciesChart.update();

  // HP chart
  const hpData = data.filter(g => g.hp);
  hpChart.data.labels = hpData.map(g => g.generation);
  hpChart.data.datasets[0].data = hpData.map(g => Math.abs(g.hp.p2Delta));
  hpChart.data.datasets[1].data = hpData.map(g => Math.abs(g.hp.p1Delta));
  hpChart.update();

  // Table
  const tbody = document.getElementById('gen-table');
  while (tbody.firstChild) tbody.removeChild(tbody.firstChild);
  data.slice(-20).reverse().forEach(g => {
    const tr = document.createElement('tr');
    const cells = [
      g.generation,
      g.bestFitness.toFixed(1),
      g.allTimeBest.toFixed(1),
      g.species,
      g.hp ? g.hp.p2Delta : '--',
      g.hp ? g.hp.p1Delta : '--',
      g.hp ? g.hp.frames : '--',
      g.combo ? g.combo.entropy.toFixed(2) : '--',
      g.timestamp ? g.timestamp.split(' ')[1] || '--' : '--'
    ];
    cells.forEach((val, i) => {
      const td = document.createElement('td');
      td.textContent = String(val);
      if (i === 4) td.className = 'cell-positive';
      if (i === 5) td.className = 'cell-negative';
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });

  previousStats = latest;
}

/* ---- Polling ---- */
async function poll() {
  try {
    const res = await fetch('/api/stats');
    const data = await res.json();
    updateDashboard(data);
    document.getElementById('status-dot').className = 'status-dot';
    document.getElementById('status-label').textContent = 'LIVE';
    document.getElementById('status-label').style.color = 'var(--green)';
    document.getElementById('update-time').textContent = new Date().toLocaleTimeString();
  } catch (e) {
    document.getElementById('status-dot').className = 'status-dot offline';
    document.getElementById('status-label').textContent = 'OFFLINE';
    document.getElementById('status-label').style.color = 'var(--red)';
  }
}

/* ---- Pod Management (VNC) ---- */
let currentPodUrl = null;
let currentPodName = null;
let vncMode = 'grid';

function setVncMode(mode) {
  vncMode = mode;
  document.getElementById('btn-single').style.background = mode === 'single' ? 'var(--accent)' : 'transparent';
  document.getElementById('btn-single').style.color = mode === 'single' ? '#000' : 'var(--accent)';
  document.getElementById('btn-grid').style.background = mode === 'grid' ? 'var(--accent)' : 'transparent';
  document.getElementById('btn-grid').style.color = mode === 'grid' ? '#000' : 'var(--accent)';
  renderPodCards(lastPods);
}

function selectPod(name, source, url) {
  currentPodUrl = url;
  currentPodName = name;
  document.getElementById('vnc-pod-name').textContent = name;
  document.getElementById('vnc-toolbar').style.display = 'flex';
  document.getElementById('vnc-empty').style.display = 'none';
  document.getElementById('vnc-frame-wrap').style.display = 'block';
  document.getElementById('vnc-grid').style.display = 'none';
  document.getElementById('vnc-frame').src = url;
  vncMode = 'single';
  document.getElementById('btn-single').style.background = 'var(--accent)';
  document.getElementById('btn-single').style.color = '#000';
  document.getElementById('btn-grid').style.background = 'transparent';
  document.getElementById('btn-grid').style.color = 'var(--accent)';
  renderPodCards(lastPods);
}

function renderGridView(pods) {
  const grid = document.getElementById('vnc-grid');
  while (grid.firstChild) grid.removeChild(grid.firstChild);
  const runningPods = pods.filter(p => p.phase === 'Running' && p.vncUrl);
  if (runningPods.length === 0) return;

  document.getElementById('vnc-empty').style.display = 'none';
  document.getElementById('vnc-frame-wrap').style.display = 'none';
  document.getElementById('vnc-toolbar').style.display = 'none';
  grid.style.display = 'grid';
  grid.style.gridTemplateColumns = 'repeat(2, 1fr)';

  runningPods.forEach(pod => {
    const cell = document.createElement('div');
    cell.style.cssText = 'background:var(--card-bg);border-radius:8px;overflow:hidden;border:1px solid var(--border);';
    const label = document.createElement('div');
    label.style.cssText = 'padding:6px 12px;font-size:11px;color:var(--accent);font-family:monospace;border-bottom:1px solid var(--border);display:flex;justify-content:space-between;align-items:center;';
    label.textContent = pod.taskrun || pod.name;
    const statusDot = document.createElement('span');
    statusDot.style.cssText = 'width:8px;height:8px;border-radius:50%;background:#00ff88;display:inline-block;';
    label.appendChild(statusDot);
    const iframe = document.createElement('iframe');
    iframe.src = pod.vncUrl + '&reconnect=true';
    iframe.style.cssText = 'width:100%;height:400px;border:none;background:#000;';
    iframe.allow = 'autoplay';
    cell.appendChild(label);
    cell.appendChild(iframe);
    grid.appendChild(cell);
  });
}

let lastPods = [];
function renderPodCards(pods) {
  lastPods = pods;
  const container = document.getElementById('live-pod-selector');
  while (container.firstChild) container.removeChild(container.firstChild);

  const runningPods = pods.filter(p => p.phase === 'Running' && p.vncUrl);
  if (runningPods.length === 0) {
    document.getElementById('vnc-empty').style.display = 'flex';
    document.getElementById('vnc-frame-wrap').style.display = 'none';
    document.getElementById('vnc-grid').style.display = 'none';
    document.getElementById('vnc-toolbar').style.display = 'none';
    return;
  }

  // Grid mode: show all VNC streams at once
  if (vncMode === 'grid') {
    renderGridView(pods);
    // Still render pod cards but don't auto-select
  }

  runningPods.forEach(pod => {
    const card = document.createElement('div');
    card.className = 'pod-select-card' + (pod.vncUrl === currentPodUrl ? ' selected' : '');
    const nameDiv = document.createElement('div');
    nameDiv.className = 'pod-card-name';
    nameDiv.textContent = pod.taskrun || pod.name;
    const metaDiv = document.createElement('div');
    metaDiv.className = 'pod-card-meta';
    metaDiv.textContent = pod.phase + ' / ' + pod.source;
    card.appendChild(nameDiv);
    card.appendChild(metaDiv);
    card.addEventListener('click', function() {
      selectPod(pod.taskrun || pod.name, pod.source, pod.vncUrl);
    });
    container.appendChild(card);
  });

  // Auto-select first
  if (!currentPodUrl && runningPods.length > 0) {
    const first = runningPods[0];
    selectPod(first.taskrun || first.name, first.source, first.vncUrl);
  }
}

async function pollPods() {
  try {
    const res = await fetch('/api/pods');
    const pods = await res.json();
    renderPodCards(pods);
    renderPodsTable(pods);
  } catch (e) { /* silent */ }
}

/* ---- Pods Table ---- */
function renderPodsTable(pods) {
  const tbody = document.getElementById('pods-table');
  while (tbody.firstChild) tbody.removeChild(tbody.firstChild);

  document.getElementById('pods-timestamp').textContent =
    'Updated: ' + new Date().toLocaleTimeString();

  if (pods.length === 0) {
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = 5;
    td.textContent = 'No Tekton pods found';
    td.style.textAlign = 'center';
    td.style.color = 'var(--text-muted)';
    td.style.padding = '32px';
    tr.appendChild(td);
    tbody.appendChild(tr);
    return;
  }

  pods.forEach(pod => {
    const tr = document.createElement('tr');

    // Name
    const tdName = document.createElement('td');
    tdName.textContent = pod.name;
    tdName.style.fontWeight = '500';
    tdName.style.color = 'var(--text-primary)';
    tr.appendChild(tdName);

    // Status badge
    const tdStatus = document.createElement('td');
    const badge = document.createElement('span');
    const phase = (pod.phase || 'Unknown').toLowerCase();
    badge.className = 'status-badge ' + phase;
    badge.textContent = pod.phase || 'Unknown';
    tdStatus.appendChild(badge);
    tr.appendChild(tdStatus);

    // TaskRun
    const tdTask = document.createElement('td');
    tdTask.textContent = pod.taskrun || '--';
    tr.appendChild(tdTask);

    // Source
    const tdSource = document.createElement('td');
    tdSource.textContent = pod.source || '--';
    tr.appendChild(tdSource);

    // VNC Link
    const tdVnc = document.createElement('td');
    if (pod.vncUrl) {
      const a = document.createElement('a');
      a.className = 'vnc-link';
      a.href = pod.vncUrl;
      a.target = '_blank';
      a.textContent = 'Open VNC';
      tdVnc.appendChild(a);
    } else {
      tdVnc.textContent = '--';
      tdVnc.style.color = 'var(--text-muted)';
    }
    tr.appendChild(tdVnc);

    tbody.appendChild(tr);
  });
}

/* ---- Metrics Page ---- */
async function loadMetrics() {
  const viewer = document.getElementById('json-metrics-viewer');
  try {
    const res = await fetch('/api/k8s-metrics');
    const data = await res.json();
    viewer.textContent = JSON.stringify(data, null, 2);
  } catch (e) {
    viewer.textContent = 'Failed to load metrics: ' + e.message;
  }
}

/* ---- Island Comparison ---- */
const ISLAND_COLORS = ['#ff6b6b', '#4ecdc4', '#45b7d1', '#f9ca24', '#a29bfe', '#fd79a8'];
let islandCharts = {};
let islandData = null;

async function loadIslands() {
  try {
    const res = await fetch('/api/island-stats');
    islandData = await res.json();
    renderIslandCharts(islandData);
    renderIslandTable(islandData);
    document.getElementById('json-island-viewer').textContent = JSON.stringify(islandData, null, 2);
  } catch (e) {
    document.getElementById('json-island-viewer').textContent = 'Failed: ' + e.message;
  }
}

function renderIslandCharts(data) {
  const islands = Object.keys(data).sort();
  if (!islands.length) return;

  // Fitness chart
  const fitnessCtx = document.getElementById('island-fitness-chart');
  if (islandCharts.fitness) islandCharts.fitness.destroy();
  islandCharts.fitness = new Chart(fitnessCtx, {
    type: 'line',
    data: {
      datasets: islands.map((id, i) => ({
        label: id,
        data: data[id].map(g => ({x: g.generation, y: g.bestFitness})),
        borderColor: ISLAND_COLORS[i % ISLAND_COLORS.length],
        backgroundColor: ISLAND_COLORS[i % ISLAND_COLORS.length] + '22',
        borderWidth: 2, tension: 0.3, fill: true, pointRadius: 3,
      }))
    },
    options: {
      responsive: true,
      scales: {
        x: {type: 'linear', title: {display: true, text: 'Generation'}},
        y: {title: {display: true, text: 'Best Fitness'}, beginAtZero: true}
      },
      plugins: {legend: {labels: {color: '#aab'}}}
    }
  });

  // Damage chart
  const damageCtx = document.getElementById('island-damage-chart');
  if (islandCharts.damage) islandCharts.damage.destroy();
  islandCharts.damage = new Chart(damageCtx, {
    type: 'line',
    data: {
      datasets: islands.map((id, i) => ({
        label: id,
        data: data[id].filter(g => g.hp).map(g => ({x: g.generation, y: Math.abs(g.hp.p2Delta)})),
        borderColor: ISLAND_COLORS[i % ISLAND_COLORS.length],
        borderWidth: 2, tension: 0.3, pointRadius: 3,
      }))
    },
    options: {
      responsive: true,
      scales: {
        x: {type: 'linear', title: {display: true, text: 'Generation'}},
        y: {title: {display: true, text: 'P2 Damage Dealt'}, beginAtZero: true}
      },
      plugins: {legend: {labels: {color: '#aab'}}}
    }
  });

  // Species chart
  const speciesCtx = document.getElementById('island-species-chart');
  if (islandCharts.species) islandCharts.species.destroy();
  islandCharts.species = new Chart(speciesCtx, {
    type: 'line',
    data: {
      datasets: islands.map((id, i) => ({
        label: id,
        data: data[id].map(g => ({x: g.generation, y: g.species})),
        borderColor: ISLAND_COLORS[i % ISLAND_COLORS.length],
        borderWidth: 2, tension: 0.3, pointRadius: 3,
      }))
    },
    options: {
      responsive: true,
      scales: {
        x: {type: 'linear', title: {display: true, text: 'Generation'}},
        y: {title: {display: true, text: 'Species Count'}, beginAtZero: true}
      },
      plugins: {legend: {labels: {color: '#aab'}}}
    }
  });
}

function renderIslandTable(data) {
  const tbody = document.querySelector('#island-table tbody');
  tbody.textContent = '';
  for (const [id, gens] of Object.entries(data).sort()) {
    if (!gens.length) continue;
    const last = gens[gens.length - 1];
    const bestFitness = Math.max(...gens.map(g => g.bestFitness));
    const maxDamage = Math.max(...gens.filter(g => g.hp).map(g => Math.abs(g.hp.p2Delta)));
    const entropy = last.combo ? last.combo.entropy.toFixed(2) : '--';
    const tr = document.createElement('tr');
    tr.style.borderBottom = '1px solid var(--border)';
    const cells = [id, gens.length, bestFitness.toFixed(1), maxDamage, last.species, entropy];
    cells.forEach((val, ci) => {
      const td = document.createElement('td');
      td.style.padding = '8px';
      td.textContent = val;
      if (ci === 0) td.style.fontWeight = '600';
      if (ci > 0) td.style.textAlign = 'right';
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  }
}

function downloadIslandData() {
  if (!islandData) return;
  const blob = new Blob([JSON.stringify(islandData, null, 2)], {type: 'application/json'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'island-training-data.json';
  a.click();
}

/* ---- Network Visualization ---- */
let networkData = null;
let netCharts = {};

async function loadNetworks() {
  try {
    const res = await fetch('/api/island-networks');
    networkData = await res.json();
    setupNetworkControls();
    renderSelectedNetwork();
    renderNetworkCharts();
  } catch (e) {
    console.error('Failed to load networks:', e);
  }
}

function setupNetworkControls() {
  const select = document.getElementById('net-island-select');
  select.textContent = '';
  const islands = Object.keys(networkData).sort();
  islands.forEach(id => {
    const opt = document.createElement('option');
    opt.value = id;
    opt.textContent = id;
    select.appendChild(opt);
  });
  if (islands.length > 0) {
    const gens = networkData[islands[0]];
    const slider = document.getElementById('net-gen-slider');
    slider.max = Math.max(0, gens.length - 1);
    slider.value = gens.length - 1;
  }
}

function renderSelectedNetwork() {
  const island = document.getElementById('net-island-select').value;
  if (!networkData || !networkData[island]) return;
  const gens = networkData[island];
  const slider = document.getElementById('net-gen-slider');
  slider.max = Math.max(0, gens.length - 1);
  const idx = parseInt(slider.value);
  const gen = gens[Math.min(idx, gens.length - 1)];
  document.getElementById('net-gen-label').textContent = 'Gen ' + gen.generation;
  document.getElementById('net-info').textContent =
    'Fitness: ' + gen.fitness + ' | Genes: ' + gen.geneCount +
    ' | Hidden: ' + gen.nodes.filter(n => n.type === 'hidden').length;
  drawNetwork(gen);
}

function drawNetwork(gen) {
  const canvas = document.getElementById('network-canvas');
  const ctx = canvas.getContext('2d');
  const W = canvas.width = canvas.offsetWidth * 2;
  const H = canvas.height = 400 * 2;
  ctx.scale(2, 2);
  const w = W / 2, h = H / 2;
  ctx.clearRect(0, 0, w, h);

  const inputs = gen.nodes.filter(n => n.type === 'input');
  const outputs = gen.nodes.filter(n => n.type === 'output');
  const hidden = gen.nodes.filter(n => n.type === 'hidden');

  // Layout: inputs left, outputs right, hidden middle
  const pad = 40;
  const positions = {};
  inputs.forEach((n, i) => {
    positions[n.id] = {x: pad + 30, y: pad + i * ((h - 2*pad) / Math.max(1, inputs.length - 1))};
  });
  outputs.forEach((n, i) => {
    positions[n.id] = {x: w - pad - 30, y: pad + i * ((h - 2*pad) / Math.max(1, outputs.length - 1))};
  });
  // Spread hidden nodes in middle columns
  const cols = Math.max(1, Math.ceil(hidden.length / 6));
  hidden.forEach((n, i) => {
    const col = Math.floor(i / 6);
    const row = i % 6;
    const xStart = pad + 100;
    const xEnd = w - pad - 100;
    const x = cols === 1 ? (xStart + xEnd) / 2 : xStart + col * ((xEnd - xStart) / Math.max(1, cols - 1));
    const rowCount = Math.min(6, hidden.length - col * 6);
    const y = pad + 20 + row * ((h - 2*pad - 40) / Math.max(1, rowCount - 1));
    positions[n.id] = {x, y};
  });

  // Draw connections
  gen.connections.forEach(c => {
    const from = positions[c.from];
    const to = positions[c.to];
    if (!from || !to) return;
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    if (!c.enabled) {
      ctx.strokeStyle = 'rgba(100,100,100,0.15)';
      ctx.lineWidth = 0.5;
    } else if (c.weight > 0) {
      const alpha = Math.min(1, Math.abs(c.weight) / 2);
      ctx.strokeStyle = 'rgba(78,205,196,' + alpha + ')';
      ctx.lineWidth = Math.min(3, Math.abs(c.weight));
    } else {
      const alpha = Math.min(1, Math.abs(c.weight) / 2);
      ctx.strokeStyle = 'rgba(255,107,107,' + alpha + ')';
      ctx.lineWidth = Math.min(3, Math.abs(c.weight));
    }
    ctx.stroke();
  });

  // Draw nodes
  const colors = {input: '#4ecdc4', output: '#f9ca24', hidden: '#a29bfe'};
  gen.nodes.forEach(n => {
    const pos = positions[n.id];
    if (!pos) return;
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, n.type === 'hidden' ? 8 : 12, 0, Math.PI * 2);
    ctx.fillStyle = colors[n.type];
    ctx.fill();
    ctx.strokeStyle = '#1a1a2e';
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.fillStyle = '#e0e0ff';
    ctx.font = '9px system-ui';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    if (n.type === 'input') {
      ctx.textAlign = 'right';
      ctx.fillText(n.label, pos.x - 16, pos.y);
    } else if (n.type === 'output') {
      ctx.textAlign = 'left';
      ctx.fillText(n.label, pos.x + 16, pos.y);
    }
  });

  // Legend
  ctx.font = '10px system-ui';
  ctx.textAlign = 'left';
  ctx.fillStyle = '#4ecdc4'; ctx.fillText('● Input', 10, h - 30);
  ctx.fillStyle = '#a29bfe'; ctx.fillText('● Hidden', 70, h - 30);
  ctx.fillStyle = '#f9ca24'; ctx.fillText('● Output', 140, h - 30);
  ctx.fillStyle = '#4ecdc4'; ctx.fillText('— positive weight', 210, h - 30);
  ctx.fillStyle = '#ff6b6b'; ctx.fillText('— negative weight', 330, h - 30);
}

function renderNetworkCharts() {
  const islands = Object.keys(networkData).sort();
  if (!islands.length) return;

  // Gene count chart
  const geneCtx = document.getElementById('gene-count-chart');
  if (netCharts.genes) netCharts.genes.destroy();
  netCharts.genes = new Chart(geneCtx, {
    type: 'line',
    data: {
      datasets: islands.map((id, i) => ({
        label: id,
        data: networkData[id].map(g => ({x: g.generation, y: g.geneCount})),
        borderColor: ISLAND_COLORS[i % ISLAND_COLORS.length],
        borderWidth: 2, tension: 0.3, pointRadius: 3,
      }))
    },
    options: {
      responsive: true,
      scales: {
        x: {type: 'linear', title: {display: true, text: 'Generation'}},
        y: {title: {display: true, text: 'Genes'}, beginAtZero: true}
      },
      plugins: {legend: {labels: {color: '#aab'}}}
    }
  });

  // Hidden nodes chart
  const hiddenCtx = document.getElementById('hidden-nodes-chart');
  if (netCharts.hidden) netCharts.hidden.destroy();
  netCharts.hidden = new Chart(hiddenCtx, {
    type: 'line',
    data: {
      datasets: islands.map((id, i) => ({
        label: id,
        data: networkData[id].map(g => ({
          x: g.generation,
          y: g.nodes.filter(n => n.type === 'hidden').length
        })),
        borderColor: ISLAND_COLORS[i % ISLAND_COLORS.length],
        borderWidth: 2, tension: 0.3, pointRadius: 3,
      }))
    },
    options: {
      responsive: true,
      scales: {
        x: {type: 'linear', title: {display: true, text: 'Generation'}},
        y: {title: {display: true, text: 'Hidden Nodes'}, beginAtZero: true}
      },
      plugins: {legend: {labels: {color: '#aab'}}}
    }
  });
}

/* ---- Init ---- */
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

# Cache for expensive kubectl calls — persisted to disk
import time as _time
_cache = {}
_CACHE_TTL = 30  # seconds
_CACHE_DIR = PROJECT_ROOT / ".dashboard-cache"

def _cache_path(key):
    return _CACHE_DIR / f"{key}.json"

def _load_disk_cache(key):
    p = _cache_path(key)
    if p.exists():
        try:
            with open(p, "r") as f:
                obj = json.load(f)
            _cache[key] = {"data": obj["data"], "ts": obj["ts"]}
            return True
        except (json.JSONDecodeError, KeyError):
            pass
    return False

def _save_disk_cache(key, data, ts):
    _CACHE_DIR.mkdir(exist_ok=True)
    with open(_cache_path(key), "w") as f:
        json.dump({"data": data, "ts": ts}, f)

def cached_fetch(key, fetch_fn):
    """Serve from memory or disk cache, refresh when TTL expires."""
    now = _time.time()
    # In-memory hit
    if key in _cache and now - _cache[key]["ts"] < _CACHE_TTL:
        return _cache[key]["data"]
    # Cold start: load disk cache as if it were fresh (instant first page load)
    if key not in _cache and _load_disk_cache(key):
        _cache[key]["ts"] = now  # treat disk data as fresh
        return _cache[key]["data"]
    # TTL expired or no cache: fetch fresh
    data = fetch_fn()
    if data:
        _cache[key] = {"data": data, "ts": now}
        _save_disk_cache(key, data, now)
    elif key in _cache:
        return _cache[key]["data"]
    return data
next_vnc_port = 7000


def cleanup_port_forwards():
    """Terminate all kubectl port-forward subprocesses."""
    for name, info in active_forwards.items():
        try:
            info["process"].terminate()
            info["process"].wait(timeout=5)
        except Exception:
            try:
                info["process"].kill()
            except Exception:
                pass


atexit.register(cleanup_port_forwards)
signal.signal(signal.SIGTERM, lambda s, f: (cleanup_port_forwards(), sys.exit(0)))


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

    if next_vnc_port > 7999:
        # Reclaim ports from dead forwards before wrapping
        dead = [name for name, info in active_forwards.items()
                if info["process"].poll() is not None]
        for name in dead:
            del active_forwards[name]
        next_vnc_port = 7000

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
    """Read metrics.json from all island directories on training pods."""
    metrics = []
    try:
        result = subprocess.run(
            ["kubectl", "--context", "kind-saiyan", "get", "pods",
             "--field-selector=status.phase=Running",
             "-o", "jsonpath={range .items[*]}{.metadata.name}{' '}{end}"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            return metrics
        pods = [p for p in result.stdout.strip().split() if "train-batch" in p]
        if not pods:
            return metrics
        # Use first available pod to scan all island directories on shared PVC
        pod_name = pods[0]
        find_result = subprocess.run(
            ["kubectl", "--context", "kind-saiyan", "exec", pod_name,
             "--", "find", "/workspace/data/output", "-name", "metrics.json", "-path", "*/results/*"],
            capture_output=True, text=True, timeout=10
        )
        if find_result.returncode != 0:
            return metrics
        for metrics_path in find_result.stdout.strip().split("\n"):
            if not metrics_path:
                continue
            # Extract island ID from path (e.g., /workspace/data/output/island-1/results/metrics.json)
            parts = metrics_path.split("/")
            island_id = "unknown"
            for i, part in enumerate(parts):
                if part == "output" and i + 1 < len(parts) and parts[i + 1] != "results":
                    island_id = parts[i + 1]
                    break
            exec_result = subprocess.run(
                ["kubectl", "--context", "kind-saiyan", "exec", pod_name,
                 "--", "cat", metrics_path],
                capture_output=True, text=True, timeout=10
            )
            if exec_result.returncode == 0 and exec_result.stdout.strip():
                try:
                    pod_metrics = json.loads(exec_result.stdout)
                    for m in pod_metrics:
                        m["pod"] = pod_name
                        m["island"] = island_id
                    metrics.extend(pod_metrics)
                except json.JSONDecodeError:
                    pass
    except Exception:
        pass
    return metrics


def get_island_stats():
    """Read training logs from all island directories for comparison."""
    islands = {}
    try:
        result = subprocess.run(
            ["kubectl", "--context", "kind-saiyan", "get", "pods",
             "--field-selector=status.phase=Running",
             "-o", "jsonpath={range .items[*]}{.metadata.name}{' '}{end}"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            return islands
        pods = [p for p in result.stdout.strip().split() if "train-batch" in p]
        if not pods:
            return islands
        pod_name = pods[0]
        # Find all training logs
        find_result = subprocess.run(
            ["kubectl", "--context", "kind-saiyan", "exec", pod_name,
             "--", "find", "/workspace/data/output", "-name", "training.log"],
            capture_output=True, text=True, timeout=10
        )
        if find_result.returncode != 0:
            return islands
        for log_path in find_result.stdout.strip().split("\n"):
            if not log_path:
                continue
            parts = log_path.split("/")
            island_id = "default"
            for i, part in enumerate(parts):
                if part == "output" and i + 1 < len(parts) and parts[i + 1] != "training.log":
                    island_id = parts[i + 1]
                    break
            exec_result = subprocess.run(
                ["kubectl", "--context", "kind-saiyan", "exec", pod_name,
                 "--", "cat", log_path],
                capture_output=True, text=True, timeout=10
            )
            if exec_result.returncode == 0:
                # Write to temp file and parse
                import tempfile
                with tempfile.NamedTemporaryFile(mode='w', suffix='.log', delete=False) as f:
                    f.write(exec_result.stdout)
                    tmp_path = Path(f.name)
                gens = parse_training_log(tmp_path)
                tmp_path.unlink()
                if gens:
                    islands[island_id] = gens
    except Exception:
        pass
    return islands


def get_island_networks():
    """Read checkpoint files from all islands in one kubectl call, extract best genome networks."""
    islands = {}
    try:
        result = subprocess.run(
            ["kubectl", "--context", "kind-saiyan", "get", "pods",
             "--field-selector=status.phase=Running",
             "-o", "jsonpath={range .items[*]}{.metadata.name}{' '}{end}"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            return islands
        pods = [p for p in result.stdout.strip().split() if "train-batch" in p]
        if not pods:
            return islands
        pod_name = pods[0]

        # Single kubectl exec: extract only best genome genes from each checkpoint
        # Uses python3 on the pod to parse JSON and output minimal data
        script = r'''python3 -c "
import json, os, glob
result = {}
for f in sorted(glob.glob('/workspace/data/output/*/checkpoints/gen_*.json')):
    parts = f.split('/')
    island = parts[4]
    gen = int(parts[-1].replace('gen_','').replace('.json',''))
    try:
        with open(f) as fh:
            cp = json.load(fh)
        best, bf = None, -1e9
        for sp in cp.get('species',[]):
            for g in sp.get('genomes',[]):
                if g.get('fitness',0) > bf:
                    bf = g['fitness']; best = g
        if best:
            if island not in result: result[island] = []
            result[island].append({
                'g': gen, 'f': round(bf,1),
                'm': best.get('maxneuron',0),
                'genes': [{'i':g['into'],'o':g['out'],'w':round(g['weight'],3),'e':g.get('enabled',True)} for g in best.get('genes',[])]
            })
    except: pass
for k in result: result[k].sort(key=lambda x:x['g'])
print(json.dumps(result))
"'''
        exec_result = subprocess.run(
            ["kubectl", "--context", "kind-saiyan", "exec", pod_name, "--", "sh", "-c", script],
            capture_output=True, text=True, timeout=30
        )
        if exec_result.returncode != 0:
            return islands

        # Parse compact JSON output from pod-side python script
        max_nodes = 1000000
        num_inputs = 5
        num_outputs = 8
        input_labels = ["P1HP", "P2HP", "P1Ki", "P1Pwr", "Bias"]
        output_labels = ["A", "B", "L", "R", "Up", "Down", "Left", "Right"]

        try:
            raw = json.loads(exec_result.stdout.strip())
        except json.JSONDecodeError:
            return islands

        for island_id, gens in raw.items():
            islands[island_id] = []
            for g in gens:
                nodes = set()
                connections = []
                for gene in g.get("genes", []):
                    nodes.add(gene["i"])
                    nodes.add(gene["o"])
                    connections.append({
                        "from": gene["i"], "to": gene["o"],
                        "weight": gene["w"], "enabled": gene.get("e", True),
                    })

                classified_nodes = []
                for n in sorted(nodes):
                    if 1 <= n <= num_inputs:
                        classified_nodes.append({"id": n, "type": "input", "label": input_labels[n - 1]})
                    elif max_nodes < n <= max_nodes + num_outputs:
                        idx = n - max_nodes - 1
                        classified_nodes.append({"id": n, "type": "output", "label": output_labels[idx]})
                    else:
                        classified_nodes.append({"id": n, "type": "hidden", "label": f"H{n}"})

                islands[island_id].append({
                    "generation": g["g"],
                    "fitness": g["f"],
                    "maxneuron": g.get("m", 0),
                    "geneCount": len(g.get("genes", [])),
                    "nodes": classified_nodes,
                    "connections": connections,
                })
    except Exception:
        pass
    return islands


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
            self.end_headers()
            # Combine local log stats + K8s pod metrics
            local_data = parse_training_log(LOG_FILE)
            k8s_data = cached_fetch("k8s-metrics", get_k8s_metrics)
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
            self.end_headers()
            pods = cached_fetch("pods", get_training_pods)
            for pod in pods:
                if pod["source"] == "tekton" and pod["phase"] == "Running":
                    port = ensure_port_forward(pod["name"])
                    if port:
                        pod["vncUrl"] = f"http://localhost:{port}/vnc_lite.html?autoconnect=true&resize=scale"
            self.wfile.write(json.dumps(pods).encode())
        elif self.path == '/api/island-networks':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            networks = cached_fetch("island-networks", get_island_networks)
            self.wfile.write(json.dumps(networks).encode())
        elif self.path == '/api/island-stats':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            islands = cached_fetch("island-stats", get_island_stats)
            self.wfile.write(json.dumps(islands).encode())
        elif self.path == '/api/k8s-metrics':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            metrics = cached_fetch("k8s-metrics", get_k8s_metrics)
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

    server = http.server.HTTPServer(('127.0.0.1', port), DashboardHandler)
    print(f'Dashboard: http://localhost:{port}')
    print(f'Reading: {LOG_FILE}')
    print('Press Ctrl+C to stop')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nStopped.')


if __name__ == '__main__':
    main()

#!/usr/bin/env node
/**
 * Cross-platform launcher for edge parallel-18 probe (Windows PowerShell / Unix bash).
 */
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const env = {
  ...process.env,
  EDGE_PROBE_RESOLVE:
    process.env.EDGE_PROBE_RESOLVE ?? 'gitlab.lilangverse.xyz:443:192.168.10.33',
  EDGE_PROBE_LABEL: process.env.EDGE_PROBE_LABEL ?? 'parallel-edge',
};

function run(cmd, args) {
  const result = spawnSync(cmd, args, { stdio: 'inherit', env, shell: false });
  process.exit(result.status ?? 1);
}

if (process.platform === 'win32') {
  run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(dir, 'edge-parallel-18-probe.ps1')]);
}

run('bash', [path.join(dir, 'run-edge-parallel-18-probe.sh')]);

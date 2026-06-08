#!/usr/bin/env python3
"""Patch Shiphook server.js for ?format=json&async=1 → 202 Accepted."""
from pathlib import Path

p = Path.home() / "staging/shiphook-pkg/package/dist/server.js"
text = p.read_text()

if "wantsAsync" in text:
    print("already patched", p)
    raise SystemExit(0)

needle = """        const trigger = parseDeployTriggerPayload(rawBody);
        await enqueueAppDeploy(matchedApp, async () => {
            const requestUrl = new URL(req.url ?? "", "http://localhost");
            const wantsJson = requestUrl.searchParams.get("format") === "json";
            // Default: stream deploy output as plain text so GitHub Actions can show it live."""

replacement = """        const trigger = parseDeployTriggerPayload(rawBody);
        const requestUrl = new URL(req.url ?? "", "http://localhost");
        const wantsJson = requestUrl.searchParams.get("format") === "json";
        const wantsAsync = requestUrl.searchParams.get("async") === "1" || requestUrl.searchParams.get("async") === "true";

        if (wantsAsync && wantsJson) {
            const { randomUUID } = await import("node:crypto");
            const jobId = randomUUID();
            const acceptBody = JSON.stringify({ status: "accepted", jobId, app: matchedApp.name });
            res.writeHead(202, {
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(acceptBody),
            });
            res.end(acceptBody);
            void enqueueAppDeploy(matchedApp, async () => {
                const startedAt = new Date();
                const result = await pullAndRun(matchedApp.repoPath, matchedApp.runScript, {
                    timeoutMs: matchedApp.runTimeoutMs,
                    skipPull: trigger.skipPull,
                    gitCheckout: trigger.gitCheckout,
                    deployEnv: trigger.deployEnv,
                });
                const finishedAt = new Date();
                try {
                    await writeDeployLogs({
                        repoPath: matchedApp.repoPath,
                        runScript: result.runScriptApplied ?? matchedApp.runScript,
                        startedAt,
                        finishedAt,
                        result,
                    });
                }
                catch (err) {
                    const details = err instanceof Error ? err.message : String(err);
                    console.error(`shiphook: async job ${jobId} log write failed: ${details}`);
                }
                console.log(`shiphook: async job ${jobId} app=${matchedApp.name} ok=${result.success}`);
            }).catch((err) => {
                const details = err instanceof Error ? err.message : String(err);
                console.error(`shiphook: async job ${jobId} failed: ${details}`);
            });
            return;
        }

        await enqueueAppDeploy(matchedApp, async () => {
            // Default: stream deploy output as plain text so GitHub Actions can show it live."""

if needle not in text:
    raise SystemExit("patch anchor not found — server.js version may differ")

p.write_text(text.replace(needle, replacement, 1))
print("patched", p)

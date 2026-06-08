#!/usr/bin/env python3
"""Move async 202 before readRequestBody to avoid li-httpd POST body deadlock."""
from pathlib import Path

p = Path.home() / "staging/shiphook-pkg/package/dist/server.js"
text = p.read_text()

if "asyncBeforeBody" in text:
    print("already v2 patched", p)
    raise SystemExit(0)

if "wantsAsync" not in text:
    raise SystemExit("run patch-shiphook-async.py first")

old = """        let rawBody = \"\";
        try {
            rawBody = await readRequestBody(req);
        }
        catch (err) {
            const details = err instanceof Error ? err.message : String(err);
            res.writeHead(413, { \"Content-Type\": \"application/json\" });
            res.end(JSON.stringify({ ok: false, error: \"Payload too large\", details }));
            return;
        }
        const trigger = parseDeployTriggerPayload(rawBody);
        const requestUrl = new URL(req.url ?? \"\", \"http://localhost\");
        const wantsJson = requestUrl.searchParams.get(\"format\") === \"json\";
        const wantsAsync = requestUrl.searchParams.get(\"async\") === \"1\" || requestUrl.searchParams.get(\"async\") === \"true\";

        if (wantsAsync && wantsJson) {
            const { randomUUID } = await import(\"node:crypto\");
            const jobId = randomUUID();
            const acceptBody = JSON.stringify({ status: \"accepted\", jobId, app: matchedApp.name });
            res.writeHead(202, {
                \"Content-Type\": \"application/json\",
                \"Content-Length\": Buffer.byteLength(acceptBody),
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

        await enqueueAppDeploy(matchedApp, async () => {"""

new = """        const requestUrl = new URL(req.url ?? \"\", \"http://localhost\");
        const wantsJson = requestUrl.searchParams.get(\"format\") === \"json\";
        const wantsAsync = requestUrl.searchParams.get(\"async\") === \"1\" || requestUrl.searchParams.get(\"async\") === \"true\";

        if (wantsAsync && wantsJson) {
            const { randomUUID } = await import(\"node:crypto\");
            const jobId = randomUUID();
            const acceptBody = JSON.stringify({ status: \"accepted\", jobId, app: matchedApp.name });
            res.writeHead(202, {
                \"Content-Type\": \"application/json\",
                \"Content-Length\": Buffer.byteLength(acceptBody),
            });
            res.end(acceptBody);
            void (async () => {
                let rawBody = \"\";
                try {
                    rawBody = await readRequestBody(req);
                }
                catch (err) {
                    const details = err instanceof Error ? err.message : String(err);
                    console.error(`shiphook: async job ${jobId} body read failed: ${details}`);
                    return;
                }
                const trigger = parseDeployTriggerPayload(rawBody);
                await enqueueAppDeploy(matchedApp, async () => {
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
                });
            })().catch((err) => {
                const details = err instanceof Error ? err.message : String(err);
                console.error(`shiphook: async job ${jobId} failed: ${details}`);
            });
            return;
        }

        let rawBody = \"\";
        try {
            rawBody = await readRequestBody(req);
        }
        catch (err) {
            const details = err instanceof Error ? err.message : String(err);
            res.writeHead(413, { \"Content-Type\": \"application/json\" });
            res.end(JSON.stringify({ ok: false, error: \"Payload too large\", details }));
            return;
        }
        const trigger = parseDeployTriggerPayload(rawBody);
        await enqueueAppDeploy(matchedApp, async () => {"""

if old not in text:
    raise SystemExit("v2 anchor not found")

text = text.replace(old, new, 1)
text = text.replace("export function createShiphookServer(config, options) {",
                    "export function createShiphookServer(config, options) {\n    // asyncBeforeBody", 1)
p.write_text(text)
print("v2 patched", p)

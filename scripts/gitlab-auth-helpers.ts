import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

export const HOMELAB_ROOT = path.join(__dirname, "..");
export const STORAGE_STATE = path.join(HOMELAB_ROOT, ".playwright", "gitlab-session.json");
export const TOKEN_LOCAL = path.join(HOMELAB_ROOT, ".gitlab-token.local");

export type GitLabAuthEnv = {
  host: string;
  edgeIp: string;
  nodeIp: string;
  baseUrl: string;
  signInUrl: string;
  useNodeport: boolean;
};

export function resolveAuthEnv(): GitLabAuthEnv {
  const host = process.env.GITLAB_HOST ?? "gitlab.lilangverse.xyz";
  const edgeIp = process.env.EDGE_IP ?? "192.168.10.33";
  const nodeIp = process.env.GITLAB_NODE_IP ?? "192.168.10.32";
  const nodeport = process.env.GITLAB_NODEPORT ?? "30481";
  const useNodeport = process.env.GITLAB_USE_NODEPORT === "1";
  const baseUrl =
    process.env.GITLAB_BASE_URL ??
    (useNodeport ? `http://${nodeIp}:${nodeport}` : `https://${host}`);
  const signInUrl = `${baseUrl.replace(/\/$/, "")}/users/sign_in`;
  return { host, edgeIp, nodeIp, baseUrl, signInUrl, useNodeport };
}

export function kubeconfig(): string {
  return process.env.KUBECONFIG ?? path.join(process.env.HOME ?? process.env.USERPROFILE ?? "", ".kube", "config-homelab");
}

export function readRootPasswordFromK8s(): string {
  const ns = process.env.GITLAB_NAMESPACE ?? "gitlab";
  const secret = process.env.GITLAB_SECRET_NAME ?? "gitlab-secrets";
  const key = process.env.GITLAB_ROOT_PASSWORD_KEY ?? "GITLAB_ROOT_PASSWORD";
  const b64 = execSync(
    `kubectl --kubeconfig "${kubeconfig()}" -n ${ns} get secret ${secret} -o jsonpath="{.data.${key}}"`,
    { encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },
  ).trim();
  if (!b64) throw new Error(`empty ${key} in secret ${secret} (namespace ${ns})`);
  return Buffer.from(b64, "base64").toString("utf8").replace(/\r?\n$/, "");
}

export function writeTokenLocal(token: string, target = TOKEN_LOCAL): void {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, `GITLAB_TOKEN=${token}\n`, { mode: 0o600 });
}

export function upsertEnvLocalToken(token: string, envLocal = path.join(HOMELAB_ROOT, "..", ".env.local")): void {
  const file = process.env.GITLAB_TOKEN_OUT ?? envLocal;
  if (!fs.existsSync(file)) {
    writeTokenLocal(token, file);
    return;
  }
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
  let found = false;
  const out = lines.map((line) => {
    if (line.startsWith("GITLAB_TOKEN=")) {
      found = true;
      return `GITLAB_TOKEN=${token}`;
    }
    return line;
  });
  if (!found) out.push(`GITLAB_TOKEN=${token}`);
  fs.writeFileSync(file, out.join("\n") + (out[out.length - 1] === "" ? "" : "\n"));
}

export function tokenSuffix(token: string): string {
  return token.length >= 4 ? token.slice(-4) : "????";
}

#!/usr/bin/env node
/**
 * Cross-platform GitLab PAT mint via kubectl + gitlab-rails.
 * Writes gitignored .gitlab-token.local (or OUT_FILE).
 */
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..");

const patName = process.env.PAT_NAME ?? "dev-workstation";
const patScopes = process.env.PAT_SCOPES ?? "api,read_api,read_repository,write_repository";
const outFile = process.env.OUT_FILE ?? path.join(root, ".gitlab-token.local");
const kubeconfig =
  process.env.KUBECONFIG ?? path.join(os.homedir(), ".kube", "config-homelab");
const namespace = process.env.GITLAB_NAMESPACE ?? "gitlab";
const pod = process.env.GITLAB_POD ?? "gitlab-0";
const outPod = "/tmp/gitlab-mint-pat-out";
const scriptPod = "/tmp/gitlab-mint-pat.rb";

process.env.KUBECONFIG = kubeconfig;

function kubectl(args, input) {
  return execSync(`kubectl ${args}`, {
    encoding: "utf8",
    input,
    stdio: ["pipe", "pipe", "pipe"],
    env: process.env,
  });
}

const ruby = `user = User.find_by(username: 'root')
user = User.admins.first if user.nil?
abort('no admin user') unless user
name = '${patName.replace(/'/g, "\\'")}'
scopes = '${patScopes}'.split(',').map(&:strip)
available = Gitlab::Auth.all_available_scopes.map(&:to_s)
scopes = scopes & available
abort('no valid scopes') if scopes.empty?
out_file = '${outPod}'
user.personal_access_tokens.where(name: name).find_each { |t| t.revoke! unless t.revoked? }
token = PersonalAccessToken.new(user: user, name: name, scopes: scopes, expires_at: 1.year.from_now)
token.save!
File.write(out_file, token.token)
`;

kubectl(`exec -i -n ${namespace} ${pod} -- tee ${scriptPod}`, ruby);
kubectl(
  `exec -n ${namespace} ${pod} -- gitlab-rails runner "load '${scriptPod}'"`,
);
const token = kubectl(`exec -n ${namespace} ${pod} -- cat ${outPod}`).trim();
try {
  kubectl(`exec -n ${namespace} ${pod} -- rm -f ${outPod} ${scriptPod}`);
} catch {
  // cleanup best-effort
}

if (!token) {
  console.error("ERROR: empty token from rails runner");
  process.exit(1);
}

fs.mkdirSync(path.dirname(outFile), { recursive: true });
if (/\.env(\.local)?$/.test(outFile) && fs.existsSync(outFile)) {
  const lines = fs.readFileSync(outFile, "utf8").split(/\r?\n/);
  let found = false;
  const out = lines.map((line) => {
    if (line.startsWith("GITLAB_TOKEN=")) {
      found = true;
      return `GITLAB_TOKEN=${token}`;
    }
    return line;
  });
  if (!found) out.push(`GITLAB_TOKEN=${token}`);
  fs.writeFileSync(outFile, out.join("\n") + "\n");
} else {
  fs.writeFileSync(outFile, `GITLAB_TOKEN=${token}\n`, { mode: 0o600 });
}

const suffix = token.slice(-4);
console.log(`OK: minted PAT name=${patName} → ${outFile} (suffix …${suffix})`);

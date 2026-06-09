import { test, expect } from "@playwright/test";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  STORAGE_STATE,
  resolveAuthEnv,
  readRootPasswordFromK8s,
  writeTokenLocal,
  upsertEnvLocalToken,
  tokenSuffix,
  HOMELAB_ROOT,
  type GitLabAuthEnv,
} from "./gitlab-auth-helpers";

const ARTIFACT_DIR = path.join(HOMELAB_ROOT, "test-results", "gitlab-auth");

function authEnvForProject(projectName: string, baseURL?: string): GitLabAuthEnv {
  const base = resolveAuthEnv();
  if (projectName === "gitlab-auth-nodeport") {
    const url = baseURL ?? `http://${base.nodeIp}:${process.env.GITLAB_NODEPORT ?? "30481"}`;
    return { ...base, baseUrl: url, signInUrl: `${url}/users/sign_in`, useNodeport: true };
  }
  if (baseURL) {
    return { ...base, baseUrl: baseURL, signInUrl: `${baseURL}/users/sign_in` };
  }
  return base;
}

test.describe("GitLab Playwright auth", () => {
  test("login as root and persist session (+ optional PAT via UI)", async ({ page, context }, testInfo) => {
    fs.mkdirSync(ARTIFACT_DIR, { recursive: true });
    const createPat = testInfo.project.name === "gitlab-auth-pat" || process.env.GITLAB_AUTH_CREATE_PAT === "1";
    const env = authEnvForProject(testInfo.project.name, testInfo.project.use.baseURL as string | undefined);

    const rootPassword = readRootPasswordFromK8s();
    expect(rootPassword.length, "root password from K8s secret").toBeGreaterThan(8);

    const response = await page.goto(env.signInUrl, {
      waitUntil: env.useNodeport ? "domcontentloaded" : "commit",
      timeout: 120_000,
    });
    expect(response?.status(), "sign_in HTTP status").toBeLessThan(500);

    const userField = page.getByTestId("username-field");
    const passField = page.getByTestId("password-field");
    await expect(userField, "username field").toBeVisible({ timeout: env.useNodeport ? 30_000 : 90_000 });
    await expect(passField, "password field").toBeVisible();

    await userField.fill("root");
    await passField.fill(rootPassword);

    const signInButton = page.locator('button[type="submit"], input[type="submit"], [data-testid="sign-in-button"]').first();
    await Promise.all([
      page.waitForURL((url) => !url.pathname.includes("/users/sign_in"), { timeout: 120_000 }),
      signInButton.click(),
    ]);

    await expect(page.locator("body")).not.toContainText("422: The change you requested was rejected");

    fs.mkdirSync(path.dirname(STORAGE_STATE), { recursive: true });
    await context.storageState({ path: STORAGE_STATE });
    fs.writeFileSync(
      path.join(ARTIFACT_DIR, "summary.json"),
      JSON.stringify(
        {
          baseUrl: env.baseUrl,
          host: env.host,
          useNodeport: env.useNodeport,
          storageState: STORAGE_STATE,
          loggedInUrl: page.url(),
        },
        null,
        2,
      ),
    );

    if (createPat) {
      const patName = process.env.PAT_NAME ?? "playwright-dev";
      const patPage = `${env.baseUrl.replace(/\/$/, "")}/-/user_settings/personal_access_tokens`;
      await page.goto(patPage, { waitUntil: "domcontentloaded", timeout: 120_000 });

      const nameInput = page.locator('input[name="personal_access_token[name]"], #personal_access_token_name').first();
      if (await nameInput.isVisible({ timeout: 15_000 }).catch(() => false)) {
        await nameInput.fill(patName);
        for (const scope of ["api", "read_api", "read_repository", "write_repository"]) {
          const box = page.locator(`input[type="checkbox"][value="${scope}"]`).first();
          if (await box.isVisible().catch(() => false)) await box.check();
        }
        await page.locator('button:has-text("Create"), input[value="Create"]').first().click();
        const tokenField = page.locator('[data-testid="new-personal-access-token-field"], #created-personal-access-token, input[readonly]').first();
        await expect(tokenField).toBeVisible({ timeout: 30_000 });
        const token = (await tokenField.inputValue()) || (await tokenField.textContent()) || "";
        expect(token.startsWith("glpat-"), "PAT prefix").toBeTruthy();
        const out = process.env.GITLAB_TOKEN_OUT;
        if (out?.includes(".env")) upsertEnvLocalToken(token, out);
        else writeTokenLocal(token, out ?? path.join(HOMELAB_ROOT, ".gitlab-token.local"));
        fs.writeFileSync(path.join(ARTIFACT_DIR, "pat-suffix.txt"), `suffix=…${tokenSuffix(token)}\n`);
      }
    }
  });
});

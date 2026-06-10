import { defineConfig, devices } from "@playwright/test";

const host = process.env.GITLAB_HOST ?? "gitlab.lilangverse.xyz";
const edgeIp = process.env.EDGE_IP ?? "192.168.10.33";
const edgePort = process.env.GITLAB_EDGE_PORT ?? "443";
const origin =
  edgePort === "443" ? `https://${host}` : `https://${host}:${edgePort}`;
const signInUrl = `${origin}/users/sign_in`;

export default defineConfig({
  testDir: "./scripts",
  testMatch: /edge-gitlab-render\.spec\.ts|gitlab-playwright-auth\.spec\.ts/,
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 180_000,
  expect: { timeout: 30_000 },
  reporter: [["list"], ["html", { open: "never", outputFolder: "test-results/playwright-report" }]],
  outputDir: "test-results/playwright-artifacts",
  use: {
    ...devices["Desktop Chrome"],
    channel: process.env.PLAYWRIGHT_CHANNEL ?? "chrome",
    ignoreHTTPSErrors: true,
    launchOptions: {
      args: [`--host-resolver-rules=MAP ${host} ${edgeIp}`],
    },
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  projects: [
    {
      name: "edge-gitlab-render",
      testMatch: "edge-gitlab-render.spec.ts",
      use: {
        baseURL: origin,
      },
    },
    {
      name: "gitlab-auth",
      testMatch: "gitlab-playwright-auth.spec.ts",
      use: {
        baseURL: origin,
      },
    },
    {
      name: "gitlab-auth-nodeport",
      testMatch: "gitlab-playwright-auth.spec.ts",
      use: {
        baseURL: `http://${process.env.GITLAB_NODE_IP ?? "192.168.10.32"}:${process.env.GITLAB_NODEPORT ?? "30481"}`,
      },
    },
    {
      name: "gitlab-auth-pat",
      testMatch: "gitlab-playwright-auth.spec.ts",
      use: {
        baseURL: origin,
      },
    },
  ],
});

export { signInUrl, host, edgeIp };

import { defineConfig, devices } from "@playwright/test";

const host = process.env.GITLAB_HOST ?? "gitlab.lilangverse.xyz";
const edgeIp = process.env.EDGE_IP ?? "192.168.10.33";
const signInUrl = `https://${host}/users/sign_in`;

export default defineConfig({
  testDir: "./scripts",
  testMatch: "edge-gitlab-render.spec.ts",
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
      use: {
        baseURL: `https://${host}`,
      },
    },
  ],
});

export { signInUrl, host, edgeIp };

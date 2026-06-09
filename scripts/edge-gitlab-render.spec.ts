import { test, expect, type Page, type Response } from "@playwright/test";
import * as fs from "node:fs";
import * as path from "node:path";

const HOST = process.env.GITLAB_HOST ?? "gitlab.lilangverse.xyz";
const SIGN_IN = `https://${HOST}/users/sign_in`;
const ARTIFACT_DIR = path.join(__dirname, "..", "test-results", "edge-gitlab-render");

const BENIGN_CONSOLE = [
  /favicon/i,
  /deprecated/i,
  /third.party cookie/i,
  /Content Security Policy/i,
  /Failed to load resource.*favicon/i,
];

type AssetRecord = {
  url: string;
  path: string;
  status: number;
  contentLength: number | null;
  received: number;
  kind: "css" | "js";
};

function isBenignConsole(text: string): boolean {
  return BENIGN_CONSOLE.some((re) => re.test(text));
}

function parseContentLength(headers: { [key: string]: string }): number | null {
  const raw = headers["content-length"];
  if (!raw) return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
}

function assetPath(url: string): string {
  try {
    return new URL(url).pathname;
  } catch {
    return url;
  }
}

function parseRgb(color: string): [number, number, number] | null {
  const m = color.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
  if (!m) return null;
  return [Number(m[1]), Number(m[2]), Number(m[3])];
}

function isGitLabBrandColor(color: string): boolean {
  const rgb = parseRgb(color);
  if (!rgb) return false;
  const [r, g, b] = rgb;
  const isOrange = r >= 230 && r <= 255 && g >= 80 && g <= 140 && b >= 20 && b <= 80;
  const isBlue = r >= 20 && r <= 60 && g >= 100 && g <= 140 && b >= 180 && b <= 230;
  return isOrange || isBlue;
}

async function collectNetworkAssets(page: Page): Promise<Map<string, AssetRecord>> {
  const byPath = new Map<string, AssetRecord>();
  page.on("response", async (response: Response) => {
    const url = response.url();
    if (!url.includes("/assets/")) return;
    const kind = url.endsWith(".css") ? "css" : url.endsWith(".js") ? "js" : null;
    if (!kind) return;
    const headers = response.headers();
    const body = await response.body().catch(() => Buffer.alloc(0));
    const p = assetPath(url);
    byPath.set(p, {
      url,
      path: p,
      status: response.status(),
      contentLength: parseContentLength(headers),
      received: body.length,
      kind,
    });
  });
  return byPath;
}

async function discoverAssetPaths(page: Page): Promise<{ css: string[]; js: string[] }> {
  return page.evaluate(() => {
    const toPath = (href: string) => {
      try {
        return new URL(href, window.location.origin).pathname;
      } catch {
        return href;
      }
    };
    const css = Array.from(document.querySelectorAll('link[rel="stylesheet"][href]'))
      .map((el) => toPath((el as HTMLLinkElement).href))
      .filter((p) => p.includes("/assets/") && p.endsWith(".css"));
    const js = Array.from(document.querySelectorAll("script[src]"))
      .map((el) => toPath((el as HTMLScriptElement).src))
      .filter((p) => p.includes("/assets/") && p.endsWith(".js"));
    return { css, js };
  });
}

test.describe("GitLab edge render — sign_in", () => {
  test("loads styled sign-in with all CSS/JS assets intact", async ({ page }) => {
    fs.mkdirSync(ARTIFACT_DIR, { recursive: true });

    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error" && !isBenignConsole(msg.text())) {
        consoleErrors.push(msg.text());
      }
    });
    page.on("pageerror", (err) => {
      if (!isBenignConsole(err.message)) {
        consoleErrors.push(err.message);
      }
    });

    const networkByPath = await collectNetworkAssets(page);

    const response = await page.goto(SIGN_IN, { waitUntil: "networkidle", timeout: 120_000 });
    expect(response, "sign_in navigation response").toBeTruthy();
    expect([200, 302]).toContain(response!.status());

    const { css: cssPaths, js: jsPaths } = await discoverAssetPaths(page);
    expect(cssPaths.length, "stylesheet link tags in HTML").toBeGreaterThanOrEqual(4);
    expect(jsPaths.length, "script src tags in HTML").toBeGreaterThanOrEqual(4);

    const allPaths = [...cssPaths, ...jsPaths];
    const missing: string[] = [];
    const truncated: string[] = [];
    const failed: string[] = [];

    for (const p of allPaths) {
      const rec = networkByPath.get(p);
      if (!rec) {
        missing.push(p);
        continue;
      }
      if (rec.status !== 200) failed.push(`${p}: status=${rec.status}`);
      if (rec.received <= 0) failed.push(`${p}: zero body`);
      if (rec.contentLength !== null && rec.received !== rec.contentLength) {
        truncated.push(`${p}: clen=${rec.contentLength} received=${rec.received}`);
      }
      const body = await page.evaluate(async (path) => {
        const r = await fetch(path);
        const buf = await r.arrayBuffer();
        return buf.byteLength > 0 ? new Uint8Array(buf)[0] : 0;
      }, p);
      if (body === 0x3c) failed.push(`${p}: body is HTML error page`);
    }

    expect(missing, "all HTML assets fetched by browser").toEqual([]);
    expect(truncated, "no truncated asset bodies").toEqual([]);
    expect(failed, "all assets HTTP 200 with valid body").toEqual([]);

    const branding = page.locator(
      'img[alt*="GitLab"], svg[data-testid="tanuki-logo"], .tanuki-logo, [data-testid="gitlab-logo"], .gl-logo svg',
    );
    await expect(branding.first(), "GitLab logo/branding visible").toBeVisible({ timeout: 15_000 });

    const signInForm = page.locator('form[action*="sign_in"], #login-form, [data-testid="sign-in-form"]');
    await expect(signInForm.first(), "sign-in form in DOM").toBeVisible();

    const styles = await page.evaluate(() => {
      const body = getComputedStyle(document.body);
      const btn = document.querySelector(
        'button[type="submit"], input[type="submit"], [data-testid="sign-in-button"]',
      );
      const btnStyle = btn ? getComputedStyle(btn) : null;
      const sheetCount = document.styleSheets.length;
      let appliedRules = 0;
      for (const sheet of Array.from(document.styleSheets)) {
        try {
          if (sheet.cssRules && sheet.cssRules.length > 0) appliedRules += sheet.cssRules.length;
        } catch {
          // cross-origin sheet
        }
      }
      return {
        bodyBg: body.backgroundColor,
        bodyFont: body.fontFamily,
        btnBg: btnStyle?.backgroundColor ?? "",
        btnRadius: btnStyle?.borderRadius ?? "",
        sheetCount,
        appliedRules,
      };
    });

    expect(styles.sheetCount, "stylesheets attached to document").toBeGreaterThan(0);
    expect(styles.appliedRules, "CSS rules applied (not unstyled HTML)").toBeGreaterThan(10);
    expect(styles.bodyFont.toLowerCase(), "body font not browser default serif").not.toContain("times");
    expect(
      isGitLabBrandColor(styles.btnBg),
      `Sign in button has GitLab brand color (got ${styles.btnBg})`,
    ).toBeTruthy();

    const cssAssets = [...networkByPath.values()].filter((a) => a.kind === "css");
    const jsAssets = [...networkByPath.values()].filter((a) => a.kind === "js");

    expect(consoleErrors, "no unexpected console errors").toEqual([]);

    const screenshotPath = path.join(ARTIFACT_DIR, "gitlab-sign-in.png");
    await page.screenshot({ path: screenshotPath, fullPage: true });

    const summary = {
      host: HOST,
      signInUrl: SIGN_IN,
      htmlCssCount: cssPaths.length,
      htmlJsCount: jsPaths.length,
      networkCssCount: cssAssets.length,
      networkJsCount: jsAssets.length,
      consoleErrors,
      missing,
      truncated,
      failed,
      screenshot: screenshotPath,
      styles,
    };
    fs.writeFileSync(path.join(ARTIFACT_DIR, "summary.json"), JSON.stringify(summary, null, 2));
  });
});

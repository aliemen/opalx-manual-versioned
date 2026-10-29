import { expect, test } from "@playwright/test";

// The test server publishes only the development build. Routing serves the same
// build as a frozen 1.0 release and supplies the manifests that
// scripts/assemble_release_sites.rb writes at deploy time.
const versions = [
  { id: "dev", label: "Development (main)", path: "" },
  { id: "1.0", label: "OPALX 1.0.0", path: "1.0/", tag: "OPALX-1.0.0" }
];
const manifest = (current) => ({ current, latest: "1.0", versions });

const serveRelease = async (page, { missing = [] } = {}) => {
  await page.route((url) => url.pathname.endsWith("/versions.json") || url.pathname.startsWith("/1.0/"), async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname === "/versions.json") return route.fulfill({ json: manifest("dev") });
    if (url.pathname === "/1.0/versions.json") return route.fulfill({ json: manifest("1.0") });
    if (missing.includes(url.pathname)) return route.fulfill({ status: 404, body: "missing" });
    url.pathname = url.pathname.slice("/1.0".length);
    return route.continue({ url: url.href });
  });
};

test("shows no release navigation without a manifest", async ({ page }) => {
  const manifestResponse = page.waitForResponse((response) => response.url().endsWith("/versions.json"));
  await page.goto("/user-guide/beam.html");
  expect((await manifestResponse).status()).toBe(404);
  await expect(page.locator("h1.title")).toBeVisible();
  await expect(page.getByLabel("Manual release")).toHaveCount(0);
  await expect(page.locator(".opalx-release-banner")).toHaveCount(0);
});

test("switches from the development manual to the same page of a release", async ({ page }) => {
  await serveRelease(page);
  await page.goto("/user-guide/beam.html");

  const select = page.getByLabel("Manual release");
  await expect(select).toHaveValue("dev");
  await expect(page.locator("#quarto-sidebar .opalx-release-selector")).toBeAttached();
  const banner = page.locator(".opalx-release-banner");
  await expect(banner).toContainText("development manual");
  await expect(banner.getByRole("link", { name: "OPALX 1.0.0" }))
    .toHaveAttribute("href", /\/1\.0\/user-guide\/beam\.html$/);

  await select.selectOption("1.0");
  await expect(page).toHaveURL(/\/1\.0\/user-guide\/beam\.html$/);
  await expect(page.getByLabel("Manual release")).toHaveValue("1.0");
  await expect(page.locator("html")).toHaveAttribute("data-opalx-manual-release", "1.0");
  await expect(page.locator(".opalx-release-banner--frozen")).toContainText("This is the manual for OPALX 1.0.0.");
});

test("returns from a release to the same development page and anchor", async ({ page }) => {
  await serveRelease(page);
  await page.goto("/1.0/user-guide/beam-distributions.html#gauss");

  const banner = page.locator(".opalx-release-banner--frozen");
  await expect(banner).not.toContainText("The latest release is");
  await banner.getByRole("link", { name: "development manual" }).click();
  await expect(page).toHaveURL(/127\.0\.0\.1:4173\/user-guide\/beam-distributions\.html#gauss$/);
  await expect(page.getByLabel("Manual release")).toHaveValue("dev");
});

test("falls back to the release start page when a page does not exist there", async ({ page }) => {
  await serveRelease(page, { missing: ["/1.0/user-guide/beam.html"] });
  await page.goto("/user-guide/beam.html");

  await page.getByLabel("Manual release").selectOption("1.0");
  await expect(page).toHaveURL(/\/1\.0\/$/);
  await expect(page.getByLabel("Manual release")).toHaveValue("1.0");
});

test("keeps release navigation usable at mobile width", async ({ page }) => {
  await serveRelease(page);
  await page.setViewportSize({ width: 390, height: 900 });
  await page.goto("/1.0/physics/beam-beam/index.html");
  const banner = page.locator(".opalx-release-banner--frozen");
  await expect(banner).toBeVisible();
  const box = await banner.boundingBox();
  expect(box.x + box.width).toBeLessThanOrEqual(390);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1);
  expect(overflow).toBe(false);
});

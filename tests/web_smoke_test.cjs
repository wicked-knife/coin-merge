// Run against Wrangler Pages dev or the public HTTPS URL. Each profile uses a
// fresh browser context and checks the real browser save after UI interactions.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const url = process.argv[2] || 'http://127.0.0.1:8788/';
const output = path.resolve(process.argv[3] || 'build/web-checks');
fs.mkdirSync(output, { recursive: true });
fs.rmSync(path.join(output, 'verification.json'), { force: true });

async function savedFile(page, filename) {
  return page.evaluate(async (name) => {
    const info = (await indexedDB.databases()).find((item) => item.name === '/userfs');
    if (!info) return null;
    const db = await new Promise((resolve, reject) => {
      const open = indexedDB.open(info.name);
      open.onsuccess = () => resolve(open.result);
      open.onerror = () => reject(open.error);
    });
    let text = null;
    await new Promise((resolve, reject) => {
      const tx = db.transaction('FILE_DATA', 'readonly');
      const cursor = tx.objectStore('FILE_DATA').openCursor();
      cursor.onsuccess = () => {
        const item = cursor.result;
        if (!item) return;
        if (String(item.key).endsWith('/' + name) && item.value.contents) {
          text = new TextDecoder().decode(item.value.contents);
        }
        item.continue();
      };
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error);
    });
    db.close();
    return text;
  }, filename);
}

async function waitSave(page, filename, predicate, label) {
  const deadline = Date.now() + 15000;
  let value = null;
  while (Date.now() < deadline) {
    const text = await savedFile(page, filename);
    value = text ? JSON.parse(text) : null;
    if (value && predicate(value)) {
      // Saves happen before the final arrival/merge animation releases input.
      await page.waitForTimeout(1200);
      return value;
    }
    await page.waitForTimeout(200);
  }
  throw new Error(`${label}: timed out; last save: ${JSON.stringify(value)}`);
}

async function runProfile(browser, name, options) {
  const context = await browser.newContext(options);
  const page = await context.newPage();
  page.setDefaultTimeout(60000);
  const errors = [];
  const assets = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  page.on('requestfailed', (request) => errors.push(`${request.url()}: ${request.failure().errorText}`));
  page.on('response', (response) => {
    if (/\.(wasm|pck)$/.test(response.url())) assets.push({ url: response.url(), status: response.status(), headers: response.headers() });
  });
  const capture = (label) => page.screenshot({ path: path.join(output, `${name}-${label}.png`) });
  const click = async (x, y, anchor = 'center') => {
    const box = await page.locator('canvas').boundingBox();
    const scale = box.width / 750;
    const top = anchor === 'bottom' ? box.height - 1334 * scale : (anchor === 'top' ? 0 : (box.height - 1334 * scale) / 2);
    const at = { x: box.x + x * scale, y: box.y + top + y * scale };
    if (options.hasTouch) await page.touchscreen.tap(at.x, at.y);
    else await page.mouse.click(at.x, at.y);
    await page.waitForTimeout(450);
  };
  const load = async () => {
    await page.goto(url, { waitUntil: 'load' });
    await page.waitForFunction(() => !document.getElementById('status') || !document.getElementById('retry').hidden);
    assert.equal(await page.locator('#status').count(), 0, 'game startup succeeds');
    await page.waitForTimeout(1200);
  };
  try {
    await load();
    assert.equal(await page.title(), 'Coin Merge');
    const canvasSize = await page.locator('canvas').boundingBox();
    assert(canvasSize.width <= 563 && canvasSize.height <= options.viewport.height, 'portrait canvas fits the viewport');
    await capture('menu');
    await click(70, 94, 'top');
    await page.keyboard.press('Tab');
    await page.keyboard.press('Space');
    await page.waitForTimeout(1800);
    assert.match(await savedFile(page, 'settings.cfg') || '', /\[audio\][\s\S]*enabled=false/, 'settings modal opens and sound preference persists');
    await capture('settings');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    await click(375, 1112, 'bottom');
    await waitSave(page, 'normal_game.json', (save) => save.guide_step === 0, 'normal tutorial loads');
    await click(168, 939);
    await click(444, 939);
    let normal = await waitSave(page, 'normal_game.json', (save) => save.guide_step === 3, 'first automatic merge');
    assert.equal(normal.cells[2].coins.length, 2);
    assert(normal.cells[2].coins.every((coin) => coin.level === 2), '10 matching coins become two coins of the next level');
    await click(375, 1234);
    await waitSave(page, 'normal_game.json', (save) => save.guide_step === 4, 'tutorial deal');
    await click(168, 939);
    await click(306, 939);
    await waitSave(page, 'normal_game.json', (save) => save.guide_step === 6, 'second tutorial move');
    await click(444, 939);
    await click(306, 939);
    await waitSave(page, 'normal_game.json', (save) => save.guide_step === 9, 'second automatic merge');
    await click(375, 230);
    await click(375, 1234);
    normal = await waitSave(page, 'normal_game.json', (save) => save.guide_step === -1, 'tutorial completes');
    await capture('normal');
    await click(77, 94);
    await capture('normal-settings');
    await page.setViewportSize({ width: options.viewport.width, height: options.viewport.height - 184 });
    await page.waitForTimeout(400);
    await capture('normal-settings-compact');
    await page.setViewportSize(options.viewport);
    await page.waitForTimeout(400);
    await page.keyboard.press('Escape');

    // Reload the page, resume the actual persisted board, then deal again. A
    // fresh tutorial would reject this action, so a changed save proves resume.
    await load();
    await click(375, 1112, 'bottom');
    await page.waitForTimeout(500);
    await click(375, 1234);
    await waitSave(page, 'normal_game.json', (save) => save.guide_step === -1 && JSON.stringify(save.cells) !== JSON.stringify(normal.cells), 'progress survives refresh');
    // Start the challenge from a fresh menu while retaining the same save.
    await load();
    await click(375, 938, 'bottom');
    await capture('challenge-menu');
    await click(158, 329);
    await page.waitForTimeout(500);
    await capture('challenge-tutorial');
    const xs = [251, 375, 499];
    for (const [source, target] of [[0, 2], [1, 2], [1, 0], [2, 1]]) {
      await click(xs[source], 696);
      await click(xs[target], 696);
      await page.waitForTimeout(600);
    }
    const challenge = await waitSave(page, 'challenge_game.json', (save) => save.cells.length === 30 && !save.tutorial, 'challenge tutorial enters the first level');
    assert.equal(challenge.level, 1);
    await capture('challenge');
    await click(77, 94);
    await capture('challenge-settings');
    await page.keyboard.press('Escape');
    await page.setViewportSize({ width: options.viewport.width, height: options.viewport.height - 80 });
    await page.waitForTimeout(400);
    await capture('resized');
    assert.equal(await page.locator('#status').count(), 0);

    assert(assets.length >= 4, 'engine and pack load on both page visits');
    for (const asset of assets) {
      assert.equal(asset.status, 200);
      assert.equal(asset.headers['content-encoding'], 'gzip');
      assert.match(asset.headers['content-type'], asset.url.endsWith('.wasm') ? /^application\/wasm/ : /^application\/octet-stream/);
    }
    assert.deepEqual(errors, [], 'no browser or game runtime errors');
    for (const suffix of ['errors.json', 'failure.png']) {
      fs.rmSync(path.join(output, `${name}-${suffix}`), { force: true });
    }
    console.log(`WEB ${name}: passed (normal tutorial, merge, deal, save/resume, settings, challenge tutorial, resize)`);
    return { name, passed: true, assets, errors };
  } catch (error) {
    await capture('failure').catch(() => {});
    fs.writeFileSync(path.join(output, `${name}-errors.json`), JSON.stringify({ error: String(error), errors, assets }, null, 2));
    throw error;
  } finally {
    await context.close();
  }
}

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH || undefined, args: ['--enable-unsafe-swiftshader'] });
  const results = [];
  try {
    results.push(await runProfile(browser, 'desktop', { viewport: { width: 1280, height: 900 } }));
    results.push(await runProfile(browser, 'mobile-touch', { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true }));
    fs.writeFileSync(path.join(output, 'verification.json'), JSON.stringify({ url, checkedAt: new Date().toISOString(), results }, null, 2) + '\n');
  } finally {
    await browser.close();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });

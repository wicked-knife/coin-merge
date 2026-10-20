// Executes the actual bridge string from challenge_platform.gd, without a browser
// or a real ad SDK. These mocks do not establish YouTube host compatibility.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../scripts/challenge_platform.gd'), 'utf8');
const match = source.match(/const INTERSTITIAL_SCRIPT := """([\s\S]*?)"""/);
assert.ok(match, 'the production JavaScript string must exist');
const script = match[1];
assert.equal((script.match(/%s/g) || []).length, 1);

function harness(sdk, withWindow = true) {
  const warnings = [];
  const globals = { console: { warn: (...args) => warnings.push(args) } };
  if (withWindow) globals.window = sdk === undefined ? {} : { ytgame: sdk };
  const context = vm.createContext(globals);
  return {
    warnings,
    request(placement = 'war-level-complete') {
      return vm.runInContext(script.replace('%s', () => JSON.stringify(placement)), context, { timeout: 1000 });
    },
  };
}

function readySdk(requestInterstitialAd, logError = () => {}) {
  return { IN_PLAYABLES_ENV: true, ads: { requestInterstitialAd }, health: { logError } };
}

const settled = () => new Promise(resolve => setImmediate(resolve));

test('missing window or SDK safely reports unavailable', () => {
  assert.equal(harness(undefined, false).request(), false);
  assert.equal(harness().request(), false);
});

test('outside Playables or without the actual SDK method reports unavailable', () => {
  let calls = 0;
  const sdk = readySdk(() => { calls++; });
  sdk.IN_PLAYABLES_ENV = false;
  assert.equal(harness(sdk).request(), false);
  for (const sdk of [
    { IN_PLAYABLES_ENV: true },
    { IN_PLAYABLES_ENV: true, ads: {} },
    { IN_PLAYABLES_ENV: true, ads: { requestInterstitialAd: true } },
  ]) assert.equal(harness(sdk).request(), false);
  assert.equal(calls, 0);
});

test('success calls the SDK with no placement argument and preserves its receiver', async () => {
  const calls = [];
  const errors = [];
  const sdk = readySdk(function (...args) { calls.push({ receiver: this, args }); return Promise.resolve(); }, error => errors.push(error));
  const host = harness(sdk);
  assert.equal(host.request(), true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].receiver, sdk.ads);
  assert.deepEqual(calls[0].args, []);
  await settled();
  assert.deepEqual(errors, []);
  assert.deepEqual(host.warnings, []);
});

test('synchronous SDK errors are logged and do not block future requests', async () => {
  let calls = 0;
  const errors = [];
  const host = harness(readySdk(() => { calls++; throw new Error('sync failure'); }, error => errors.push(error)));
  assert.equal(host.request(), true);
  await settled();
  assert.deepEqual(errors, ['[InterstitialAd] war-level-complete failed: sync failure']);
  assert.equal(host.warnings.length, 1);
  assert.equal(host.request(), true);
  await settled();
  assert.equal(calls, 2);
});

test('rejected SDK promises are logged and do not block future requests', async () => {
  let calls = 0;
  const errors = [];
  const host = harness(readySdk(() => { calls++; return Promise.reject(new Error('rejected')); }, error => errors.push(error)));
  assert.equal(host.request(), true);
  await settled();
  assert.deepEqual(errors, ['[InterstitialAd] war-level-complete failed: rejected']);
  assert.equal(host.request(), true);
  await settled();
  assert.equal(calls, 2);
});

test('overlapping requests share one in-flight operation and unlock after settlement', async () => {
  let resolve;
  let calls = 0;
  const host = harness(readySdk(() => { calls++; return new Promise(done => { resolve = done; }); }));
  assert.equal(host.request(), true);
  assert.equal(host.request('another-placement'), true);
  assert.equal(calls, 1);
  await settled();
  assert.equal(host.request(), true);
  assert.equal(calls, 1);
  resolve();
  await settled();
  assert.equal(host.request(), true);
  assert.equal(calls, 2);
  resolve();
  await settled();
});

test('a successful request permits a later request', async () => {
  let calls = 0;
  const host = harness(readySdk(() => { calls++; return Promise.resolve(); }));
  assert.equal(host.request(), true);
  await settled();
  assert.equal(host.request(), true);
  await settled();
  assert.equal(calls, 2);
});

test('throwing health logger is swallowed and placement remains data', async () => {
  const placement = '"; window.injected = true; //\n$`%s';
  const host = harness(readySdk(() => Promise.reject(null), () => { throw new Error('logger failure'); }));
  assert.equal(host.request(placement), true);
  await settled();
  assert.equal(host.warnings.length, 1);
  assert.equal(host.warnings[0][1], '[InterstitialAd] ' + placement + ' failed: unknown');
  assert.equal(host.request(), true);
  await settled();
});

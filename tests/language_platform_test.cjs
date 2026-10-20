// Exercise the production bridge with SDK doubles; this is not a live host test.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const source = fs.readFileSync(path.join(__dirname, '../scripts/language_platform.gd'), 'utf8');
const script = name => source.match(new RegExp(`const ${name} := """([\\s\\S]*?)"""`))[1];
const request = script('LANGUAGE_SCRIPT');
const result = script('RESULT_SCRIPT');
const settled = () => new Promise(resolve => setImmediate(resolve));
function host(sdk, withWindow = true) {
  const context = vm.createContext(withWindow ? { window: { ytgame: sdk } } : {});
  return {
    begin: () => vm.runInContext(request, context, { timeout: 1000 }),
    result: () => JSON.parse(vm.runInContext(result, context, { timeout: 1000 })),
  };
}
const sdk = getLanguage => ({ IN_PLAYABLES_ENV: true, system: { getLanguage } });
test('missing host, standalone and absent methods report unavailable', () => {
  for (const candidate of [undefined, {}, { IN_PLAYABLES_ENV: false },
    { IN_PLAYABLES_ENV: true }, { IN_PLAYABLES_ENV: true, system: {} },
    { IN_PLAYABLES_ENV: true, system: { getLanguage: true } }]) {
    assert.equal(host(candidate).begin(), false);
  }
  assert.equal(host(undefined, false).begin(), false);
});
test('host method retains receiver, has no arguments and handles promises', async () => {
  let calls = 0;
  const candidate = sdk(function (...args) {
    assert.equal(this, candidate.system);
    assert.deepEqual(args, []);
    calls++;
    return Promise.resolve('zh-Hant-TW');
  });
  const h = host(candidate);
  assert.equal(h.begin(), true);
  await settled();
  assert.equal(calls, 1);
  assert.deepEqual(h.result(), { done: true, language: 'zh-Hant-TW' });
});
test('synchronous return values and non-string results are safe', async () => {
  for (const value of ['fr-CA', undefined, null, {}, 7]) {
    const h = host(sdk(() => value));
    assert.equal(h.begin(), true);
    await settled();
    assert.deepEqual(h.result(), { done: true, language: typeof value === 'string' ? value : '' });
  }
});
test('sync errors and rejected promises settle with English fallback input', async () => {
  for (const get of [() => { throw Error('sync'); }, () => Promise.reject(Error('async'))]) {
    const h = host(sdk(get));
    assert.equal(h.begin(), true);
    await settled();
    assert.deepEqual(h.result(), { done: true, language: '' });
  }
});
test('pending and delayed SDK results expose state without blocking', async () => {
  let resolve;
  const h = host(sdk(() => new Promise(done => { resolve = done; })));
  assert.equal(h.begin(), true);
  assert.deepEqual(h.result(), { done: false, language: '' });
  resolve('ja');
  await settled();
  assert.deepEqual(h.result(), { done: true, language: 'ja' });
});
test('host content is returned as data', async () => {
  const value = '\"; window.injected=true; //\\n$`';
  const h = host(sdk(() => value));
  assert.equal(h.begin(), true);
  await settled();
  assert.deepEqual(h.result(), { done: true, language: value });
});

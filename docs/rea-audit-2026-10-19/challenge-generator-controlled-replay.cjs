/*
 * Offline controlled replay. No browser or game runtime is started.
 * Run from any directory: node path/to/challenge-generator-controlled-replay.cjs
 * Only stdout is written. The original module/configuration files are read only.
 *
 * The shipped Create.js is evaluated in an isolated vm with dependency stubs.
 * port() is a MANUAL JavaScript translation of challenge_game.gd:_generate and
 * its helpers, NOT execution/transpilation of GDScript. Both implementations use
 * the injected xorshift32 stream below instead of their production RNG engines.
 * This compares generation logic under controlled randomness; it does not prove
 * Godot/Cocos runtime parity, the production RNG distribution, or solvability.
 */
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const crypto = require('node:crypto');
const os = require('node:os');

const root = path.resolve(__dirname, '../..');
const reference = path.join(root, 'docs/rea-reference');
const sourcePath = path.join(reference, 'source/modules/Create.js');
const loadConfig = name => JSON.parse(fs.readFileSync(path.join(reference, 'configs', name + '.json'), 'utf8'));
const cfg = {
  Excelchallenge_area1: loadConfig('Excelchallenge_area1'),
  Excelchallenge_deal1: loadConfig('Excelchallenge_deal1'),
  Excelarea_color1: loadConfig('Excelarea_color1'),
  ExcelKeyvalue: loadConfig('Excelkeyvalue')[0],
};
// Establish that the translation's raw table inputs also match the embedded
// Godot tables. This avoids relying only on the expanded documentation JSON.
const localDataSource = fs.readFileSync(path.join(root, 'scripts/challenge_data.gd'), 'utf8');
const localLevels = localDataSource.split(/\r?\n/).filter(line => line.trimStart().startsWith('{'))
  .map(line => JSON.parse(line.trim().replace(/,$/, '')));
const localWeights = JSON.parse(localDataSource.split('const GROUP_WEIGHTS := ')[1]);
const expectedWeights = Array.from({ length: 6 }, (_, index) => cfg.Excelchallenge_deal1
  .map(entry => entry['challenge' + (index + 1)].split('#').map(Number)));
const mismatchedLevelTables = [];
for (let index = 0; index < cfg.Excelchallenge_area1.length; index++) {
  const area = cfg.Excelchallenge_area1[index];
  const expected = { columns: area.row, rows: area.column, unlock: area.unlockNumeral,
    hidden: area.greyNum.split('#').map(Number),
    targets: cfg.Excelarea_color1.slice(0, area.row * area.column).map(entry => Number(entry['level' + (index + 1)])) };
  if (JSON.stringify(localLevels[index]) !== JSON.stringify(expected)) mismatchedLevelTables.push(index + 1);
}
const embeddedTableCheck = { localLevelCount: localLevels.length,
  originalLevelCount: cfg.Excelchallenge_area1.length, mismatchedLevelTables,
  groupWeightsEqual: JSON.stringify(localWeights) === JSON.stringify(expectedWeights) };
if (mismatchedLevelTables.length || !embeddedTableCheck.groupWeightsEqual || localLevels.length !== 100) {
  throw new Error('Embedded challenge tables do not match the captured raw configurations');
}

// xorshift32; seed is a nonzero unsigned integer. Exactly one draw per
// randomInt invocation, including a degenerate interval, just like MathTools.
let state = 1;
let draws = 0;
const random = () => {
  draws++;
  state ^= state << 13;
  state ^= state >>> 17;
  state ^= state << 5;
  return (state >>> 0) / 4294967296;
};
const math = {
  randomInt: (low, high) => Math.floor(random() * (high - low + 1) + low),
  shuffle: values => {
    for (let index = 0, length = values.length; index < length - 1; index++) {
      const other = Math.floor(random() * (length - index));
      [values[other], values[length - index - 1]] = [values[length - index - 1], values[other]];
    }
    return values;
  },
};

const probe = { originalHiddenFallback: 0, originalConsoleLogs: 0, originalConsoleErrors: 0, pureRepairShortages: 0 };
let source = fs.readFileSync(sourcePath, 'utf8').trim().replace(/,$/, '');
const marker = 'var B=!1';
if (source.split(marker).length !== 2) throw new Error('Expected exactly one hidden fallback marker');
// Instrumentation is in memory only. It inserts one counter before the original
// fallback body and does not consume RNG values or change the algorithm.
source = source.replace(marker, 'probe.originalHiddenFallback++;var B=!1');
const context = {
  cc: { _RF: { push() {}, pop() {} } },
  console: {
    log(...values) {
      probe.originalConsoleLogs++;
      if (values[0] === 'moreThreeIdxs.size..error:') probe.pureRepairShortages++;
    },
    error() { probe.originalConsoleErrors++; },
  },
  probe,
};
const factory = vm.runInNewContext('({' + source + '})', context).Create[0];
const exportsObject = {};
factory(name => {
  if (name.includes('MathTools')) return { MathTools: math };
  if (name.includes('ConfigCollect')) return { ConfigCollect: cfg };
  if (name.includes('GameConst')) return { CoinNeedData: class {} };
  throw new Error('Unexpected dependency: ' + name);
}, {}, exportsObject);

let localDefensiveFillFallback = 0;
function port(level, sourceOrder) {
  const area = cfg.Excelchallenge_area1[level - 1];
  const result = [];
  const stock = new Map();
  const positions = [];
  for (let index = 0; index < area.row * area.column; index++) {
    const target = Number(cfg.Excelarea_color1[index]['level' + level]);
    if (target > 0) {
      stock.set(target, (stock.get(target) || 0) + 10);
      positions.push(index);
    }
    result.push([]);
  }
  const groupSize = () => {
    const table = cfg.Excelchallenge_deal1.map(entry => entry['challenge' + Math.min(level, 6)].split('#').map(Number));
    let roll = math.randomInt(1, table.reduce((total, entry) => total + entry[1], 0));
    for (const [count, weight] of table) {
      roll -= weight;
      if (roll <= 0) return count;
    }
    return 1;
  };
  const chooseColor = (minimum = 1, exceptColor = 0) => {
    let total = 0;
    for (const [color, count] of stock) if (color !== exceptColor && count >= minimum) total += count;
    if (total <= 0) return 0;
    let roll = math.randomInt(1, total);
    for (const [color, count] of stock) {
      if (color !== exceptColor && count >= minimum) {
        roll -= count;
        if (roll <= 0) return color;
      }
    }
    return 0;
  };
  const appendStock = (stack, color, count, hidden = false) => {
    count = Math.min(count, stock.get(color) || 0);
    for (let index = 0; index < count; index++) stack.push({ num: color, isUn: hidden });
    stock.set(color, stock.get(color) - count);
  };

  const bounds = area.greyNum.split('#').map(Number);
  let hiddenCount;
  // This is the only intentional change between the two compared port modes:
  // source-order: hidden count draw -> Fisher-Yates shuffle -> coin draws.
  // current-order: Fisher-Yates shuffle -> hidden count draw -> coin draws.
  if (sourceOrder) {
    hiddenCount = math.randomInt(...bounds);
    math.shuffle(positions);
  } else {
    math.shuffle(positions);
    hiddenCount = math.randomInt(...bounds);
  }
  const hiddenPositions = new Set();
  for (const index of positions.slice(0, hiddenCount)) {
    const color = chooseColor(3);
    if (color === 0) break;
    appendStock(result[index], color, 3, true);
    hiddenPositions.add(index);
    let count = groupSize();
    let other = chooseColor(count, color);
    if (other === 0) {
      other = chooseColor(1, color);
      count = Math.min(7, stock.get(other) || 0);
    }
    if (other > 0) appendStock(result[index], other, count);
  }
  const pure = [];
  const mixed = [];
  for (let index = 0; index < result.length; index++) {
    const stack = result[index];
    if (!positions.includes(index)) continue;
    for (let attempt = 0; attempt < 50; attempt++) {
      if (stack.length >= 10) break;
      const color = chooseColor();
      if (color === 0) break;
      appendStock(stack, color, Math.min(groupSize(), 10 - stack.length));
    }
    while (stack.length < 10) {
      localDefensiveFillFallback++;
      const color = chooseColor();
      if (color === 0) break;
      appendStock(stack, color, 10 - stack.length);
    }
    const colors = new Set(stack.map(item => item.num));
    if (!hiddenPositions.has(index)) {
      if (colors.size === 1) pure.push(index);
      else if (colors.size >= 3) mixed.push(index);
    }
  }
  for (let pair = 0; pair < Math.min(pure.length, mixed.length); pair++) {
    const from = result[pure[pair]];
    const to = result[mixed[pair]];
    let other = 0;
    for (const item of to) {
      if (item.num !== from[0].num) {
        other = item.num;
        break;
      }
    }
    for (let index = 0; index < Math.min(from.length, to.length); index++) {
      if (to[index].num === other) [from[index].num, to[index].num] = [other, from[index].num];
    }
  }
  return result;
}

let tests = 0;
let equalAligned = 0;
let equalCurrent = 0;
let invalidOriginal = 0;
let maximumOriginalRandomDraws = 0;
let minimumFallbackInventoryMargin = Infinity;
let firstCurrentOrderDifference = null;
const normalize = stack => stack.map(item => [item.num, !!item.isUn]);
for (let level = 1; level <= 100; level++) {
  const area = cfg.Excelchallenge_area1[level - 1];
  const inventory = new Map();
  for (let index = 0; index < area.row * area.column; index++) {
    const color = Number(cfg.Excelarea_color1[index]['level' + level]);
    if (color > 0) inventory.set(color, (inventory.get(color) || 0) + 10);
  }
  // Every earlier hidden stack spends at most 3+5 coins. After selecting the
  // current three hidden coins, if no different color could satisfy G<=5, all
  // other colors would have <=4 each. The positive margin below disproves that
  // condition for every shipped level, even using the initial largest stock as
  // an upper bound for the selected color. Thus the hidden fallback is not
  // reachable for this configuration set under valid generation.
  const total = [...inventory.values()].reduce((sum, count) => sum + count, 0);
  const maximumColorStock = Math.max(...inventory.values());
  const maximumHidden = Number(area.greyNum.split('#')[1]);
  minimumFallbackInventoryMargin = Math.min(minimumFallbackInventoryMargin,
    total - (maximumHidden - 1) * 8 - 3 - maximumColorStock - 4 * (inventory.size - 1));
  for (let sample = 1; sample <= 50; sample++) {
    tests++;
    const seed = level * 100 + sample;
    state = seed;
    draws = 0;
    const originalMap = exportsObject.Create.getInitData(level - 1);
    const originalRandomDraws = draws;
    maximumOriginalRandomDraws = Math.max(maximumOriginalRandomDraws, draws);
    const original = Array.from({ length: area.row * area.column }, (_, index) => normalize(originalMap.get(index) || []));
    for (let index = 0; index < original.length; index++) {
      const target = Number(cfg.Excelarea_color1[index]['level' + level]);
      if (original[index].length !== (target > 0 ? 10 : 0)) invalidOriginal++;
    }
    state = seed;
    draws = 0;
    const aligned = port(level, true).map(normalize);
    if (JSON.stringify(original) === JSON.stringify(aligned) && draws === originalRandomDraws) equalAligned++;
    state = seed;
    draws = 0;
    const current = port(level, false).map(normalize);
    if (JSON.stringify(original) === JSON.stringify(current)) equalCurrent++;
    else if (firstCurrentOrderDifference === null) {
      const index = current.findIndex((stack, position) => JSON.stringify(stack) !== JSON.stringify(original[position]));
      firstCurrentOrderDifference = { level, sample, seed, firstDifferentCell: index,
        original: original[index], currentOrderPort: current[index] };
    }
  }
}

const identityPaths = [
  'docs/rea-reference/source/main.index.js', 'docs/rea-reference/source/modules/Create.js',
  'scripts/challenge_game.gd', 'scripts/challenge_data.gd',
  ...['Excelchallenge_area1', 'Excelchallenge_deal1', 'Excelarea_color1', 'Excelkeyvalue'].map(name => 'docs/rea-reference/configs/' + name + '.json'),
];
const identities = identityPaths.map(relativePath => ({ path: relativePath,
  sha256: crypto.createHash('sha256').update(fs.readFileSync(path.join(root, relativePath))).digest('hex') }));
const result = {
  kind: 'offline-controlled-replay',
  environment: { node: process.version, platform: process.platform, architecture: process.arch, osRelease: os.release() },
  randomStream: { algorithm: 'xorshift32 (13,17,5)', unsignedNormalization: 'uint32 / 4294967296', seedFormula: 'level * 100 + sample', levelRange: [1, 100], sampleRange: [1, 50] },
  scope: 'Complete per-cell coin order and hidden flags; aligned mode additionally requires equal random draw count. Manual JS translation of local generator; GDScript itself is not executed.',
  limits: ['No browser or production game runtime executed.', 'Production Godot/Cocos RNG engines are replaced by the controlled stream.', 'No claim about puzzle solvability or live UI behavior.'],
  identities,
  embeddedTableCheck,
  results: { tests, equalAligned, equalCurrent, ...probe, localDefensiveFillFallback, invalidOriginal, minimumFallbackInventoryMargin, maximumOriginalRandomDraws },
  firstCurrentOrderDifference,
};
console.log(JSON.stringify(result, null, 2));
if (equalAligned !== tests || invalidOriginal !== 0) process.exitCode = 1;

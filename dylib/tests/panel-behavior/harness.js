'use strict';
const fs = require('fs');
const { execFileSync } = require('child_process');

const CAPS = { '\u0003': 'R0', '\u0004': 'B0' };
const expand = s => s.replace(/[\u0001-\u0008]/g, c => {
  if (!(c in CAPS)) throw new Error('payload uses unbound capture ' + c.charCodeAt(0));
  return CAPS[c];
});

const mk = (type, props) => ({ type, props });
const react = { jsx: mk, jsxs: mk, Fragment: 'Fragment' };
const barrel = { XY: 'Section', m: 'Dropdown', Yh: 'Toggle' };

const FORMS = {
  component: { arg: 'component', react: 'i',  barrel: 'c'  },
  statement: { arg: 'statement', react: 'R0', barrel: 'B0' },
};

function panel(emit, form) {
  const raw = execFileSync(emit, [form], { encoding: 'utf8' }).trim();
  const src = form === 'component'
    ? 'var ' + raw.replace(/,$/, '')
    : expand(raw).replace(/;$/, '');
  const f = FORMS[form];
  const written = [];
  const SteamClient = {
    Apps: { SetAppLaunchOptions: (appid, opts) => written.push({ appid, opts }) },
  };
  const build = new Function(f.react, f.barrel, 'SteamClient', src + '\nreturn MSCXOpts;');
  return { render: build(react, barrel, SteamClient), written };
}

function walk(node, out = []) {
  if (!node || typeof node !== 'object') return out;
  if (Array.isArray(node)) { node.forEach(c => walk(c, out)); return out; }
  if (typeof node.type === 'function') return walk(node.type(node.props), out);
  if (node.type) out.push(node);
  if (node.props && node.props.children) walk(node.props.children, out);
  return out;
}

function details(launchOptions, over) {
  return Object.assign({
    unAppID: 287700,
    vecPlatforms: ['windows'],
    strCompatToolName: 'steambridge',
    strLaunchOptions: launchOptions,
  }, over || {});
}

function runner(name) {
  let failed = 0;
  return {
    ok(cond, what) {
      if (!cond) failed++;
      console.log(`  ${cond ? 'PASS' : 'FAIL'}  [${name}] ${what}`);
    },
    get failed() { return failed; },
  };
}

module.exports = { panel, walk, details, runner, expand, FORMS };

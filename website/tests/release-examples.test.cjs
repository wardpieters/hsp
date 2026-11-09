const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const {execFileSync} = require('node:child_process');

async function fixture(t, buildSource = `
  const fs = require('node:fs');
  fs.mkdirSync('build', {recursive: true});
  fs.writeFileSync('build/rendered.txt', fs.readFileSync('../README.md', 'utf8') + fs.readFileSync('../examples/README.md', 'utf8'));
`) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hsp-release-'));
  t.after(() => fs.rm(root, {recursive: true, force: true}));
  await fs.mkdir(path.join(root, 'website'));
  await fs.mkdir(path.join(root, 'examples'));
  await fs.writeFile(path.join(root, 'README.md'), 'source = "git::https://github.com/wardpieters/hsp.git//modules/hsp?ref=abc123"\n');
  await fs.writeFile(path.join(root, 'examples/README.md'), [
    'source = "git::https://github.com/wardpieters/hsp.git//modules/connections?ref=v1.0.0"',
    'source = "git::https://github.com/wardpieters/hsp.git//modules/hsp?ref=def456"',
    'source = "git::https://github.com/wardpieters/hsp.git//modules/proxmox_host?ref=v1.1.0"',
    'source = "../../modules/hsp"',
    'source = "git::https://github.com/other/project.git//module?ref=v1.0.0"',
  ].join('\n'));
  await fs.writeFile(path.join(root, 'website/package.json'), JSON.stringify({scripts: {build: 'node build.cjs'}}));
  await fs.writeFile(path.join(root, 'website/build.cjs'), buildSource);
  return {root, context: {cwd: root, nextRelease: {gitTag: 'v2.3.4'}}};
}

test('release preparation updates every published pin and builds those exact examples', async t => {
  const {prepare} = require('../scripts/release-examples.cjs');
  const {root, context} = await fixture(t);
  await prepare({}, context);
  const readme = await fs.readFile(path.join(root, 'README.md'), 'utf8');
  const examples = await fs.readFile(path.join(root, 'examples/README.md'), 'utf8');
  assert.equal(readme, 'source = "git::https://github.com/wardpieters/hsp.git//modules/hsp?ref=v2.3.4"\n');
  assert.equal(examples, [
    'source = "git::https://github.com/wardpieters/hsp.git//modules/connections?ref=v2.3.4"',
    'source = "git::https://github.com/wardpieters/hsp.git//modules/hsp?ref=v2.3.4"',
    'source = "git::https://github.com/wardpieters/hsp.git//modules/proxmox_host?ref=v2.3.4"',
    'source = "../../modules/hsp"',
    'source = "git::https://github.com/other/project.git//module?ref=v1.0.0"',
  ].join('\n'));
  assert.equal(await fs.readFile(path.join(root, 'website/build/rendered.txt'), 'utf8'), readme + examples);
});

test('release preparation fails before writing if a guide has no published pin', async t => {
  const {prepare} = require('../scripts/release-examples.cjs');
  const {root, context} = await fixture(t);
  const original = await fs.readFile(path.join(root, 'README.md'), 'utf8');
  await fs.writeFile(path.join(root, 'examples/README.md'), 'No module references');
  await assert.rejects(prepare({}, context), /No published HSP module references/);
  assert.equal(await fs.readFile(path.join(root, 'README.md'), 'utf8'), original);
});

test('a failed documentation build aborts release preparation', async t => {
  const {prepare} = require('../scripts/release-examples.cjs');
  const {context} = await fixture(t, 'process.exit(1);');
  await assert.rejects(prepare({}, context), /Documentation build failed/);
});

test('release preparation rejects an invalid release tag before changing files', async t => {
  const {prepare} = require('../scripts/release-examples.cjs');
  const {root, context} = await fixture(t);
  const original = await fs.readFile(path.join(root, 'README.md'), 'utf8');
  context.nextRelease.gitTag = 'main';
  await assert.rejects(prepare({}, context), /Invalid release tag/);
  assert.equal(await fs.readFile(path.join(root, 'README.md'), 'utf8'), original);
});

test('release commits publish both updated guides without including other changes', async t => {
  const {prepare} = require('../scripts/release-examples.cjs');
  const {root, context} = await fixture(t);
  const remote = path.join(root, 'remote.git');
  const env = {...process.env,
    GIT_AUTHOR_NAME: 'Release Test', GIT_AUTHOR_EMAIL: 'release@example.com',
    GIT_COMMITTER_NAME: 'Release Test', GIT_COMMITTER_EMAIL: 'release@example.com',
  };
  const git = (...args) => execFileSync('git', args, {cwd: root, env, encoding: 'utf8'}).trim();
  git('init', '--quiet', '--bare', remote);
  git('init', '--quiet', '--initial-branch=main');
  await fs.writeFile(path.join(root, '.gitignore'), 'remote.git/\nwebsite/build/\n');
  git('add', '.');
  git('-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'Initial fixtures');
  git('remote', 'add', 'origin', remote);
  await fs.writeFile(path.join(root, 'website/unrelated.txt'), 'Do not release this');
  await prepare({}, context);
  const {prepare: commitRelease} = await import('@semantic-release/git');
  const [, options] = require('../release.config.cjs').plugins.find(([name]) => name === '@semantic-release/git');
  await commitRelease(options, {
    ...context, env, branch: {name: 'main'}, options: {repositoryUrl: remote},
    nextRelease: {...context.nextRelease, version: '2.3.4'}, logger: {log() {}},
  });
  assert.equal(git('log', '-1', '--format=%s'), 'chore(release): 2.3.4 [skip ci]');
  assert.equal(git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD'), 'README.md\nexamples/README.md');
  assert.match(git('--git-dir', remote, 'show', 'main:README.md'), /\?ref=v2\.3\.4/);
  assert.match(git('--git-dir', remote, 'show', 'main:examples/README.md'), /\?ref=v2\.3\.4/);
});

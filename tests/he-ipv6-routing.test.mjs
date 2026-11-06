import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import test, { before } from 'node:test';
import { renderedFiles, networkFixture } from './helpers/network-fixture.mjs';
let script, teardown;
before(async () => { const f = await renderedFiles('modules/proxmox_host', 'tests/ipv6.tftest.hcl'); script = f.he_helper; teardown = f.teardown; });

test('starts guarded tunnel and public /128 before any exposure; reload converges', async t => {
  const f = await networkFixture(t, script); await f.run('start');
  const s = await f.read();
  assert.deepEqual(s.links['hsp-vip6'].addresses, ['2001:470:1f15:4d6::2/128']);
  assert.deepEqual(s.links['hsp-he6'].addresses, ['2001:470:1f14:4d4::2/64']);
  assert.equal(s.links['hsp-he6'].mtu, 1480);
  assert.deepEqual(s.routes.sort(), ['blackhole 2001:470:1f15:4d6::/64 metric 42761', 'default via 2001:470:1f14:4d4::1 dev hsp-he6 metric 42761'].sort());
  assert.match(s.tables.hsp_he_host, /iifname "hsp-he6" drop/);
  assert.match(s.tables.hsp_he_host, /ip6 daddr 2001:470:1f15:4d6::2 drop/);
  assert(s.log.findIndex(x => x.startsWith('nft -f ')) < s.log.findIndex(x => x.startsWith('ip tunnel add')));
  await f.run('reload'); const again = await f.read();
  assert.deepEqual(again.links, s.links); assert.deepEqual(again.routes.sort(), s.routes.sort());
});
test('stop is idempotent and preserves unrelated interfaces/routes/tables and forwarding', async t => {
  const f = await networkFixture(t, script); await f.seed({ links: { unrelated: { type: 'dummy' } }, routes: ['default via 2001:db8::1 dev unrelated metric 100'], tables: { unrelated: 'keep' } });
  await f.run('start'); await f.run('stop'); await f.run('stop'); const s = await f.read();
  assert.deepEqual(Object.keys(s.links), ['unrelated']); assert.deepEqual(s.routes, ['default via 2001:db8::1 dev unrelated metric 100']); assert.deepEqual(s.tables, { unrelated: 'keep' });
  assert(!s.log.some(x => x.includes('forwarding=0')));
});
test('foreign interface, table and reserved route collisions fail before mutation', async t => {
  for (const changes of [{ links: { 'hsp-he6': { type: 'dummy', alias: 'foreign' } } }, { tables: { hsp_he_host: 'foreign' } }, { routes: ['default via 2001:db8::1 dev foreign metric 42761'] }]) {
    const f = await networkFixture(t, script); await f.seed(changes); await assert.rejects(f.run('start')); const s = await f.read();
    for (const [key, value] of Object.entries(changes)) assert.deepEqual(s[key], value);
  }
});
test('partial start rolls back owned interfaces but retains host input guard', async t => {
  const f = await networkFixture(t, script); await f.seed({ fail: { tool: 'ip', match: '-6 address replace' } }); await assert.rejects(f.run('start'));
  const s = await f.read(); assert.deepEqual(s.links, {}); assert(s.tables.hsp_he_host); await f.run('start'); await f.run('stop');
});
test('changed tunnel endpoints reconcile without stale addresses; topology migration is refused', async t => {
  const f = await networkFixture(t, script); await f.run('start');
  const changed = script.replaceAll('216.66.84.46', '216.66.84.47').replaceAll('2001:470:1f14:4d4::2/64', '2001:470:1f14:4d4::3/64');
  await writeFile(f.scriptPath, changed); await f.run('reload'); const s = await f.read();
  assert.match(s.links['hsp-he6'].tunnel, /216\.66\.84\.47/); assert.deepEqual(s.links['hsp-he6'].addresses, ['2001:470:1f14:4d4::3/64']);
  await writeFile(f.scriptPath, changed.replaceAll('fd42:77:1::/48', 'fd42:77:2::/48')); await assert.rejects(f.run('reload'), /disable|topology/);
});
test('stop refuses a foreign replacement instead of deleting it', async t => {
  const f = await networkFixture(t, script); await f.run('start'); const s = await f.read(); s.links['hsp-he6'].alias = 'foreign'; await f.seed({ links: s.links });
  await assert.rejects(f.run('stop')); assert.equal((await f.read()).links['hsp-he6'].alias, 'foreign');
});

test('Terraform host teardown retries helper even after a failed stop deactivates service', async t => {
  assert.match(teardown?.command ?? '', /systemctl stop .* && .*routing.sh stop/);
  const f = await networkFixture(t, script); await f.run('start');
  await f.seed({ serviceActive: true, fail: { tool: 'ip', match: 'link delete' } });
  await assert.rejects(f.teardown(teardown.command));
  assert.equal((await f.read()).serviceActive, false); assert((await f.read()).tables.hsp_he_host);
  await f.teardown(teardown.command);
  const s = await f.read(); assert.deepEqual(s.links, {}); assert.deepEqual(s.tables, {}); assert.deepEqual(s.routes, []);
});

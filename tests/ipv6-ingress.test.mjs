import assert from 'node:assert/strict';
import test, { before } from 'node:test';
import { networkFixture, renderedFiles } from './helpers/network-fixture.mjs';
let enabled, revoked;
before(async () => {
  enabled = await renderedFiles('modules/ipv6_ingress', 'tests/ingress.tftest.hcl', 'enabled');
  revoked = await renderedFiles('modules/ipv6_ingress', 'tests/ingress.tftest.hcl', 'revoked');
});
const vip = '2001:470:1f15:4d6::2', guest = 'fd42:77:1:1::2';
const files = f => ({ 'rules.nft': f.ingress_rules, permissions: f.ingress_permissions });
async function fixture(t) {
  const f = await networkFixture(t, enabled.ingress_helper, files(enabled));
  await f.seed({ links: { 'hsp-he6': {}, hsp1002: {}, hsp1001: {} } });
  return f;
}
const flows = () => [
  { id: 'incoming-https', origSrc: '2001:db8::7', origDst: vip, proto: 'tcp', port: 443, zone: 0 },
  { id: 'outgoing-https', origSrc: guest, replyDst: vip, proto: 'tcp', port: 443, zone: 0 },
  { id: 'outgoing-ntp', origSrc: guest, replyDst: vip, proto: 'udp', port: 123, zone: 0 },
  { id: 'outgoing-ping', origSrc: guest, replyDst: vip, proto: '58', zone: 0 },
  { id: 'unrelated', origSrc: 'fd42:77:1:3::2', replyDst: vip, proto: 'tcp', port: 443, zone: 0 },
];
test('no-op reload preserves flows and foreign tables; policy revocation removes only affected flows', async t => {
  const f = await fixture(t); await f.seed({ tables: { foreign: 'keep unrelated filtering' } }); await f.run('start');
  await f.seed({ flows: flows() }); await f.run('reload'); assert.deepEqual((await f.read()).flows, flows());
  await f.configure(files(revoked)); await f.run('reload'); const s = await f.read();
  assert.deepEqual(s.flows.map(f => f.id), ['outgoing-ntp', 'unrelated']); assert.equal(s.tables.foreign, 'keep unrelated filtering');
  const purge = s.log.findIndex(x => x.startsWith('conntrack -D'));
  assert(s.log.slice(0, purge).some(x => x.startsWith('nft -f ')));
  assert(!s.log.some(x => /conntrack.*(?:-F|--flush)/.test(x)));
});
test('stop revokes owned DNAT and all SNAT protocols, retaining unrelated state', async t => {
  const f = await fixture(t); await f.run('start'); await f.seed({ flows: flows() }); await f.run('stop'); await f.run('stop');
  const s = await f.read(); assert.deepEqual(s.flows.map(f => f.id), ['unrelated']); assert.equal(s.tables.hsp_he_ingress, undefined);
});
test('conntrack purge failure leaves a blocking guard and can be repaired', async t => {
  const f = await fixture(t); await f.run('start'); await f.seed({ flows: flows(), fail: { tool: 'conntrack', match: '-D' } });
  await f.configure(files(revoked)); await assert.rejects(f.run('reload'));
  assert.match((await f.read()).tables.hsp_he_ingress, /ip6 saddr fd42:77:1::\/48 drop/);
  assert(!((await f.read()).tables.hsp_he_ingress.includes('snat to')));
  await f.run('reload'); assert.deepEqual((await f.read()).flows.map(f => f.id), ['outgoing-ntp', 'unrelated']);
});
test('foreign table and conflicting conntrack zone preflight fail without overwriting rules', async t => {
  const f = await fixture(t); await f.seed({ tables: { hsp_he_ingress: 'foreign' } }); await assert.rejects(f.run('start')); assert.equal((await f.read()).tables.hsp_he_ingress, 'foreign');
  const g = await fixture(t); await g.seed({ raw: '-A PREROUTING -i fwbr+ -j CT --zone 1' }); await assert.rejects(g.run('start')); assert.deepEqual((await g.read()).tables, {});
});
test('adding permissions preserves retained flows; rejected reduction blocks old established permissions', async t => {
  const f = await fixture(t); await f.configure(files(revoked)); await f.run('start');
  await f.seed({ flows: flows().filter(f => f.id === 'outgoing-ntp') });
  await f.configure(files(enabled)); await f.run('reload');
  assert.deepEqual((await f.read()).flows.map(f => f.id), ['outgoing-ntp']);
  const oldRules = (await f.read()).tables.hsp_he_ingress;
  await f.configure(files(revoked)); await f.seed({ fail: { tool: 'nft', match: '-c' } });
  await assert.rejects(f.run('reload'));
  assert.notEqual((await f.read()).tables.hsp_he_ingress, oldRules);
  assert.match((await f.read()).tables.hsp_he_ingress, /iifname "hsp-he6" drop/);
  assert(!((await f.read()).tables.hsp_he_ingress.includes('snat to')));
  await f.run('reload'); assert.deepEqual((await f.read()).flows.map(f => f.id), ['outgoing-ntp']);
});

test('failed reduction preflight blocks access; failed additions preserve restrictive policy', async t => {
  const f = await fixture(t); await f.run('start'); await f.seed({ flows: flows(), raw: '-A PREROUTING -j CT --zone 1' });
  await f.configure(files(revoked)); await assert.rejects(f.run('reload'));
  assert.match((await f.read()).tables.hsp_he_ingress, /iifname "hsp-he6" drop/);
  const g = await fixture(t); await g.configure(files(revoked)); await g.run('start');
  const old = (await g.read()).tables.hsp_he_ingress;
  await g.configure(files(enabled)); await g.seed({ fail: { tool: 'nft', match: '-c' } }); await assert.rejects(g.run('reload'));
  assert.equal((await g.read()).tables.hsp_he_ingress, old);
});
test('Terraform teardown retries helper after failed ExecStop leaves service inactive', async t => {
  assert.match(enabled.teardown?.command ?? '', /systemctl stop .* && .*ingress.sh stop/);
  const f = await fixture(t); await f.run('start');
  await f.seed({ serviceActive: true, flows: flows(), fail: { tool: 'conntrack', match: '-D' } });
  await assert.rejects(f.teardown(enabled.teardown.command));
  assert.equal((await f.read()).serviceActive, false);
  assert.match((await f.read()).tables.hsp_he_ingress, /iifname "hsp-he6" drop/);
  await f.teardown(enabled.teardown.command);
  assert.equal((await f.read()).tables.hsp_he_ingress, undefined);
  assert.deepEqual((await f.read()).flows.map(f => f.id), ['unrelated']);
});

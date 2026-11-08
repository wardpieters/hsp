import assert from 'node:assert/strict';
import test, { before } from 'node:test';
import { readFile } from 'node:fs/promises';
import { networkFixture, renderedFiles } from './helpers/network-fixture.mjs';
let enabled, revoked;
const hairpin = {};
before(async () => {
  enabled = await renderedFiles('modules/ipv6_ingress', 'tests/ingress.tftest.hcl', 'enabled');
  for (const name of ['enabled', 'grant_revoked', 'egress_revoked', 'remapped', 'self_only']) hairpin[name] = await renderedFiles('modules/ipv6_ingress', 'tests/hairpin.tftest.hcl', name);
  revoked = await renderedFiles('modules/ipv6_ingress', 'tests/ingress.tftest.hcl', 'revoked');
});
const vip = '2001:470:1f15:4d6::2', guest = 'fd42:77:1:1::2';
const files = f => ({ 'rules.nft': f.ingress_rules, permissions: f.ingress_permissions, 'bridge-zones': f.ingress_zones ?? '' });
async function fixture(t) {
  const f = await networkFixture(t, enabled.ingress_helper, files(enabled));
  await f.seed({ links: { 'hsp-he6': {}, hsp1002: {}, hsp1001: {}, hsp1003: {} } });
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

test('adopting bridge zones removes broken untranslated flows and only owned bridge flows', async t => {
  const f = await fixture(t);
  await f.configure({ 'bridge-zones': '' }); await f.run('start');
  const broken = [
    { id: 'broken-https', origSrc: guest, replyDst: guest, proto: 'tcp', port: 443, zone: 0 },
    { id: 'broken-ping', origSrc: guest, replyDst: guest, proto: '58', zone: 0 },
    { id: 'bridge-ping', origSrc: guest, replyDst: guest, proto: '58', zone: 1 },
    { id: 'incoming-bridge', origSrc: '2001:db8::7', origDst: 'fd42:77:1:2::2', proto: 'tcp', port: 443, zone: 1 },
    { id: 'foreign-bridge', origSrc: 'fd42:77:1:3::2', proto: '58', zone: 1 },
    { id: 'foreign-default', origSrc: '2001:db8::7', proto: 'tcp', port: 443, zone: 0 },
  ];
  await f.seed({ flows: broken });
  await f.configure({ 'bridge-zones': 'fwbr1001i0|fd42:77:1:1::2\nfwbr1002i0|fd42:77:1:2::2\n' }); await f.run('reload');
  assert.deepEqual((await f.read()).flows.map(f => f.id), ['foreign-bridge', 'foreign-default']);
  assert(!((await f.read()).log.some(x => /conntrack.*(?:-F|--flush)/.test(x))));
  await f.seed({ flows: broken }); await f.run('reload');
  assert.deepEqual((await f.read()).flows, broken, 'unchanged bridge profile must preserve sessions');
});

test('bridge-zone migration cleanup failure blocks traffic until a successful retry', async t => {
  const f = await fixture(t); await f.configure({ 'bridge-zones': '' }); await f.run('start');
  await f.configure({ 'bridge-zones': 'fwbr1001i0|fd42:77:1:1::2\n' });
  await f.seed({ fail: { tool: 'conntrack', match: '-D' } });
  await assert.rejects(f.run('reload'));
  assert.match((await f.read()).tables.hsp_he_ingress, /iifname "hsp-he6" drop/);
  await f.run('reload'); assert.match((await f.read()).tables.hsp_he_ingress, /snat to/);
});

test('adding a guest bridge preserves established sessions for existing guests', async t => {
  const f = await fixture(t);
  await f.configure({ 'bridge-zones': 'fwbr1001i0|fd42:77:1:1::2\n' }); await f.run('start');
  const existing = [
    { id: 'retained-routed', origSrc: guest, replyDst: vip, proto: 'tcp', port: 443, zone: 0 },
    { id: 'retained-bridge', origSrc: guest, replyDst: guest, proto: '58', zone: 1 },
  ];
  await f.seed({ flows: [...existing, { id: 'new-bridge', origDst: 'fd42:77:1:2::2', proto: 'tcp', port: 443, zone: 1 }] });
  await f.configure({ 'bridge-zones': 'fwbr1001i0|fd42:77:1:1::2\nfwbr1002i0|fd42:77:1:2::2\n' });
  await f.run('reload'); assert.deepEqual((await f.read()).flows, existing);
});

const target = 'fd42:77:1:2::2', gateway = 'fd42:77:1:2::1';
function hairpinFlows() {
  const result = [];
  for (const [name, source, translated] of [['cloud', guest, 50000], ['other-client', 'fd42:77:1:3::2', 50001], ['self', target, 50002]]) {
    result.push({ id: name + '-routed', origSrc: source, origDst: vip, replySrc: target, replyDst: gateway, origSport: 50000, replyDport: translated, proto: 'tcp', port: 443, zone: 0 });
    result.push({ id: name + '-source', origSrc: source, origDst: vip, replySrc: vip, replyDst: source, origSport: 50000, replyDport: 50000, proto: 'tcp', port: 443, zone: 1 });
    result.push({ id: name + '-bridge', origSrc: gateway, origDst: target, replySrc: target, replyDst: gateway, origSport: translated, replyDport: translated, proto: 'tcp', port: 443, zone: 1 });
  }
  result.push({ id: 'external', origSrc: '2001:db8::7', origDst: vip, replySrc: target, replyDst: '2001:db8::7', origSport: 51000, replyDport: 51000, proto: 'tcp', port: 443, zone: 0 });
  result.push({ id: 'internet', origSrc: guest, origDst: '2001:db8::8', replySrc: '2001:db8::8', replyDst: vip, origSport: 52000, replyDport: 52000, proto: 'tcp', port: 443, zone: 0 });
  return result;
}
async function hairpinFixture(t, name = 'enabled') {
  const f = await networkFixture(t, hairpin.enabled.ingress_helper, files(hairpin[name]));
  await f.seed({ links: { 'hsp-he6': {}, hsp1001: {}, hsp1002: {}, hsp1003: {} }, tables: { foreign: 'keep' } });
  await f.run('start'); await f.seed({ flows: hairpinFlows() }); return f;
}
test('hairpin revocation preserves independent flows', async t => {
  const f = await hairpinFixture(t); await f.run('reload'); assert.deepEqual((await f.read()).flows, hairpinFlows());
  await f.seed({ log: [] }); await f.configure(files(hairpin.grant_revoked)); await f.run('reload');
  assert.deepEqual((await f.read()).flows.map(x => x.id).sort(), ['external', 'internet', 'other-client-bridge', 'other-client-routed', 'other-client-source', 'self-bridge', 'self-routed', 'self-source'].sort());
  const s = await f.read(); assert.equal(s.tables.foreign, 'keep'); assert(!s.log.some(x => /conntrack.*(?:-F|--flush)|flush ruleset/.test(x)));
  assert(s.log.findIndex(x => x.startsWith('nft -f ')) < s.log.findIndex(x => x.startsWith('conntrack -D')));
  await f.configure(files(hairpin.enabled)); await f.run('reload'); assert.equal((await f.read()).flows.length, 8);
});
test('egress revocation preserves same-port hairpin', async t => {
  const f = await hairpinFixture(t);
  const retained = [
    { id: 'udp', origSrc: guest, replyDst: vip, proto: 'udp', port: 123, zone: 0 },
    { id: 'icmp', origSrc: guest, replyDst: vip, proto: '58', zone: 0 },
  ];
  const internet = hairpinFlows().find(x => x.id === 'internet');
  await f.seed({ flows: [...hairpinFlows(), { ...internet, id: 'internet-bridge', zone: 1, replyDst: guest }, ...retained] });
  await f.configure(files(hairpin.egress_revoked)); await f.run('reload');
  assert.deepEqual((await f.read()).flows.map(x => x.id), [...hairpinFlows().filter(x => x.id !== 'internet'), ...retained].map(x => x.id));
  assert.match((await f.read()).tables.hsp_he_ingress, /snat to/);
});
test('translated source-port collisions clean up selectively', async t => {
  const f = await hairpinFixture(t); await f.configure(files(hairpin.grant_revoked)); await f.run('reload');
  const s = await f.read(); assert(s.flows.some(x => x.id === 'other-client-bridge')); assert(!s.flows.some(x => x.id === 'cloud-bridge'));
  assert(s.log.some(x => x.includes('--zone 1') && x.includes('--sport 50000') && x.includes('--orig-src ' + gateway)));
});
test('self-hairpin stop is idempotent', async t => {
  const f = await hairpinFixture(t, 'self_only'); await f.seed({ flows: hairpinFlows().filter(x => x.id.startsWith('self')) });
  await f.seed({ serviceActive: true, fail: { tool: 'conntrack', match: '-D -f ipv6 --zone 1 --orig-src ' + gateway } });
  await assert.rejects(f.teardown(hairpin.self_only.teardown.command)); assert.equal((await f.read()).serviceActive, false);
  await f.teardown(hairpin.self_only.teardown.command); await f.run('stop'); assert.deepEqual((await f.read()).flows, []);
});
test('cleanup resumes after zone-zero deletion', async t => {
  const f = await hairpinFixture(t); await f.configure(files(hairpin.grant_revoked));
  await f.seed({ fail: { tool: 'conntrack', match: '-D -f ipv6 --zone 1 --orig-src ' + gateway } });
  await assert.rejects(f.run('reload')); assert(!(await f.read()).flows.some(x => x.id === 'cloud-routed'));
  const pending = await import('node:fs/promises').then(fs => fs.readFile(f.dir + '/runtime/hairpin-pending', 'utf8'));
  assert.match(pending, /50000\|443\|fd42:77:1:2::2\|fd42:77:1:2::1\|50000/);
  await f.run('reload'); assert(!(await f.read()).flows.some(x => x.id.startsWith('cloud')));
  const log = (await f.read()).log; const firstDelete = log.findIndex(x => x.startsWith('conntrack -D'));
  assert(log.slice(0, firstDelete).some(x => x.startsWith('nft -f ')));
});
test('malformed enumeration blocks reductions', async t => {
  for (const enumeration of ['tcp 6 123 ESTABLISHED src=fd42:77:1:1::2', 'tcp 6 src=fd42:77:1:1::2 dst=' + vip + ' sport=50000 dport=443 src=' + target]) {
    const f = await hairpinFixture(t); await f.configure(files(hairpin.grant_revoked)); await f.seed({ enumeration });
    await assert.rejects(f.run('reload')); assert.match((await f.read()).tables.hsp_he_ingress, /iifname "hsp-he6" drop/);
  }
  const f = await hairpinFixture(t); await f.configure(files(hairpin.grant_revoked)); await f.seed({ fail: { tool: 'conntrack', match: '-L' } }); await assert.rejects(f.run('reload'));
  const g = await hairpinFixture(t); await g.configure(files(hairpin.grant_revoked)); await g.seed({ flows: [] }); await g.run('reload');
});
test('bridge changes revoke source and target views', async t => {
  for (const address of [guest, target]) {
    const f = await hairpinFixture(t); await f.configure({ 'bridge-zones': 'fwbr1001i0|' + address + '\n' }); await f.run('reload');
    assert(!(await f.read()).flows.some(x => x.id.startsWith('cloud')));
  }
});
test('old manifests adopt hairpin without broad purges', async t => {
  const f = await fixture(t); await f.run('start'); await f.seed({ flows: hairpinFlows() }); await f.configure(files(hairpin.enabled)); await f.run('reload');
  assert.deepEqual((await f.read()).flows, hairpinFlows());
});
test('failed hairpin reduction retains guard', async t => {
  const f = await hairpinFixture(t); await f.configure(files(hairpin.grant_revoked)); await f.seed({ raw: '-A PREROUTING -j CT --zone 1' });
  await assert.rejects(f.run('reload')); assert.match((await f.read()).tables.hsp_he_ingress, /iifname "hsp-he6" drop/);
});

test('forward remap snapshots hairpin before DNAT cleanup', async t => {
  const f = await hairpinFixture(t); await f.configure(files(hairpin.remapped)); await f.run('reload');
  assert.deepEqual((await f.read()).flows.map(x => x.id), ['internet']);
  const log = (await f.read()).log;
  assert(log.findIndex(x => x.startsWith('conntrack -L')) < log.findIndex(x => x.startsWith('conntrack -D')));
});

// A remap's old public-port purge must finish before replacement traffic enters.
test('forward remap keeps replacement closed through old D cleanup', async t => {
  const f = await hairpinFixture(t); await f.configure(files(hairpin.remapped)); await f.run('reload');
  const purges = (await f.read()).conntrackDeletes.filter(x => x.command === '-D -f ipv6 --zone 0 --orig-dst ' + vip + ' -p tcp --dport 443');
  assert.equal(purges.length, 1);
  assert.match(purges[0].rules, /iifname "hsp-he6" drop/);
  assert(!purges[0].rules.includes('dnat to'));
  assert.match((await f.read()).tables.hsp_he_ingress, /dnat to fd42:77:1:3::2/);
});
test('grant revocation removes orphan source bridge without guessing target port', async t => {
  const f = await hairpinFixture(t);
  const selected = hairpinFlows().filter(x => ['cloud-source', 'cloud-bridge', 'other-client-source', 'other-client-bridge'].includes(x.id));
  await f.seed({ flows: selected, fail: { tool: 'conntrack', match: '-D -f ipv6 --zone 1 --orig-src ' + guest } });
  await f.configure(files(hairpin.grant_revoked)); await assert.rejects(f.run('reload'));
  assert.match(await readFile(f.dir + '/runtime/hairpin-pending', 'utf8'), /S\|fd42:77:1:1::2\|2001:470:1f15:4d6::2\|none\|443/);
  await f.run('reload');
  assert.deepEqual((await f.read()).flows.map(x => x.id), ['cloud-bridge', 'other-client-source', 'other-client-bridge']);
});
test('egress revocation removes orphan Internet bridge and preserves P source bridge', async t => {
  const f = await hairpinFixture(t);
  const internet = hairpinFlows().find(x => x.id === 'internet');
  const bridge = { ...internet, id: 'orphan-internet-bridge', zone: 1, replyDst: guest };
  const retained = hairpinFlows().filter(x => ['cloud-source', 'other-client-source', 'other-client-bridge'].includes(x.id));
  await f.seed({ flows: [bridge, ...retained], fail: { tool: 'conntrack', match: '-D -f ipv6 --zone 1 --orig-src ' + guest } });
  await f.configure(files(hairpin.egress_revoked)); await assert.rejects(f.run('reload'));
  assert.match(await readFile(f.dir + '/runtime/hairpin-pending', 'utf8'), /B\|fd42:77:1:1::2\|2001:db8::8\|52000\|443/);
  await f.run('reload');
  assert.deepEqual((await f.read()).flows, retained);
});
test('invalid E remote addresses and reply relationships never publish a journal and allow retry', async t => {
  for (const [destination, replySource] of [
    [':::::', ':::::'], ['2001:db8:::8', '2001:db8:::8'], ['2001:db8:0:0:0:0:0:0:8', '2001:db8:0:0:0:0:0:0:8'],
    ['2001:db8::8', '2001:db8::9'], ['2001:db8::8', ':::::'],
  ]) await t.test(destination + ' / ' + replySource, async t => {
    const f = await hairpinFixture(t); await f.configure(files(hairpin.egress_revoked));
    await f.seed({ enumeration: 'ipv6 10 tcp 6 120 ESTABLISHED src=' + guest + ' dst=' + destination + ' sport=52000 dport=443 src=' + replySource + ' dst=' + vip + ' sport=443 dport=52000 [ASSURED] mark=0 use=1' });
    await assert.rejects(f.run('reload'));
    assert.match((await f.read()).tables.hsp_he_ingress, /iifname "hsp-he6" drop/);
    await assert.rejects(readFile(f.dir + '/runtime/hairpin-pending'), { code: 'ENOENT' });
    await f.seed({ enumeration: null }); await f.run('reload');
    assert.deepEqual((await f.read()).flows, hairpinFlows().filter(x => x.id !== 'internet'));
  });
});

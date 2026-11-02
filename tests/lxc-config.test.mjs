import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { promisify } from 'node:util';
import test from 'node:test';

const exec = promisify(execFile);
const script = resolve(import.meta.dirname, '../modules/vm/scripts/lxc-config.pl');
const mount = ['lxc.mount.entry', '/dev/dri dev/dri none bind,optional,create=dir'];
const cgroup = ['lxc.cgroup2.devices.allow', 'c 226:128 rwm'];

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'hsp-lxc-config-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await mkdir(join(directory, 'PVE/LXC'), { recursive: true });
  await writeFile(join(directory, 'PVE/Cluster.pm'), 'package PVE::Cluster; sub cfs_update {} 1;');
  await writeFile(join(directory, 'PVE/INotify.pm'), 'package PVE::INotify; sub nodename { "pve" } 1;');
  await writeFile(join(directory, 'PVE/LXC/Config.pm'), `package PVE::LXC::Config;
use JSON::PP; our $locked = 0;
sub lock_config { my ($class, $id, $code) = @_; die "wrong CT ID" unless $id == 1009; local $locked = 1; $code->(); }
sub load_config { die "missing lock" unless $locked; open my $fh, '<', $ENV{HSP_FIXTURE} or die "Configuration file 'nodes/pve/lxc/1009.conf' does not exist\\n"; local $/; return decode_json(<$fh>); }
sub check_lock { die "config locked" if $_[1]->{lock}; }
sub write_config { die "missing lock" unless $locked; open my $fh, '>', $ENV{HSP_FIXTURE} or die $!; print $fh encode_json($_[2]); open my $count, '>>', $ENV{HSP_WRITES} or die $!; print $count "write\\n"; }
1;`);
  const path = join(directory, 'config.json');
  const seed = {
    hostname: 'plex', rootfs: 'local-lvm:vm-1009-disk-0,size=16G',
    lxc: [['lxc.apparmor.profile', 'generated'], ['lxc.mount.entry', '/srv/data srv/data none bind']],
    snapshots: { yesterday: { hostname: 'old-plex', lxc: [['lxc.cgroup2.devices.allow', 'c 29:0 rwm']] } },
  };
  await writeFile(path, JSON.stringify(seed));
  return {
    seed, path,
    read: async () => JSON.parse(await readFile(path, 'utf8')),
    writes: async () => (await readFile(join(directory, 'writes'), 'utf8')).trim().split('\n').length,
    run: async (operation = 'apply', entries = [mount, cgroup], extra = {}) => exec('perl', ['-I', directory, '-MMIME::Base64', '-e',
      'my $code = shift @ARGV; eval decode_base64($code); die $@ if $@;', Buffer.from(await readFile(script)).toString('base64'),
      Buffer.from(JSON.stringify({ vm_id: 1009, node_name: 'pve', entries, ...extra })).toString('base64'), operation],
    { env: { ...process.env, HSP_FIXTURE: path, HSP_WRITES: join(directory, 'writes') } }),
  };
}

test('adds exact mount and cgroup entries, preserving unrelated config and snapshots', async t => {
  const f = await fixture(t);
  await f.run();
  assert.deepEqual(await f.read(), { ...f.seed, lxc: [...f.seed.lxc, mount, cgroup] });
  assert.equal(await f.writes(), 1);
  await f.run();
  assert.deepEqual(await f.read(), { ...f.seed, lxc: [...f.seed.lxc, mount, cgroup] });
  assert.equal(await f.writes(), 1);
});

test('removes only previously managed pairs, including when input is emptied', async t => {
  const f = await fixture(t);
  await f.run();
  await f.run('remove');
  assert.deepEqual(await f.read(), f.seed);
  await f.run('remove');
  assert.deepEqual(await f.read(), f.seed);
});

test('replacement removes old entries then installs changed values', async t => {
  const f = await fixture(t);
  await f.run();
  await f.run('remove');
  const changed = ['lxc.cgroup2.devices.allow', 'c 29:0 rwm'];
  await f.run('apply', [changed]);
  assert.deepEqual(await f.read(), { ...f.seed, lxc: [...f.seed.lxc, changed] });
});

test('rejects wrong node and locked config before writing', async t => {
  const f = await fixture(t);
  await assert.rejects(f.run('apply', [mount], { node_name: 'other-node' }), /node/i);
  assert.deepEqual(await f.read(), f.seed);
  await writeFile(f.path, JSON.stringify({ ...f.seed, lock: 'backup' }));
  await assert.rejects(f.run(), /locked/);
  assert.deepEqual(await f.read(), { ...f.seed, lock: 'backup' });
});

test('rejects newline injection, unsupported keys and invalid identifiers', async t => {
  const f = await fixture(t);
  for (const entries of [
    [['lxc.mount.entry', '/dev/dri dev/dri none bind\nlxc.apparmor.profile: unconfined']],
    [['lxc.hook.pre-start', '/tmp/evil']],
    [['lxc.cgroup2.devices.allow: a', 'b']],
    [['lxc.cgroup2.devices.allow', ' c 226:128 rwm ']],
    [['lxc.cgroup2.devices.Allow', 'c 226:128 rwm']],
  ]) await assert.rejects(f.run('apply', entries));
  await assert.rejects(f.run('apply', [mount], { vm_id: '../1009' }));
  assert.deepEqual(await f.read(), f.seed);
});

test('quotes in mount values remain literal config data', async t => {
  const f = await fixture(t);
  const literal = ['lxc.mount.entry', "/dev/dri dev/dri none bind,optional # ' $(touch /tmp/hsp-unwanted)"];
  await f.run('apply', [literal]);
  assert.deepEqual((await f.read()).lxc.at(-1), literal);
});

test('removing the last raw entries preserves the container without an empty lxc section', async t => {
  const f = await fixture(t);
  const { lxc, ...withoutRaw } = f.seed;
  await writeFile(f.path, JSON.stringify(withoutRaw));
  await f.run();
  await f.run('remove');
  assert.deepEqual(await f.read(), withoutRaw);
});

test('cleanup tolerates an externally deleted container while apply fails', async t => {
  const f = await fixture(t);
  await rm(f.path);
  await f.run('remove');
  await assert.rejects(f.run(), /does not exist/);
  await assert.rejects(readFile(f.path), { code: 'ENOENT' });
});

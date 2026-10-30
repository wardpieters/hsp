import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { join, relative, resolve } from 'node:path';
import { promisify } from 'node:util';
import test from 'node:test';

const exec = promisify(execFile);

test('real REST provider manages nesting with non-root feature-only requests', { timeout: 120_000 }, async () => {
  const requests = [];
  const phases = new Set();
  let features;
  const server = createServer(async (req, res) => {
    const reply = (status, data) => {
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(data));
    };
    const auth = req.headers.authorization ?? '';
    if (!auth.startsWith('PVEAPIToken=offline@pve!test=')) return reply(401, { error: 'Expected a non-root API token' });
    const phase = auth.split('=').at(-1);
    if (!phases.has(phase)) {
      phases.add(phase);
      if (phase === 'drift') features = 'nesting=1';
      if (phase === 'remove') features = undefined;
      if (phase === 'preserve') features = 'keyctl=0,nesting=0,fuse=0';
    }
    if (req.url !== '/api2/json/nodes/pve/lxc/1009/config') return reply(404, { error: 'Unexpected API path' });
    requests.push({ method: req.method, phase });
    if (req.method === 'GET') {
      return reply(200, { data: { ...(features === undefined ? {} : { features }), hostname: 'plex', 'ssh-public-keys': 'unmanaged-field' } });
    }
    if (req.method !== 'PUT') return reply(405, { error: 'Only feature PUTs are allowed' });
    let raw = '';
    for await (const chunk of req) raw += chunk;
    let body;
    try { body = JSON.parse(raw); } catch { return reply(400, { error: 'Expected JSON' }); }
    if (Object.keys(body).join() !== 'features') return reply(400, { error: 'Unexpected config mutation' });
    const parse = value => Object.fromEntries((value ?? '').split(',').filter(Boolean).map(flag => flag.split('=')));
    const oldFlags = parse(features);
    const newFlags = parse(body.features);
    // Match Proxmox: omitted -> explicit zero counts as a non-nesting change.
    for (const key of new Set([...Object.keys(oldFlags), ...Object.keys(newFlags)])) {
      if (key !== 'nesting' && oldFlags[key] !== newFlags[key]) return reply(403, { error: 'Changing other features requires root@pam' });
    }
    if (!['0', '1'].includes(newFlags.nesting)) return reply(400, { error: 'Expected explicit nesting value' });
    features = body.features;
    requests.at(-1).features = features;
    reply(200, { data: null });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const moduleDirectory = resolve(import.meta.dirname, '../modules/vm');
  const directory = await mkdtemp(join(moduleDirectory, '.terraform/nesting-api-'));
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}/api2/json`;
    await writeFile(join(directory, 'nesting.tftest.hcl'), `
mock_provider "proxmox" {}
${["enable", "noop", "disable", "drift", "remove", "preserve", "replace"].map(phase => `provider "restful" {
  alias = "${phase}"
  base_url = "${baseUrl}"
  security = { apikey = [{ in = "header", name = "Authorization", value = "PVEAPIToken=offline@pve!test=${phase}" }] }
}`).join("\n")}
variables {
  username = "enable"
  name = "plex"
  guest_type = "lxc"
  node_name = "pve"
  vm_id = 1009
  lxc_template = { file_id = "local:vztmpl/debian-test.tar.zst" }
  datastore_id = "local-lvm"
  network = { address = "10.77.0.38", gateway = "10.77.0.37", cidr = "10.77.0.36/30", vnet_id = "hsp1009" }
  protected_cidrs = ["192.168.1.0/24"]
  dns_servers = ["192.168.1.53"]
  ntp_servers = []
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbQ7fxCXpGk6DckT2PRXJ5w5pMR6qksY6hOyw4mftR1 test"]
}
run "enable" {
  providers = { proxmox = proxmox, restful = restful.enable }
  command = apply
  variables {
    nesting = true
    username = "enable"
  }
  assert {
    condition = restful_resource.nesting[0].output.features == "nesting=1"
    error_message = "Enable must survive real API read-back."
  }
}
run "no_op" {
  providers = { proxmox = proxmox, restful = restful.noop }
  command = plan
  variables {
    nesting = true
    username = "noop"
  }
  assert {
    condition = restful_resource.nesting[0].body.features == "nesting=1" && restful_resource.nesting[0].output.features == "nesting=1"
    error_message = "An unchanged container must retain nesting."
  }
}
run "disable" {
  providers = { proxmox = proxmox, restful = restful.disable }
  command = apply
  variables {
    nesting = false
    username = "disable"
  }
  assert {
    condition = restful_resource.nesting[0].output.features == "nesting=0"
    error_message = "Disable must send an explicit zero."
  }
}
run "repair_external_drift" {
  providers = { proxmox = proxmox, restful = restful.drift }
  command = apply
  variables {
    nesting = false
    username = "drift"
  }
  assert {
    condition = restful_resource.nesting[0].output.features == "nesting=0"
    error_message = "Refresh must detect and repair external nesting changes."
  }
}
run "repair_removed_features" {
  providers = { proxmox = proxmox, restful = restful.remove }
  command = apply
  variables {
    nesting = false
    username = "remove"
  }
  assert {
    condition = restful_resource.nesting[0].output.features == "nesting=0"
    error_message = "Removing all feature flags externally must be repaired."
  }
}
run "preserve_disabled_flags" {
  providers = { proxmox = proxmox, restful = restful.preserve }
  command = apply
  variables {
    nesting = true
    username = "preserve"
  }
  assert {
    condition = restful_resource.nesting[0].output.features == "fuse=0,keyctl=0,nesting=1"
    error_message = "Explicit zeros must be preserved without root-only mutations."
  }
}
run "container_replacement" {
  providers = { proxmox = proxmox, restful = restful.replace }
  command = apply
  variables {
    nesting = true
    username = "replace"
  }
  plan_options { replace = [proxmox_virtual_environment_container.this[0]] }
  assert {
    condition = restful_resource.nesting[0].output.features == "fuse=0,keyctl=0,nesting=1"
    error_message = "Replacing a container with the same CT ID must reapply nesting."
  }
}
`);
    let result;
    try {
      result = await exec('terraform', ['-chdir=modules/vm', 'test', `-test-directory=${relative(moduleDirectory, directory)}`, '-no-color'], { cwd: resolve(import.meta.dirname, '..'), timeout: 100_000, maxBuffer: 2_000_000 });
    } catch (error) {
      throw new Error(`${error.stdout ?? ''}\n${error.stderr ?? ''}`);
    }
    assert.match(result.stdout, /Success! 7 passed, 0 failed/);
    const writes = phase => requests.filter(request => request.method === 'PUT' && request.phase === phase).map(request => request.features);
    assert.deepEqual(writes('enable'), ['nesting=1']);
    assert.deepEqual(writes('noop'), []);
    assert.deepEqual(writes('disable'), ['nesting=0']);
    assert.deepEqual(writes('drift'), ['nesting=0']);
    assert.deepEqual(writes('remove'), ['nesting=0']);
    assert.deepEqual(writes('preserve'), ['fuse=0,keyctl=0,nesting=1']);
    assert.deepEqual(writes('replace'), ['fuse=0,keyctl=0,nesting=0', 'fuse=0,keyctl=0,nesting=1', 'fuse=0,keyctl=0,nesting=0']);
    assert.equal(requests.some(request => request.method === 'DELETE'), false);
    assert.equal(features, 'fuse=0,keyctl=0,nesting=0');
  } finally {
    await new Promise(resolve => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  }
});

const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const test = require('node:test');
const path = require('node:path');

const configPath = path.resolve(__dirname, '../docusaurus.config.js');

test('docs resolve the deployment domain in prose and copyable commands', () => {
  const markdown = 'Proxy: `http-proxy.{{HSP_DOMAIN}}`\n```sh\ncurl http://http-proxy.{{HSP_DOMAIN}}:3128\nexport HTTP_PROXY="${http_proxy}"\n```\n{{TF_VAR_pihole_password}}';
  const result = spawnSync(process.execPath, ['-e', `
    const config = require(${JSON.stringify(configPath)});
    process.stdout.write(config.markdown.preprocessor({fileContent: ${JSON.stringify(markdown)}, filePath: 'example.md'}));
  `], {encoding: 'utf8', env: {...process.env, HSP_DOMAIN: 'docs.example'}});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, 'Proxy: `http-proxy.docs.example`\n```sh\ncurl http://http-proxy.docs.example:3128\nexport HTTP_PROXY="${http_proxy}"\n```\n{{TF_VAR_pihole_password}}');
});

test('docs reject a domain that could inject shell commands into examples', () => {
  const result = spawnSync(process.execPath, ['-e', `require(${JSON.stringify(configPath)})`], {
    encoding: 'utf8', env: {...process.env, HSP_DOMAIN: 'example.com; echo unsafe'},
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /HSP_DOMAIN/);
});

test('changing the deployment domain invalidates compiled Markdown', () => {
  const versions = ['first.example', 'second.example'].map((domain) => {
    const result = spawnSync(process.execPath, ['-e', `
      const config = require(${JSON.stringify(configPath)});
      const plugin = config.plugins.map(create => create()).find(item => item.name === 'hsp-domain-cache');
      const patch = plugin.configureWebpack({cache: {type: 'filesystem', version: 'existing-version'}});
      process.stdout.write(patch.cache.version);
    `], {encoding: 'utf8', env: {...process.env, HSP_DOMAIN: domain}});
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /existing-version/);
    return result.stdout;
  });
  assert.notEqual(versions[0], versions[1]);
});

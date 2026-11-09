const assert = require('node:assert/strict');
const test = require('node:test');

const cases = [
  ['fix: correct a firewall rule', 'patch'],
  ['docs: update the deployment guide', 'patch'],
  ['Update documentation', 'patch'],
  ['feat: add a guest role', 'minor'],
  ['feat!: change the inventory format', 'major'],
  ['refactor: change the inventory\n\nBREAKING CHANGE: guest IDs are now required', 'major'],
];

for (const [message, expected] of cases) {
  test(`release type for ${message.split('\n')[0]}`, async () => {
    const {analyzeCommits} = await import('@semantic-release/commit-analyzer');
    const config = require('../release.config.cjs');
    const [, options] = config.plugins.find(([name]) => name === '@semantic-release/commit-analyzer');
    const actual = await analyzeCommits(options, {
      cwd: require('node:path').resolve(__dirname, '..'),
      commits: [{hash: 'test', message}],
      logger: {log() {}},
    });
    assert.equal(actual, expected);
  });
}

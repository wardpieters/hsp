module.exports = {
  branches: ['main'],
  repositoryUrl: 'https://github.com/wardpieters/hsp.git',
  tagFormat: 'v${version}',
  plugins: [
    ['@semantic-release/commit-analyzer', {
      preset: 'conventionalcommits',
      releaseRules: [
        {breaking: true, release: 'major'},
        {type: 'feat', release: 'minor'},
        // Every push with new commits should release, including docs and chores.
        {release: 'patch'},
      ],
    }],
    ['@semantic-release/release-notes-generator', {preset: 'conventionalcommits'}],
    ['@semantic-release/github', {
      successComment: false,
      failComment: false,
      failTitle: false,
      releasedLabels: false,
    }],
  ],
};

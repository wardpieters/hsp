const fs = require('node:fs/promises');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

exports.prepare = async (_options, {cwd, nextRelease}) => {
  const tag = nextRelease.gitTag;
  if (!/^v\d+\.\d+\.\d+$/.test(tag)) {
    throw new Error(`Invalid release tag: ${tag}`);
  }

  // Validate both guides before writing either one. Only published HSP module
  // sources are changed; the runnable Terraform examples keep local sources.
  const updates = await Promise.all(['README.md', 'examples/README.md'].map(async file => {
    const filePath = path.resolve(cwd, file);
    const content = await fs.readFile(filePath, 'utf8');
    let matches = 0;
    const updated = content.replace(
      /(git::https:\/\/github\.com\/wardpieters\/hsp\.git\/\/modules\/[\w-]+\?ref=)[^"\s&]+/g,
      (_match, source) => {
        matches += 1;
        return source + tag;
      },
    );
    if (!matches) {
      throw new Error(`No published HSP module references in ${file}`);
    }
    return {filePath, updated};
  }));
  await Promise.all(updates.map(({filePath, updated}) => fs.writeFile(filePath, updated)));

  // Build the updated guides before the Git plugin commits them and before
  // semantic-release creates the tag. A failed build must abort the release.
  const build = spawnSync('npm', ['run', 'build'], {cwd: path.join(cwd, 'website'), stdio: 'inherit'});
  if (build.error || build.status !== 0) {
    throw new Error('Documentation build failed during release preparation', {cause: build.error});
  }
};

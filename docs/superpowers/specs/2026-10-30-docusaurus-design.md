# Docusaurus documentation design

Convert the repository documentation into a local Docusaurus documentation site. Preserve the complete existing README, deployment guide (including the current working-tree edit), firewall reference, verification history, and six engineering records. Add an introduction and logical chapter indexes. The user explicitly requested execution without questions.

Use a docs-only classic Docusaurus application in `website/`, reading Markdown directly from the repository. Order chapters as platform overview, deployment, firewall and access, verification, and engineering records. Add chapter index pages linking to the original documents and their sections. Keep the original source paths and links usable on disk and in the site. Render `.md` as Markdown to preserve literal placeholders in historical documents. Enable strict broken-link and anchor checks.

Use the current checkout to retain the deployment edit. Keep all generated files and dependencies ignored. Provide reproducible npm commands, a lockfile, and a documentation build in CI. No infrastructure behavior changes or live deployment are part of this conversion.

A source-reading site avoids duplicated prose that could drift. Splitting or rewriting the existing guides would create unnecessary content changes; a separate hosted service is outside this repository conversion.

Verify a production build, chapter/document/anchor links, mobile navigation, source-content hashes, and the existing infrastructure checks. Source downloads must include only files explicitly linked by the docs, never private configuration or state.

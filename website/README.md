# Documentation website

This Docusaurus site reads the root `README.md`, `examples/README.md`, and the Markdown in `docs/` directly. The original guides and engineering records remain the source of truth; there is no content copy or synchronization step.

## Local development

Install Node.js 22.14 or later and npm, then run from the repository root:

```sh
make docs-install
make docs-start
```

Open `http://localhost:3000/hsp/`. Markdown edits reload automatically.

To build and preview the production site:

```sh
make docs-build
make docs-serve
```

The static output is in `website/build/`. CI builds the documentation separately from the infrastructure checks. Broken internal links and heading anchors fail the build.

Equivalent npm commands are `npm --prefix website ci`, `npm --prefix website start`, `npm --prefix website run build`, and `npm --prefix website run serve`.

## Content and navigation

- Set `HSP_DOMAIN=home.example.com` in the repository root's local `.env` to configure the domain shown in the deployed docs. An exported `HSP_DOMAIN` takes precedence; without either setting, the site uses `home.example.com`. Restart the development server or rebuild after changing it.
- Write `{{HSP_DOMAIN}}` in Markdown prose and code examples. Docusaurus substitutes the domain during compilation, so displayed and copied commands contain the resolved hostname and need no host-side variable or `.env`. Only this public setting is substituted; infrastructure credentials remain private. The setting controls documentation examples, while Terraform DNS configuration remains separate.
- `docs/introduction.md` is the site homepage.
- `docs/chapters/` contains the chapter indexes and links to guide sections.
- `website/sidebars.js` defines the chapter and document reading order.
- Existing documents stay at their original paths, including the six original design and implementation records in `docs/superpowers/`.
- The design and plan for this website conversion are excluded from the published documentation.
- Markdown files use CommonMark parsing so Terraform examples and historical planning placeholders do not need conversion to JSX.

## Releases and GitHub Pages

Every push to `main` runs `.github/workflows/release.yml`: install the locked dependencies, run the documentation and release-policy tests, build the site, create a version tag and GitHub release with semantic-release, then deploy the build to [the documentation website](https://wardpieters.github.io/hsp/). Failed tests or builds prevent both release and deployment. Pull requests continue to build through the validation workflow without publishing.

In the repository's **Settings → Pages → Build and deployment**, select **GitHub Actions** as the source. The workflow uses the built-in `GITHUB_TOKEN` to create releases and GitHub's Pages artifact deployment with OIDC; no personal access token or `gh-pages` branch is needed.

Release versions come from Git tags, starting at `v1.0.0` when there is no previous release. `feat:` commits produce a minor release; a `!` marker or `BREAKING CHANGE:` footer produces a major release. All other new commits produce a patch release, including documentation, maintenance, and commits without a Conventional Commits prefix. The highest applicable bump since the previous release wins. Use `npm --prefix website test` to verify these rules.

The configuration publishes GitHub releases only. It does not publish an npm package or commit generated version changes back to `main`; `website/package.json` is the private documentation toolchain, not the released Terraform module version. semantic-release's standard `[skip release]` / `[release skip]` commit markers still opt individual commits out of release analysis.

The production origin and `/hsp/` base path are configured in `website/docusaurus.config.js`. For another static host, update those settings and rebuild, then serve `website/build/` at the configured path.

The documentation build does not load Terraform variables, `.env`, state, plans, or credentials. Review the documentation and its examples before choosing a hosting audience.

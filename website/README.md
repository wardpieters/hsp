# Documentation website

This Docusaurus site reads the root `README.md` and the Markdown in `docs/` directly. The original guides and engineering records remain the source of truth; there is no content copy or synchronization step.

## Local development

Install Node.js 22 or later and npm, then run from the repository root:

```sh
make docs-install
make docs-start
```

Open `http://localhost:3000`. Markdown edits reload automatically.

To build and preview the production site:

```sh
make docs-build
make docs-serve
```

The static output is in `website/build/`. CI builds the documentation separately from the infrastructure checks. Broken internal links and heading anchors fail the build.

Equivalent npm commands are `npm --prefix website ci`, `npm --prefix website start`, `npm --prefix website run build`, and `npm --prefix website run serve`.

## Content and navigation

- Set `HSP_DOMAIN=home.ward.nl` in the repository root's local `.env` to configure the domain shown in the deployed docs. An exported `HSP_DOMAIN` takes precedence; without either setting, the site uses `home.example.com`. Restart the development server or rebuild after changing it.
- Write `{{HSP_DOMAIN}}` in Markdown prose and code examples. Docusaurus substitutes the domain during compilation, so displayed and copied commands contain the resolved hostname and need no host-side variable or `.env`. Only this public setting is substituted; infrastructure credentials remain private. The setting controls documentation examples, while Terraform DNS configuration remains separate.
- `docs/introduction.md` is the site homepage.
- `docs/chapters/` contains the chapter indexes and links to guide sections.
- `website/sidebars.js` defines the chapter and document reading order.
- Existing documents stay at their original paths, including the six original design and implementation records in `docs/superpowers/`.
- The design and plan for this website conversion are excluded from the published documentation.
- Markdown files use CommonMark parsing so Terraform examples and historical planning placeholders do not need conversion to JSX.

## Static hosting

Serve `website/build/` with any static web server. Before publishing, set `url` in `website/docusaurus.config.js` to the real site origin. The checked-in `https://hsp.example.com` value is a placeholder. If hosting under a subdirectory, also set `baseUrl` to that path, including its leading and trailing slash, and rebuild.

The documentation build does not load Terraform variables, `.env`, state, plans, or credentials. Review the documentation and its examples before choosing a hosting audience.

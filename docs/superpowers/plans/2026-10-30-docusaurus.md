# Docusaurus documentation implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan in the current session.

**Goal:** Present all existing repository documentation in Docusaurus with an introduction and logical chapter indexes.

**Architecture:** A docs-only Docusaurus classic app reads the existing Markdown directly. New chapter pages supply navigation without duplicating guide content.

**Tech Stack:** Docusaurus 3, React, Node.js >=22, npm.

**Spec:** docs/superpowers/specs/2026-10-30-docusaurus-design.md

## Global Constraints

- Preserve every original document and the current deployment edit.
- Work locally in this checkout; do not deploy infrastructure or publish externally.
- Ignore build output, caches, and node_modules.
- Fail the build on broken internal links and anchors.
- Keep private configuration and state out of the site.

## Review Focus

- Literal placeholders and fenced code in historical Markdown render correctly.
- Links between existing documents retain their anchors.
- Configuration source links resolve without exposing private files.
- Small screens retain usable chapter navigation and readable tables/code.
- All original docs appear once in the sidebar and remain unchanged.

### Task 1: Documentation site and chapter navigation

**Files:** Create `website/package.json`, `website/docusaurus.config.js`, `website/sidebars.js`, `website/src/css/custom.css`, `docs/introduction.md`, and `docs/chapters/*.md`.

- [x] Configure classic Docusaurus with docs at the site root and existing repository Markdown as its source.
- [x] Add an introduction, five chapter indexes, explicit sidebar ordering, and links to guide sections.
- [x] Install pinned dependencies and generate the npm lockfile.
- [x] Build with strict link checks; verify all original source hashes and any source downloads.

### Task 2: Contributor workflow and verification

**Files:** Modify `.gitignore`, `Makefile`, `.github/workflows/validate.yml`; create `website/README.md`.

- [x] Add local install/start/build/serve instructions and Make targets.
- [x] Add a separate CI job for the documentation build.
- [x] Verify production routes and responsive navigation in a browser.
- [x] Run `make check`, the documentation build, content preservation checks, and `git diff --check`.
- [x] Review the final changes and leave them ready for review in the current checkout.

## Verification record

- Production Docusaurus build passes with strict Markdown-link and anchor checks.
- All 18 content/index pages serve HTTP 200; the 404 page is also generated.
- All five linked Terraform/example downloads return HTTP 200 and match source bytes.
- All ten original Markdown documents retain the hashes captured before this conversion.
- Desktop and 390px mobile navigation, chapter links, and guide anchors checked in the browser.
- `make check` passes: 104 native Terraform tests and the real REST-provider loopback test.
- `git diff --check` passes.
- Independent review found a source-download URL defect caused by forced trailing slashes; removing that setting fixes all five downloads, verified by HTTP requests.
- Changes remain uncommitted in the current checkout for review, alongside the preserved pre-existing deployment edit.

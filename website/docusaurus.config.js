// @ts-check

const fs = require('node:fs');
const path = require('node:path');
const {parseEnv} = require('node:util');

// Read only the public documentation setting; never publish the rest of .env.
const envPath = path.resolve(__dirname, '../.env');
const localDomain = fs.existsSync(envPath)
  ? parseEnv(fs.readFileSync(envPath, 'utf8')).HSP_DOMAIN
  : undefined;
const hspDomain = process.env.HSP_DOMAIN ?? localDomain ?? 'home.example.com';
if (!/^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$/.test(hspDomain)) {
  throw new Error('HSP_DOMAIN must be a DNS domain containing letters, digits, hyphens, and dots.');
}

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Home self-hosting platform',
  tagline: 'Infrastructure, deployment, and access policies',
  url: 'https://hsp.example.com',
  baseUrl: '/',
  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',
  markdown: {
    format: 'detect',
    preprocessor: ({fileContent}) => fileContent.replaceAll('{{HSP_DOMAIN}}', hspDomain),
    hooks: {onBrokenMarkdownLinks: 'throw'},
    // Docusaurus maps a root README to `/`; reserve that route for the introduction.
    async parseFrontMatter({filePath, fileContent, defaultParseFrontMatter}) {
      const result = await defaultParseFrontMatter({filePath, fileContent});
      if (filePath === require.resolve('../README.md')) {
        result.frontMatter.slug = '/platform-guide';
      }
      return result;
    },
  },
  i18n: {defaultLocale: 'en', locales: ['en']},
  plugins: [function docsDomainCache() {
    return {
      name: 'hsp-domain-cache',
      configureWebpack(webpackConfig) {
        // Markdown preprocessing closes over the domain, which Webpack cannot
        // otherwise see when it reuses compiled documents from a previous build.
        if (!webpackConfig.cache || typeof webpackConfig.cache !== 'object') {
          return {};
        }
        return {cache: {version: `${webpackConfig.cache.version ?? ''}:hsp-domain=${hspDomain}`}};
      },
    };
  }],
  presets: [
    ['classic', {
      docs: {
        path: '..',
        routeBasePath: '/',
        include: ['README.md', 'examples/README.md', 'docs/**/*.md'],
        exclude: ['docs/superpowers/**/2026-10-30-docusaurus*.md'],
        sidebarPath: require.resolve('./sidebars.js'),
        showLastUpdateTime: false,
      },
      blog: false,
      pages: false,
      theme: {customCss: require.resolve('./src/css/custom.css')},
    }],
  ],
  themeConfig: {
    colorMode: {respectPrefersColorScheme: true},
    navbar: {
      title: 'HSP / Docs',
      items: [
        {to: '/', label: 'Introduction', position: 'left'},
        {type: 'docSidebar', sidebarId: 'docs', label: 'Chapters', position: 'left'},
        {type: 'doc', docId: 'docs/deployment', label: 'Deploy', position: 'right'},
      ],
    },
    footer: {
      style: 'dark',
      links: [{title: 'Documentation', items: [
        {label: 'Introduction', to: '/'},
        {label: 'Deployment', to: '/docs/chapters/deployment/'},
        {label: 'Firewall & access', to: '/docs/chapters/firewall/'},
        {label: 'Verification', to: '/docs/verification/'},
      ]}],
      copyright: 'Home self-hosting platform · Terraform infrastructure documentation',
    },
    tableOfContents: {minHeadingLevel: 2, maxHeadingLevel: 3},
    prism: {additionalLanguages: ['hcl', 'bash', 'json', 'diff']},
  },
};

module.exports = config;

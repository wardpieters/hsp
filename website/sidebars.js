// Keep the reading order explicit; engineering history follows the current guides.
/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
module.exports = {
  docs: [
    {type: 'doc', id: 'docs/introduction', label: 'Introduction'},
    {
      type: 'category', label: '1. Platform overview', collapsed: false,
      link: {type: 'doc', id: 'docs/chapters/platform'},
      items: [{type: 'doc', id: 'README', label: 'Platform guide'}],
    },
    {
      type: 'category', label: '2. Deployment',
      link: {type: 'doc', id: 'docs/chapters/deployment'},
      items: [
        {type: 'doc', id: 'docs/deployment', label: 'Deploying with Terraform'},
        {type: 'doc', id: 'docs/debian-setup', label: 'Debian guest setup'},
      ],
    },
    {
      type: 'category', label: '3. Firewall & access',
      link: {type: 'doc', id: 'docs/chapters/firewall'},
      items: [{type: 'doc', id: 'docs/firewall-roles', label: 'Guest roles and firewall rules'}],
    },
    {
      type: 'category', label: '4. Verification',
      link: {type: 'doc', id: 'docs/chapters/verification'},
      items: ['docs/verification'],
    },
    {
      type: 'category', label: '5. Engineering records',
      link: {type: 'doc', id: 'docs/chapters/engineering'},
      items: [
        {
          type: 'category', label: 'Design documents',
          link: {type: 'generated-index', title: 'Design documents',
            description: 'The original architecture and feature designs, in chronological order.',
            slug: '/engineering/designs'},
          items: [
            {type: 'doc', id: 'docs/superpowers/specs/2026-10-28-self-hosting-infrastructure-design', label: 'Self-hosting infrastructure'},
            {type: 'doc', id: 'docs/superpowers/specs/2026-10-30-lxc-support-design', label: 'LXC support'},
            {type: 'doc', id: 'docs/superpowers/specs/2026-10-30-lxc-nesting-api-design', label: 'LXC nesting API'},
          ],
        },
        {
          type: 'category', label: 'Implementation plans',
          link: {type: 'generated-index', title: 'Implementation plans',
            description: 'The original implementation plans and their verification steps.',
            slug: '/engineering/plans'},
          items: [
            {type: 'doc', id: 'docs/superpowers/plans/2026-10-28-self-hosting-infrastructure', label: 'Self-hosting infrastructure'},
            {type: 'doc', id: 'docs/superpowers/plans/2026-10-30-lxc-support', label: 'LXC support'},
            {type: 'doc', id: 'docs/superpowers/plans/2026-10-30-lxc-nesting-api', label: 'LXC nesting API'},
          ],
        },
      ],
    },
  ],
};

import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    {
      type: 'doc',
      id: 'intro',
      label: 'Documentation portal',
    },
    {
      type: 'category',
      label: 'Projects',
      items: [{ type: 'link', label: 'MetaDbDiff', href: '/metadbdiff/' }],
    },
  ],
  metadbdiffSidebar: [
    {
      type: 'category',
      label: 'MetaDbDiff',
      link: { type: 'doc', id: 'metadbdiff/index' },
      items: [
        'metadbdiff/introduction',
        {
          type: 'category',
          label: 'Getting Started',
          items: [
            'metadbdiff/getting-started',
          ],
        },
        {
          type: 'category',
          label: 'Guides',
          items: [
            'metadbdiff/guide-compare-schemas',
            'metadbdiff/guide-generate-ddl',
          ],
        },
        {
          type: 'category',
          label: 'Reference',
          items: [
            'metadbdiff/reference-api',
          ],
        },
        {
          type: 'category',
          label: 'Support',
          items: [
            'metadbdiff/troubleshooting',
          ],
        },
      ],
    },
  ],
};

export default sidebars;

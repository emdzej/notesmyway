import { defineConfig } from 'vitepress'

// Site config for notesmyway.emdzej.pl.
//
// Custom domain lives at docs/public/CNAME. Since Pages serves the
// site off a root domain, base stays '/' and no baseURL rewriting is
// needed.

const repo = 'https://github.com/emdzej/notesmyway'

export default defineConfig({
  title: 'Notes my Way',
  titleTemplate: ':title · Notes my Way',
  description:
    'Plain Markdown notes, your way. A notes app for Mac, iPhone and iPad that keeps every note as a .md file in a folder you choose.',

  cleanUrls: true,
  lastUpdated: true,
  metaChunk: true,

  head: [
    ['link', { rel: 'icon', type: 'image/png', href: '/favicon.png' }],
    ['link', { rel: 'apple-touch-icon', href: '/apple-touch-icon.png' }],
    ['meta', { name: 'theme-color', content: '#1a8fa8' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:site_name', content: 'Notes my Way' }],
    ['meta', { property: 'og:title', content: 'Notes my Way — plain Markdown notes, your way' }],
    ['meta', { property: 'og:description', content: 'A notes app for Mac, iPhone and iPad that keeps every note as a plain .md file.' }],
    ['meta', { property: 'og:url', content: 'https://notesmyway.emdzej.pl/' }],
  ],

  sitemap: {
    hostname: 'https://notesmyway.emdzej.pl',
  },

  themeConfig: {
    siteTitle: 'Notes my Way',
    logo: '/logo.png',

    nav: [
      { text: 'Overview', link: '/overview' },
      { text: 'Install', link: '/install' },
      { text: 'Guide', link: '/guide' },
      { text: 'Writing', link: '/markdown' },
      {
        text: 'Reference',
        items: [
          { text: 'Tables and formulas', link: '/tables' },
          { text: 'Themes', link: '/themes' },
          { text: 'Files and compatibility', link: '/compatibility' },
          { text: 'Roadmap', link: '/backlog' },
          { text: 'Source (GitHub)', link: repo },
        ],
      },
    ],

    sidebar: [
      {
        text: 'Introduction',
        collapsed: false,
        items: [
          { text: 'What is Notes my Way?', link: '/overview' },
          { text: 'Installation', link: '/install' },
        ],
      },
      {
        text: 'Using the app',
        collapsed: false,
        items: [
          { text: 'Notebooks and folders', link: '/guide#notebooks' },
          { text: 'Notes', link: '/guide#notes' },
          { text: 'Attachments', link: '/guide#attachments' },
          { text: 'Single files', link: '/guide#standalone-files' },
          { text: 'Settings', link: '/guide#settings' },
          { text: 'Keyboard shortcuts', link: '/guide#keyboard-shortcuts' },
        ],
      },
      {
        text: 'Writing',
        collapsed: false,
        items: [
          { text: 'Markdown in the editor', link: '/markdown' },
          { text: 'Source mode', link: '/markdown#source-mode' },
          { text: 'Frontmatter and tags', link: '/markdown#frontmatter' },
          { text: 'Links between notes', link: '/markdown#links' },
          { text: 'Image and link sizes', link: '/markdown#attributes' },
          { text: 'Tables', link: '/tables' },
          { text: 'Formulas in tables', link: '/tables#formulas' },
          { text: 'Themes', link: '/themes' },
        ],
      },
      {
        text: 'Reference',
        collapsed: false,
        items: [
          { text: 'Files and compatibility', link: '/compatibility' },
          { text: 'Roadmap', link: '/backlog' },
          { text: 'Support', link: '/support' },
          { text: 'Privacy', link: '/privacy' },
          { text: 'Source on GitHub', link: repo },
        ],
      },
    ],

    socialLinks: [{ icon: 'github', link: repo }],

    editLink: {
      pattern: `${repo}/edit/main/docs/:path`,
      text: 'Suggest an edit on GitHub',
    },

    search: {
      provider: 'local',
    },

    footer: {
      // TODO: add the license link once the repo has a LICENSE file.
      copyright: 'Copyright © 2026 <a href="https://emdzej.pl">Michał Jaskólski</a>',
    },

    outline: {
      level: [2, 3],
    },
  },
})

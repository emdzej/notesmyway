import { defineConfig } from 'vitepress'

// Site config for notesmyway.emdzej.pl.
//
// Custom domain lives at docs/public/CNAME. Since Pages serves the
// site off a root domain, base stays '/' and no baseURL rewriting is
// needed.

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
      { text: 'Feature guide', link: '/guide/' },
      { text: 'Why Notes my Way', link: '/overview' },
      { text: 'Get the app', link: '/get-the-app' },
      {
        text: 'More',
        items: [
          { text: 'Files and compatibility', link: '/compatibility' },
          { text: 'Roadmap', link: '/backlog' },
          { text: 'Support', link: '/support' },
          { text: 'Privacy', link: '/privacy' },
        ],
      },
    ],

    sidebar: [
      {
        text: 'Introduction',
        items: [
          { text: 'Why Notes my Way?', link: '/overview' },
          { text: 'Get the app', link: '/get-the-app' },
        ],
      },
      {
        text: 'Feature guide',
        items: [
          { text: 'Getting started', link: '/guide/' },
          { text: 'Notebooks and folders', link: '/guide/notebooks' },
          { text: 'Writing', link: '/guide/writing' },
          { text: 'Images and previews', link: '/guide/images' },
          { text: 'Tables and formulas', link: '/guide/tables' },
          { text: 'Themes and appearance', link: '/guide/themes' },
          { text: 'Settings and shortcuts', link: '/guide/settings' },
          { text: 'Spotlight, Shortcuts and widgets', link: '/guide/integration' },
        ],
      },
      {
        text: 'Reference',
        items: [
          { text: 'Files and compatibility', link: '/compatibility' },
          { text: 'Roadmap', link: '/backlog' },
          { text: 'Support', link: '/support' },
          { text: 'Privacy', link: '/privacy' },
        ],
      },
    ],

    search: {
      provider: 'local',
    },

    footer: {
      message: 'Coming soon to the App Store for iPhone, iPad and Mac.',
      copyright: 'Copyright © 2026 <a href="https://emdzej.pl">Michał Jaskólski</a>',
    },

    outline: {
      level: [2, 3],
    },
  },
})

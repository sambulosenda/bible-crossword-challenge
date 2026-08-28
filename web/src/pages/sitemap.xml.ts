import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { SITE } from '../consts';

// The sitemap is generated, not hand-written, so it can never drift from the
// pages that actually build. Every URL here must be indexable: /challenge/ and
// /404 are noindex, so they are deliberately absent.
//
// changefreq and priority are omitted on purpose — Google ignores both, and
// lastmod is omitted rather than stamped with the build date, which would claim
// every page changed on every deploy and get the whole file distrusted.
const STATIC_PATHS = [
  '/',
  '/puzzles/',
  '/puzzles/printable/',
  '/puzzles/old-testament/',
  '/puzzles/new-testament/',
  '/puzzles/christmas-and-easter/',
  '/puzzles/for-kids/',
  '/how-to-play/',
  '/press/',
  '/privacy/',
];

export const GET: APIRoute = async () => {
  const puzzles = await getCollection('puzzles');
  const paths = [
    ...STATIC_PATHS,
    ...puzzles.map((entry) => `/puzzles/${entry.id}/`).sort(),
  ];

  const body = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${paths.map((p) => `  <url><loc>${new URL(p, SITE).href}</loc></url>`).join('\n')}
</urlset>
`;

  return new Response(body, {
    headers: {
      'Content-Type': 'application/xml; charset=utf-8',
      'Cache-Control': 'public, max-age=3600',
    },
  });
};

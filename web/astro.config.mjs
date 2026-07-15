// @ts-check
import { defineConfig } from 'astro/config';

// Static site for Cloudflare Pages (build → dist/). Clean directory URLs
// (/how-to-play/, /puzzles/, /puzzles/david-and-goliath/, /challenge/). The old
// `.html` URLs are 301'd to these in public/_redirects so no inbound link
// breaks, and /challenge/ serves the universal-link landing page exactly.
export default defineConfig({
  site: 'https://biblecrosswordchallenge.com',
  trailingSlash: 'ignore',
});

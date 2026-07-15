import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

// Each themed puzzle landing page is one JSON entry. The filename is the slug,
// so david-and-goliath.json → /puzzles/david-and-goliath.html. String fields
// may contain inline HTML (<em>, <a>, curly quotes) and are rendered with
// set:html in the template.
const puzzles = defineCollection({
  loader: glob({ pattern: '*.json', base: './src/content/puzzles' }),
  schema: z.object({
    title: z.string(), // <title> / OG title
    heading: z.string(), // H1 (may contain &amp; etc.)
    reference: z.string(), // eyebrow, e.g. "1 Samuel 17"
    meta: z.string(), // meta chips, e.g. "15×15 grid · Easy · Ends on 1 Samuel 17:45"
    description: z.string(), // meta description
    prose: z.array(z.string()), // paragraphs, HTML allowed
    clues: z.array(
      z.object({ n: z.string(), text: z.string(), enum: z.string(), len: z.number() })
    ),
    verseText: z.string(),
    verseCite: z.string(),
    related: z.array(
      z.object({ href: z.string(), eyebrow: z.string(), name: z.string(), sub: z.string() })
    ),
  }),
});

export const collections = { puzzles };

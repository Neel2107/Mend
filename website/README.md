# Mend website

Astro site for the Mend landing page.

## Development

Run commands from this directory:

```sh
bun install
bun run dev
bun run check
bun run build
```

## Deployment

Set the Vercel project root to `website`. Vercel detects Astro and uses the
standard install and build settings. The production domain is
`mend.itsneel.com`.

The `/install` route serves the repository's current `Scripts/install-app.sh`
file, so the website installer and source installer cannot drift apart.

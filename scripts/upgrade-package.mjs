import { readFile, writeFile } from 'node:fs/promises';

const path = new URL('../package.json', import.meta.url);
const packageJson = JSON.parse(await readFile(path, 'utf8'));

// Preserve existing dependency versions from the recipient's repository.
packageJson.version = '1.1.0';
packageJson.description = 'Local MCP bridge for the Jev and Cloudflare Clef-Flash structured-decision APIs.';
packageJson.scripts = {
  ...packageJson.scripts,
  check: 'node --check src/index.mjs && node --check scripts/test-api.mjs && node --check scripts/test-clef-api.mjs',
  'test:clef-api': 'node scripts/test-clef-api.mjs',
};

await writeFile(path, `${JSON.stringify(packageJson, null, 2)}\n`, 'utf8');
console.log('package.json updated; existing dependency version declarations were preserved.');

const { chromium } = require('playwright');
const { join } = require('node:path');
const { pathToFileURL } = require('node:url');
const { writeFileSync } = require('node:fs');
const { createHash } = require('node:crypto');

async function main() {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 3 });
    await page.goto(pathToFileURL(join(__dirname, 'artwork.html')).href);
    await page.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all(Array.from(document.images, image => image.decode()));
    });
    const names = ['01-a-gentler-start', '02-a-little-company', '03-room-to-focus'];
    const checksums = [];
    for (const name of names) {
      const png = await page.locator(`[id="${name}"]`).screenshot({ path: join(__dirname, 'screenshots-en', `${name}.png`), type: 'png' });
      if (png.readUInt32BE(16) !== 1320 || png.readUInt32BE(20) !== 2868 || png[25] !== 2) {
        throw new Error(`${name}: expected 1320x2868 RGB PNG without alpha`);
      }
      checksums.push(`${createHash('sha256').update(png).digest('hex')}  ${name}.png`);
    }
    writeFileSync(join(__dirname, 'screenshots-en', 'SHA256SUMS'), `${checksums.join('\n')}\n`);
    await page.close();
    const overview = await browser.newPage({ viewport: { width: 1400, height: 1000 }, deviceScaleFactor: 1 });
    await overview.goto(pathToFileURL(join(__dirname, 'artwork.html')).href);
    await overview.evaluate(async () => {
      await document.fonts.ready;
      await Promise.all(Array.from(document.images, image => image.decode()));
    });
    await overview.locator('main').screenshot({ path: join(__dirname, 'contact-sheet.png') });
    console.log('Rendered and validated 3 RGB screenshots, 1320x2868, plus contact sheet.');
  } finally {
    await browser.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });

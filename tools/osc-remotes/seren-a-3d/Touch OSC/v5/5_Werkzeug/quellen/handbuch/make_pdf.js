const { chromium } = require('playwright');
const F = '/tmp/claude-0/-home-claude/1d4028fa-12da-5404-ac70-1ceecfe42680/scratchpad/fonts/node_modules/@fontsource/';
const ff = (fam, w, f, dir) => `@font-face{font-family:"${fam}";font-weight:${w};src:url("file://${F}${dir}/files/${f}.woff2") format("woff2")}`;
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  await p.route(/fonts\.(googleapis|gstatic)\.com/, r => r.abort());
  await p.goto('file:///home/claude/v3/handbuch/HANDBUCH.html');
  await p.addStyleTag({ content: [
    ff('Roboto',400,'roboto-latin-400-normal','roboto'), ff('Roboto',500,'roboto-latin-500-normal','roboto'), ff('Roboto',700,'roboto-latin-700-normal','roboto'),
    ff('Roboto Mono',400,'roboto-mono-latin-400-normal','roboto-mono'), ff('Roboto Mono',600,'roboto-mono-latin-600-normal','roboto-mono')].join('\n') });
  await p.evaluate(() => { localStorage.clear(); });
  await p.emulateMedia({ media: 'print' });
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(500);
  await p.pdf({ path: process.argv[2], preferCSSPageSize: true, printBackground: true });
  await b.close();
})();

// End-to-end check of the web build in headless Chrome, over the DevTools Protocol (Node 22+, no npm packages).
// It taps through the app like a user on a 390px-wide phone, reading the text from Flutter's semantics DOM.
//
// usage:  node tool/e2e.mjs <appUrl> [fake-camera.y4m]
//   appUrl         a web build made with --dart-define=DEMO=true, pointed at an asset-laravel
//                  with APP_DEMO=true and freshly seeded data (php artisan migrate:fresh --seed)
//   fake-camera    optional Y4M video for Chrome's fake webcam; its frames must show the QR for COM-64-0002
// env:    CHROME_PATH, E2E_PORT (default 9455), E2E_SHOTS (folder for screenshots, default: none),
//         E2E_THEME (light or dark; default: the browser's)
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const app = (process.argv[2] ?? 'http://127.0.0.1:8766').replace(/\/$/, '');
const fakeCamera = process.argv[3];
const CHROME = process.env.CHROME_PATH ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = Number(process.env.E2E_PORT ?? 9455);
const SHOTS = process.env.E2E_SHOTS;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const profile = mkdtempSync(join(tmpdir(), 'e2e-'));
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, '--window-size=800,900',
  '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
  ...(fakeCamera ? [`--use-file-for-fake-video-capture=${fakeCamera}`] : []),
  'about:blank',
], { stdio: 'ignore' });

let ws;
for (let i = 0; i < 50 && !ws; i++) {
  try {
    const target = await (await fetch(`http://127.0.0.1:${PORT}/json/new?about:blank`, { method: 'PUT' })).json();
    ws = new WebSocket(target.webSocketDebuggerUrl);
  } catch { await sleep(200); }
}
await new Promise((r) => ws.addEventListener('open', r, { once: true }));

let nextId = 0;
const pending = new Map();
const problems = [];
ws.addEventListener('message', (event) => {
  const msg = JSON.parse(event.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); return; }
  if (msg.method === 'Runtime.exceptionThrown') problems.push(`exception: ${msg.params.exceptionDetails.exception?.description ?? msg.params.exceptionDetails.text}`);
  if (msg.method === 'Runtime.consoleAPICalled' && msg.params.type === 'error') problems.push(`console.error: ${msg.params.args.map((a) => a.value ?? a.description).join(' ')}`);
});
const send = (method, params = {}) => new Promise((resolve) => { const id = ++nextId; pending.set(id, resolve); ws.send(JSON.stringify({ id, method, params })); });
const evaluate = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result?.result?.value;

await Promise.all(['Page.enable', 'Runtime.enable'].map((m) => send(m)));
await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 2, mobile: false });
if (process.env.E2E_THEME) await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: process.env.E2E_THEME }] });

// Every label Flutter exposes, each with the centre of its box. Text fields expose their label as aria-label.
const nodes = () => evaluate(`[...document.querySelectorAll('flt-semantics, input, textarea')].map((el) => {
  const r = el.getBoundingClientRect();
  return { text: (el.getAttribute('aria-label') || el.textContent || '').trim(), x: r.x + r.width / 2, y: r.y + r.height / 2, area: r.width * r.height };
}).filter((n) => n.text && n.area > 0)`);

async function find(text, timeout = 90000) {
  for (const end = Date.now() + timeout; Date.now() < end; await sleep(250)) {
    // An exact label beats one that starts with the text, which beats one that merely contains it.
    const rank = (n) => (n.text === text ? 0 : n.text.startsWith(text) ? 1 : 2);
    const hits = (await nodes()).filter((n) => n.text.includes(text)).sort((a, b) => rank(a) - rank(b) || a.area - b.area);
    if (hits.length) return hits[0];
  }
  throw new Error(`"${text}" never appeared. On screen: ${(await nodes()).map((n) => n.text).join(' | ')}`);
}

async function gone(text, timeout = 10000) {
  for (const end = Date.now() + timeout; Date.now() < end; await sleep(250)) {
    if (!(await nodes()).some((n) => n.text.includes(text))) return;
  }
  throw new Error(`"${text}" is still on screen`);
}

async function tap(text) {
  const { x, y } = await find(text);
  for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
  }
  await sleep(400);
}

let shot = 0;
async function screenshot(name) {
  if (!SHOTS) return;
  const { result } = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(join(SHOTS, `${String(++shot).padStart(2, '0')}-${name}.png`), Buffer.from(result.data, 'base64'));
}

const results = [];
// Each step starts where the last one left off, so after a failure the rest are skipped, not run blind.
async function step(name, fn) {
  if (results.some((r) => r.startsWith('FAIL'))) return results.push(`skip  ${name}`);
  try {
    await fn();
    results.push(`ok    ${name}`);
  } catch (error) {
    results.push(`FAIL  ${name}: ${error.message}`);
    await screenshot(`FAIL-${name.replace(/\W+/g, '-')}`);
  }
}

await send('Page.navigate', { url: `${app}/` });

await step('login screen offers the demo roles', async () => {
  await find('ทดลองใช้ เลือกบทบาท');
  await find('เจ้าหน้าที่พัสดุ');
  await screenshot('login');
});

await step('officer signs in and sees the scanner', async () => {
  await tap('เจ้าหน้าที่พัสดุ');
  await find('· เจ้าหน้าที่พัสดุ');
  await find('เปิดกล้องสแกน');
  await screenshot('scan');
});

await step('an approved loan offers ส่งมอบ only', async () => {
  await tap('AV-67-0037');
  await find('กล้องถ่ายภาพ Sony A7');
  await find('อนุมัติแล้ว');
  await find('ส่งมอบ');
  await gone('รับคืน', 1000);
  await screenshot('asset-approved');
});

await step('hand over flips it to on loan and offers รับคืน', async () => {
  await tap('ส่งมอบ');
  await find('ส่งมอบให้');
  await screenshot('hand-over-dialog');
  const buttons = (await nodes()).filter((n) => n.text === 'ส่งมอบ').sort((a, b) => b.y - a.y);
  for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x: buttons[0].x, y: buttons[0].y, button: 'left', clickCount: 1 });
  }
  await find('ส่งมอบแล้ว');
  await find('ถูกยืม');
  await find('รับคืน');
  await screenshot('handed-over');
});

await step('take it back as damaged', async () => {
  await tap('รับคืน');
  await find('สภาพตอนรับคืน');
  await tap('ชำรุด');
  await screenshot('return-sheet');
  await tap('ยืนยันรับคืน');
  await find('รับคืนแล้ว');
  await find('ชำรุด');
  await find('ตอนนี้ไม่มีรายการที่คุณทำกับชิ้นนี้ได้');
  await screenshot('returned-damaged');
});

await step('typing a lower-case tag finds it', async () => {
  await tap('สแกนชิ้นต่อไป');
  await tap('หรือพิมพ์รหัสทรัพย์สิน');
  await send('Input.insertText', { text: 'com-65-0010' });
  await tap('ดู');
  await find('จอภาพ Dell 24 นิ้ว');
  await find('ส่งซ่อม');
  await tap('สแกนชิ้นต่อไป');
});

if (fakeCamera) {
  await step('the camera reads a QR label and opens that asset', async () => {
    await tap('เปิดกล้องสแกน');
    await find('Notebook Dell Latitude 5450', 30000);
    await find('รับคืน');
    await screenshot('scanned-by-camera');
    await tap('สแกนชิ้นต่อไป');
    // The fake camera still shows the same label; it must not bounce straight back into the asset.
    await sleep(1500);
    await gone('Notebook Dell Latitude 5450', 500);
    await find('หรือพิมพ์รหัสทรัพย์สิน');
  });
}

await step('staff cannot see another department\'s asset', async () => {
  await tap('ออกจากระบบ');
  await tap('พนักงาน');
  await find('· พนักงาน');
  await tap('AV-67-0034');
  await find('ไม่พบรหัสนี้ หรือทรัพย์สินนี้ไม่ได้อยู่ในหน่วยงานของคุณ');
  await screenshot('staff-not-found');
  await tap('กลับไปสแกน');
});

await step('a QR link opens the asset while the app is open, still signed in', async () => {
  await send('Page.navigate', { url: `${app}/#/a/AV-67-0037` });
  await find('กล้องถ่ายภาพ Sony A7');
  await gone('รับคืน', 1000);
  await screenshot('opened-from-link');
});

await step('and from a fresh page load, like a phone camera opening the link', async () => {
  await send('Page.navigate', { url: 'about:blank' });
  await sleep(500);
  await send('Page.navigate', { url: `${app}/#/a/AV-67-0037` });
  await find('กล้องถ่ายภาพ Sony A7');
  await tap('สแกนชิ้นต่อไป');
  await find('หรือพิมพ์รหัสทรัพย์สิน');
});

await step('a signed-out visitor who opens a QR link picks a role and lands on that asset', async () => {
  await tap('ออกจากระบบ');
  await find('ทดลองใช้ เลือกบทบาท');
  await send('Page.navigate', { url: 'about:blank' });
  await sleep(500);
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }] });
  await send('Page.navigate', { url: `${app}/#/a/COM-64-0002` });
  await tap('เจ้าหน้าที่พัสดุ');
  await find('Notebook Dell Latitude 5450');
  await find('รับคืน');
  await screenshot('link-after-login-light');
});

results.forEach((line) => console.log(line));
if (problems.length) console.log(`\nbrowser errors:\n  ${problems.join('\n  ')}`);

ws.close();
chrome.kill();
await sleep(300);
rmSync(profile, { recursive: true, force: true });
process.exit(results.some((r) => r.startsWith('FAIL')) || problems.length ? 1 : 0);

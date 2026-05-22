#!/usr/bin/env node
import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';

const env = process.env;
const req = (n) => { if (!env[n]) throw new Error(`Missing env: ${n}`); return env[n]; };

const TOKEN        = req('DISCORD_BOT_TOKEN');
const CHANNEL_ID   = req('DISCORD_CHANNEL_ID');
const BRAND_NAME   = env.BRAND_NAME?.trim() || 'NEX Development';
const COLOR_HEX    = (env.EMBED_COLOR?.trim() || '#FF3B3B').replace(/^#/, '');
const REPO_OWNER   = req('REPO_OWNER');
const REPO_NAME    = req('REPO_NAME');
const REPO_FULL    = req('REPO_FULL');
const BRANCH       = env.REPO_DEFAULT_BRANCH?.trim() || 'main';
const TAG          = req('RELEASE_TAG');
const RELEASE_BODY = env.RELEASE_BODY || '';
const RELEASE_URL  = req('RELEASE_URL');
const PUBLISHED_AT = req('RELEASE_PUBLISHED_AT');

const sub = (tpl) => tpl
  ? tpl.replaceAll('{repo}', REPO_NAME).replaceAll('{owner}', REPO_OWNER).replaceAll('{tag}', TAG)
  : '';

const STORE_URL = (env.STORE_URL_OVERRIDE?.trim()) || sub(env.STORE_URL_TEMPLATE);
const DOCS_URL  = (env.DOCS_URL_OVERRIDE?.trim())  || sub(env.DOCS_URL_TEMPLATE);
const CFX_URL   = (env.CFX_URL_OVERRIDE?.trim())   || sub(env.CFX_URL_TEMPLATE);

const COLOR_INT = parseInt(COLOR_HEX, 16);

function detectBanner() {
  if (env.BANNER_OVERRIDE_URL?.trim()) return env.BANNER_OVERRIDE_URL.trim();
  const names = ['banner.png', 'banner.jpg', 'banner.jpeg', 'banner.gif', 'banner.webp'];
  for (const n of names) {
    if (existsSync(n)) return `https://raw.githubusercontent.com/${REPO_FULL}/${BRANCH}/${n}`;
  }
  return null;
}

function parseSections(body) {
  const out = { added: '', changed: '', fixed: '', notes: '', files: '' };
  const buf = { added: [], changed: [], fixed: [], notes: [], files: [] };
  let cur = null;
  for (const line of body.split(/\r?\n/)) {
    const h = line.match(/^#{1,3}\s+(.+?)\s*$/);
    if (h) {
      const s = h[1].toLowerCase().replace(/[^a-z0-9 ]/g, '').trim();
      if (s.startsWith('added'))                 cur = 'added';
      else if (s.startsWith('changed files'))    cur = 'files';
      else if (s.startsWith('changed'))          cur = 'changed';
      else if (s.startsWith('fixed'))            cur = 'fixed';
      else if (s.startsWith('note'))             cur = 'notes';
      else                                       cur = null;
      continue;
    }
    if (cur) buf[cur].push(line);
  }
  for (const k of Object.keys(out)) out[k] = buf[k].join('\n').replace(/^\n+|\n+$/g, '');
  return out;
}

function previousTag() {
  try {
    const tags = execSync('git tag --sort=-v:refname', { encoding: 'utf8' })
      .split('\n').map(t => t.trim()).filter(Boolean);
    const i = tags.indexOf(TAG);
    if (i >= 0 && i + 1 < tags.length) return tags[i + 1];
    if (i < 0 && tags.length > 0) return tags[0];
    return null;
  } catch { return null; }
}

function autoChangedFiles() {
  const prev = previousTag();
  if (!prev) return 'All files - complete reinstall required';
  let raw;
  try { raw = execSync(`git diff --name-only ${prev}..${TAG}`, { encoding: 'utf8' }); }
  catch { return 'All files - complete reinstall required'; }
  const files = raw.split('\n').map(f => f.trim()).filter(Boolean);
  if (files.length === 0) return null;
  const collapsed = new Set();
  for (const f of files) {
    if (f.startsWith('web/') || f === 'web') collapsed.add('web/*');
    else collapsed.add(f);
  }
  const list = [...collapsed].sort();
  if (list.length > 15) return 'All files - complete reinstall required';
  return list.join('\n');
}

function fmtDate(iso) {
  return new Date(iso).toLocaleDateString('en-US',
    { year: 'numeric', month: 'long', day: 'numeric' });
}

const sections = parseSections(RELEASE_BODY);
const bannerUrl = detectBanner();
const changedFilesText = sections.files?.trim() || autoChangedFiles();

const container = [];

const titleSection = {
  type: 9,
  components: [{ type: 10, content: '## Resource Update' }],
};
if (CFX_URL) {
  titleSection.accessory = {
    type: 2, style: 5, label: 'Cfx.re Portal', url: CFX_URL,
  };
}
container.push(titleSection);

container.push({
  type: 10,
  content: [
    `**Resource Name:** \`${REPO_NAME}\``,
    `**Version:** \`${TAG}\``,
    `**Release Date:** \`${fmtDate(PUBLISHED_AT)}\``,
  ].join('\n'),
});

if (bannerUrl) {
  container.push({ type: 12, items: [{ media: { url: bannerUrl } }] });
}

const blocks = [];
if (sections.added)   blocks.push(`### 🟢 Added\n${sections.added}`);
if (sections.changed) blocks.push(`### 🟡 Changed\n${sections.changed}`);
if (sections.fixed)   blocks.push(`### 🔴 Fixed\n${sections.fixed}`);
if (blocks.length) container.push({ type: 10, content: blocks.join('\n\n') });

if (changedFilesText) {
  container.push({
    type: 10,
    content: `### 📁 Changed Files\n\`\`\`\n${changedFilesText}\n\`\`\``,
  });
}

if (sections.notes) {
  container.push({ type: 10, content: `### 📝 Notes\n${sections.notes}` });
}

const buttons = [];
if (STORE_URL) buttons.push({ type: 2, style: 5, label: 'Buy Now',             url: STORE_URL });
if (DOCS_URL)  buttons.push({ type: 2, style: 5, label: 'Install Instructions', url: DOCS_URL });
buttons.push(  { type: 2, style: 5, label: 'Download Now', url: RELEASE_URL });
if (buttons.length) {
  container.push({ type: 14 });
  container.push({ type: 1, components: buttons });
}

const payload = {
  flags: 1 << 15,
  components: [{ type: 17, accent_color: COLOR_INT, components: container }],
};

const roleIds = (env.DISCORD_PING_ROLE_IDS || '')
  .split(',').map(s => s.trim()).filter(Boolean);
if (roleIds.length) {
  payload.content = roleIds.map(r => `<@&${r}>`).join(' ');
  payload.allowed_mentions = { parse: [], roles: roleIds };
}

const res = await fetch(`https://discord.com/api/v10/channels/${CHANNEL_ID}/messages`, {
  method: 'POST',
  headers: {
    'Authorization': `Bot ${TOKEN}`,
    'Content-Type': 'application/json',
    'User-Agent': `${BRAND_NAME}-ReleaseAnnouncer (https://github.com/${REPO_FULL})`,
  },
  body: JSON.stringify(payload),
});

if (!res.ok) {
  console.error('Discord API error', res.status, await res.text());
  console.error('Payload:', JSON.stringify(payload, null, 2));
  process.exit(1);
}

const msg = await res.json();
console.log(`Posted: https://discord.com/channels/@me/${CHANNEL_ID}/${msg.id}`);

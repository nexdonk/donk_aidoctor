#!/usr/bin/env node
// Detects a version bump in fxmanifest.lua between the previous push (BEFORE_SHA)
// and HEAD, and if found, writes release-notes.md and sets workflow outputs.
//
// Outputs (via $GITHUB_OUTPUT):
//   changed=true|false
//   tag=<vX.Y.Z>           (only if changed)
//   version=<X.Y.Z>        (only if changed)
//   prev_tag=<vA.B.C>      (latest existing tag before this, or empty)
//   published_at=<ISO>     (now)

import { execSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, appendFileSync } from 'node:fs';

function setOutput(name, value) {
  const file = process.env.GITHUB_OUTPUT;
  if (!file) { console.log(`OUTPUT ${name}=${value}`); return; }
  if (String(value).includes('\n')) {
    const delim = `EOF_${Math.random().toString(36).slice(2)}`;
    appendFileSync(file, `${name}<<${delim}\n${value}\n${delim}\n`);
  } else {
    appendFileSync(file, `${name}=${value}\n`);
  }
}

function readManifestVersion(path = 'fxmanifest.lua') {
  if (!existsSync(path)) return null;
  const c = readFileSync(path, 'utf8');
  const m = c.match(/^\s*version\s+['"]([^'"]+)['"]/m);
  return m ? m[1] : null;
}

function readManifestVersionAtRef(ref, path = 'fxmanifest.lua') {
  try {
    const c = execSync(`git show ${ref}:${path}`,
      { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
    const m = c.match(/^\s*version\s+['"]([^'"]+)['"]/m);
    return m ? m[1] : null;
  } catch { return null; }
}

const newVersion = readManifestVersion();
if (!newVersion) {
  console.log('No `version` field in fxmanifest.lua — skipping.');
  setOutput('changed', 'false');
  process.exit(0);
}

const beforeSha = process.env.BEFORE_SHA;
let prevVersion = null;
if (beforeSha && !/^0+$/.test(beforeSha)) {
  prevVersion = readManifestVersionAtRef(beforeSha);
}

if (!prevVersion) {
  console.log(`No previous version found at ${beforeSha || '(no BEFORE_SHA)'}. Bump version once after install to trigger.`);
  setOutput('changed', 'false');
  process.exit(0);
}

if (prevVersion === newVersion) {
  console.log(`Version unchanged (${newVersion}) — no release.`);
  setOutput('changed', 'false');
  process.exit(0);
}

const tag = newVersion.startsWith('v') ? newVersion : `v${newVersion}`;

const existingTags = execSync('git tag', { encoding: 'utf8' })
  .split('\n').map(t => t.trim()).filter(Boolean);
if (existingTags.includes(tag)) {
  console.log(`Tag ${tag} already exists — skipping release.`);
  setOutput('changed', 'false');
  process.exit(0);
}

const sortedTags = execSync('git tag --sort=-v:refname', { encoding: 'utf8' })
  .split('\n').map(t => t.trim()).filter(Boolean);
const prevTag = sortedTags[0] || null;

let commits = [];
try {
  const range = prevTag ? `${prevTag}..HEAD` : 'HEAD';
  const log = execSync(`git log ${range} --pretty=format:%s --no-merges`, { encoding: 'utf8' });
  commits = log.split('\n').map(c => c.trim()).filter(Boolean);
} catch (e) {
  console.error('git log failed:', e.message);
}

function categorize(raw) {
  const msg = raw.trim();
  // skip version-bump-only commits
  if (/^(bump|release)\b.*v?\d+\.\d+/i.test(msg)) return null;
  if (/^v?\d+\.\d+\.\d+$/.test(msg)) return null;
  if (/^chore.*version/i.test(msg)) return null;

  // conventional-commit prefix
  const conv = msg.match(/^(\w+)(\([^)]+\))?!?:\s*(.+)$/);
  let text = msg;
  let typeFromPrefix = null;
  if (conv) {
    typeFromPrefix = conv[1].toLowerCase();
    text = conv[3];
  }

  if (typeFromPrefix) {
    if (['feat', 'feature', 'add'].includes(typeFromPrefix))         return { cat: 'added',   text };
    if (['fix', 'bugfix', 'hotfix'].includes(typeFromPrefix))        return { cat: 'fixed',   text };
    return { cat: 'changed', text };
  }

  if (/^(add|added|adds|adding|new|create|created|introduce|introduced|implement|implemented|enable|enabled|support)\b/i.test(msg))
    return { cat: 'added', text: msg };
  if (/^(fix|fixed|fixes|fixing|bug|patch|patched|resolve|resolved|repair|repaired|correct|corrected)\b/i.test(msg))
    return { cat: 'fixed', text: msg };
  return { cat: 'changed', text: msg };
}

const buckets = { added: [], changed: [], fixed: [] };
for (const c of commits) {
  const r = categorize(c);
  if (!r) continue;
  const t = r.text.charAt(0).toUpperCase() + r.text.slice(1);
  buckets[r.cat].push(t);
}

let changedFiles = [];
try {
  const range = prevTag ? `${prevTag}..HEAD` : 'HEAD';
  const raw = execSync(`git diff --name-only ${range}`, { encoding: 'utf8' });
  changedFiles = raw.split('\n').map(f => f.trim()).filter(Boolean);
} catch {}

const collapsed = new Set();
for (const f of changedFiles) {
  if (f.startsWith('web/') || f === 'web') collapsed.add('web/*');
  else collapsed.add(f);
}
const fileList = [...collapsed].sort();

const sections = [];
if (buckets.added.length)   sections.push('## Added\n'   + buckets.added.map(t   => `- ${t}`).join('\n'));
if (buckets.changed.length) sections.push('## Changed\n' + buckets.changed.map(t => `- ${t}`).join('\n'));
if (buckets.fixed.length)   sections.push('## Fixed\n'   + buckets.fixed.map(t   => `- ${t}`).join('\n'));

if (fileList.length) {
  const body = fileList.length > 15
    ? 'All files - complete reinstall required'
    : fileList.join('\n');
  sections.push(`## Changed Files\n${body}`);
}

if (!sections.length) {
  sections.push('_Version bumped without categorizable changes._');
}

const notes = sections.join('\n\n');
writeFileSync('release-notes.md', notes);

console.log(`\n--- release-notes.md ---\n${notes}\n--- end ---\n`);

setOutput('changed', 'true');
setOutput('tag', tag);
setOutput('version', newVersion);
setOutput('prev_tag', prevTag || '');
setOutput('published_at', new Date().toISOString());

console.log(`OK  ${prevVersion} -> ${newVersion}  (tag ${tag})`);
console.log(`Commits considered: ${commits.length}`);
console.log(`  Added: ${buckets.added.length}, Changed: ${buckets.changed.length}, Fixed: ${buckets.fixed.length}`);

import { readdir, readFile, access } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const ignored = new Set([".git", "node_modules", ".logic-tests"]);
async function markdownFiles(folder) {
  const files = [];
  for (const entry of await readdir(folder, { withFileTypes: true })) {
    if (ignored.has(entry.name)) continue;
    const full = path.join(folder, entry.name);
    if (entry.isDirectory()) files.push(...await markdownFiles(full));
    else if (entry.name.endsWith(".md")) files.push(full);
  }
  return files;
}
const cache = new Map();
const withoutCode = text => text.replace(/^```[\s\S]*?^```.*$/gmu, "");
async function anchors(file) {
  if (cache.has(file)) return cache.get(file);
  const text = withoutCode(await readFile(file, "utf8"));
  const ids = new Set([...text.matchAll(/\b(?:id|name)="([^"]+)"/gu)].map(match => match[1]));
  const used = new Map();
  for (const match of text.matchAll(/^#{1,6}\s+(.+)$/gmu)) {
    const slug = match[1].toLowerCase().replace(/<[^>]*>/gu, "").replace(/[^\p{L}\p{M}\p{N}_\-\s]/gu, "").replace(/\s/gu, "-");
    const count = used.get(slug) ?? 0;
    used.set(slug, count + 1);
    ids.add(count ? slug + "-" + count : slug);
  }
  cache.set(file, ids);
  return ids;
}
let checked = 0;
let failures = 0;
for (const file of await markdownFiles(root)) {
  const text = withoutCode(await readFile(file, "utf8"));
  for (const match of text.matchAll(/!?\[[^\]]*\]\(([^)\s]+)\)/gu)) {
    if (/^(?:https?:|mailto:)/iu.test(match[1])) continue;
    checked++;
    const [relative, hash] = match[1].split("#");
    const target = path.resolve(path.dirname(file), decodeURIComponent(relative || path.basename(file)));
    try {
      await access(target);
      if (hash && target.endsWith(".md") && !(await anchors(target)).has(decodeURIComponent(hash))) {
        throw new Error("anchor missing");
      }
    } catch (error) {
      failures++;
      console.error(path.relative(root, file) + ": " + match[1] + " — " + error.message);
    }
  }
}
console.log(checked + " relative documentation links checked; " + failures + " errors");
if (failures) process.exitCode = 1;

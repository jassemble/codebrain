// Minimal TOON parser/serializer for codebrain's credential registry (M#11a).
//
// TOON ("Token-Oriented Object Notation") is a compact INI/TOML-subset designed
// to be more token-efficient than JSON for agent-consumed config files. This
// implementation handles only the subset codebrain needs:
//
//   # comment lines (preserved as header on serialize)
//   [section-name]
//   key = "string value"
//   key = 1234           (integer)
//   key = ["a", "b"]     (string array)
//   <blank lines ignored>
//
// Not supported: nested sections, multi-line strings, escape sequences inside
// strings (other than \\ and \"), comments inside sections (header-only).
//
// Used by:
//   commands/brain/creds.md  → /brain:creds {list,show,add,remove,forget-all}
//
// Single source of truth — keep this small. If TOON proves operationally
// shaky, swap to TOML/JSON in v0.3; the file is internal-only (regenerated
// on every write) so no operator migration is needed.

'use strict';

const fs = require('fs');

// --- Parser -----------------------------------------------------------------

function parse(content) {
  const out = { _header: [], _sections: {} };
  let currentSection = null;
  const lines = content.split('\n');

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const line = raw.trim();

    if (line === '') continue;

    if (line.startsWith('#')) {
      // Comments before the first section go into the header (preserved on round-trip)
      if (currentSection === null) {
        out._header.push(raw);
      }
      continue;
    }

    const sectionMatch = line.match(/^\[([^\]]+)\]$/);
    if (sectionMatch) {
      currentSection = sectionMatch[1];
      if (!out._sections[currentSection]) {
        out._sections[currentSection] = {};
      }
      continue;
    }

    const kvMatch = line.match(/^([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(.+)$/);
    if (kvMatch) {
      if (currentSection === null) {
        // Key-value outside any section is an error — skip with a warning
        // (callers can inspect _errors if they care; for now, silently drop)
        continue;
      }
      const key = kvMatch[1];
      const rawValue = kvMatch[2].trim();
      out._sections[currentSection][key] = parseValue(rawValue);
      continue;
    }

    // Unrecognized line — skip silently. Strict parsing would throw; codebrain
    // prefers tolerance + lint-time detection of malformed entries.
  }

  return out;
}

function parseValue(raw) {
  // String: "..."
  if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
    return raw
      .slice(1, -1)
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, '\\');
  }
  // Array: ["a", "b", ...]
  if (raw.startsWith('[') && raw.endsWith(']')) {
    const inner = raw.slice(1, -1).trim();
    if (inner === '') return [];
    // Simple split — no escaped commas inside strings supported. Acceptable
    // for the credential-store use case where array values are slug-style.
    return inner.split(',').map(part => parseValue(part.trim()));
  }
  // Integer
  if (/^-?\d+$/.test(raw)) {
    return parseInt(raw, 10);
  }
  // Anything else: return as string (bare identifiers, dates without quotes, etc.)
  return raw;
}

// --- Serializer -------------------------------------------------------------

function serialize(obj, headerLines) {
  const lines = [];

  // Header (comment block) — use provided or fall back to obj._header
  const headers = headerLines || obj._header || [];
  for (const h of headers) {
    lines.push(h);
  }
  if (headers.length > 0) lines.push('');

  // Sections — sorted for deterministic output
  const sections = obj._sections || {};
  const sectionNames = Object.keys(sections).sort();

  for (let i = 0; i < sectionNames.length; i++) {
    const name = sectionNames[i];
    lines.push(`[${name}]`);
    const section = sections[name];
    const keys = Object.keys(section).sort();
    for (const k of keys) {
      lines.push(`${k} = ${serializeValue(section[k])}`);
    }
    // Blank line between sections (but not after the last one)
    if (i < sectionNames.length - 1) lines.push('');
  }

  return lines.join('\n') + '\n';
}

function serializeValue(v) {
  if (typeof v === 'number') return String(v);
  if (Array.isArray(v)) {
    return '[' + v.map(serializeValue).join(', ') + ']';
  }
  // String — quote + escape
  const s = String(v);
  const escaped = s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  return `"${escaped}"`;
}

// --- Convenience: read/write file ------------------------------------------

function readFile(path) {
  if (!fs.existsSync(path)) return null;
  const content = fs.readFileSync(path, 'utf8');
  return parse(content);
}

function writeFile(path, obj, headerLines) {
  const content = serialize(obj, headerLines);
  fs.writeFileSync(path, content);
  try {
    fs.chmodSync(path, 0o600);
  } catch {
    // chmod may fail on Windows; the agent procedure (commands/brain/creds.md
    // Cr5) documents the platform-specific equivalent (icacls on Windows).
  }
}

module.exports = { parse, serialize, parseValue, serializeValue, readFile, writeFile };

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

const archiveUrl = new URL(
  "../public/downloads/Shakespeare-latest.zip",
  import.meta.url,
);
const checksumUrl = new URL(`${archiveUrl.href}.sha256`);

test("download checksum matches the staged release archive", async () => {
  const [archive, checksumFile] = await Promise.all([
    readFile(archiveUrl),
    readFile(checksumUrl, "utf8"),
  ]);
  const expected = checksumFile.trim().split(/\s+/)[0];
  const actual = createHash("sha256").update(archive).digest("hex");

  assert.match(expected, /^[0-9a-f]{64}$/);
  assert.equal(actual, expected);
  assert.match(checksumFile, /\bShakespeare-latest\.zip\s*$/);
});

import assert from "node:assert/strict";
import test from "node:test";
import { compareVersions, validateAdvance, validateManifest } from "./release-state.mjs";

function manifest(version, buildNumber) {
  return {
    version,
    buildNumber,
    archiveKey: `releases/v${version}/Shakespeare.zip`,
    sha256: "a".repeat(64),
  };
}

test("compares two- and three-component versions numerically", () => {
  assert.equal(compareVersions("1.10.0", "1.9.9"), 1);
  assert.equal(compareVersions("2.0", "2.0.0"), 0);
  assert.equal(compareVersions("1.2.2", "1.2.3"), -1);
});

test("requires both version and build number to advance", () => {
  assert.doesNotThrow(() => validateAdvance(manifest("1.2.3", 12), manifest("1.3.0", 13)));
  assert.throws(() => validateAdvance(manifest("1.2.3", 12), manifest("1.2.3", 13)), /version/);
  assert.throws(() => validateAdvance(manifest("1.2.3", 12), manifest("1.3.0", 12)), /build/);
});

test("ties archive identity to the manifest version", () => {
  const value = manifest("1.2.3", 12);
  value.archiveKey = "releases/v9.9.9/Shakespeare.zip";
  assert.throws(() => validateManifest(value), /does not match/);
});

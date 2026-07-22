import fs from "node:fs";
import { pathToFileURL } from "node:url";

export function parseVersion(value) {
  if (typeof value !== "string" || !/^\d+\.\d+(?:\.\d+)?$/.test(value)) {
    throw new Error(`invalid release version: ${String(value)}`);
  }
  return value.split(".").map(Number);
}

export function compareVersions(left, right) {
  const a = parseVersion(left);
  const b = parseVersion(right);
  for (let index = 0; index < 3; index += 1) {
    const difference = (a[index] ?? 0) - (b[index] ?? 0);
    if (difference !== 0) return Math.sign(difference);
  }
  return 0;
}

export function extractToolVersion(value) {
  if (typeof value !== "string") throw new Error("tool version output is not text");
  const matches = [...value.matchAll(/(?:^|[^0-9])(\d+\.\d+\.\d+)(?=$|[^0-9])/g)]
    .map((match) => match[1]);
  const versions = [...new Set(matches)];
  if (versions.length !== 1) {
    throw new Error(`expected one semantic version in tool output, found ${versions.length}`);
  }
  return versions[0];
}

export function validateManifest(value) {
  if (!value || typeof value !== "object") throw new Error("release manifest is not an object");
  parseVersion(value.version);
  if (!Number.isSafeInteger(value.buildNumber) || value.buildNumber <= 0) {
    throw new Error("release build number must be a positive integer");
  }
  if (!/^releases\/v\d+\.\d+(?:\.\d+)?\/Shakespeare\.zip$/.test(value.archiveKey)) {
    throw new Error("release archive key is invalid");
  }
  if (value.archiveKey !== `releases/v${value.version}/Shakespeare.zip`) {
    throw new Error("release archive key does not match its version");
  }
  if (!/^[0-9a-f]{64}$/.test(value.sha256)) throw new Error("release checksum is invalid");
  return value;
}

export function validateAdvance(previous, intended) {
  validateManifest(previous);
  validateManifest(intended);
  if (compareVersions(intended.version, previous.version) <= 0) {
    throw new Error(
      `version ${intended.version} must be newer than published version ${previous.version}`,
    );
  }
  if (intended.buildNumber <= previous.buildNumber) {
    throw new Error(
      `build ${intended.buildNumber} must be newer than published build ${previous.buildNumber}`,
    );
  }
}

function readJSON(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [command, ...args] = process.argv.slice(2);
  try {
    if (command === "extract-tool-version" && args.length === 1) {
      console.log(extractToolVersion(args[0]));
    } else if (command === "validate-advance" && args.length === 2) {
      validateAdvance(readJSON(args[0]), readJSON(args[1]));
      console.log("Release metadata advances monotonically.");
    } else {
      throw new Error(
        "usage: release-state.mjs extract-tool-version OUTPUT | "
          + "validate-advance PREVIOUS INTENDED",
      );
    }
  } catch (error) {
    console.error(`Release metadata rejected: ${error.message}`);
    process.exit(1);
  }
}

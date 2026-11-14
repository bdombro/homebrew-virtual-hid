import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { $ } from "bun";
import {
  applyBump, binaryPath, buildReleaseArchive, type Bump, errorMessage, formulaPath, key,
  promoteChangelog, readBinaryTarget, readVersion, releaseFormulaUrl, releaseRepo, renderFormula, root,
} from "./formula-shared.ts";

export function parseOptions(args: string[]): { bump: Bump; dryRun: boolean } {
  const bumps = args.filter((arg): arg is Bump => arg === "major" || arg === "minor" || arg === "patch");
  if (bumps.length !== 1 || args.some((arg) => !["major", "minor", "patch", "--dry-run"].includes(arg))) {
    throw new Error("Usage: just release <major|minor|patch> [--dry-run]");
  }
  return { bump: bumps[0], dryRun: args.includes("--dry-run") };
}

async function main(): Promise<void> {
  process.chdir(root);
  const options = parseOptions(process.argv.slice(2));
  const current = readVersion();
  const version = applyBump(current, options.bump);
  const tag = `v${version}`;
  const changelogPath = join(root, "CHANGELOG.md");
  const { changelog, notes } = promoteChangelog(
    readFileSync(changelogPath, "utf8"), version, new Date().toISOString().slice(0, 10),
  );
  if (options.dryRun) {
    console.log(`[dry-run] ${current} -> ${version}: test, update VERSION/CHANGELOG.md, CMake build, archive ${key}.zip, update Formula/${key}.rb, commit, tag ${tag}, push origin, publish to ${releaseRepo}. Nothing changed.`);
    return;
  }

  const top = (await $`git rev-parse --show-toplevel`.quiet().text()).trim();
  if (top !== root) throw new Error("Run releases from the independent macos-input repository.");
  await $`git rev-parse --verify HEAD`.quiet();
  const origin = (await $`git remote get-url origin`.quiet().text()).trim();
  if (![ `https://github.com/${releaseRepo}`, `https://github.com/${releaseRepo}.git`, `git@github.com:${releaseRepo}.git` ].includes(origin)) {
    throw new Error(`origin must point to ${releaseRepo}.`);
  }
  const branch = (await $`git symbolic-ref --short HEAD`.quiet().text()).trim();
  const localTag = await $`git show-ref --verify --quiet ${`refs/tags/${tag}`}`.nothrow().quiet();
  if (localTag.exitCode === 0) throw new Error(`${tag} already exists locally.`);
  if (localTag.exitCode !== 1) throw new Error(`Cannot check local tag ${tag}.`);
  const remoteTag = await $`git ls-remote --exit-code origin ${`refs/tags/${tag}`}`.nothrow().quiet();
  if (remoteTag.exitCode === 0) throw new Error(`${tag} already exists on origin.`);
  if (remoteTag.exitCode !== 2) throw new Error(`Cannot check remote tag ${tag}: ${remoteTag.stderr.toString()}`);
  await $`gh repo view ${releaseRepo} --json nameWithOwner`.quiet();
  await $`just test`;

  writeFileSync(join(root, "VERSION"), `${version}\n`);
  writeFileSync(changelogPath, changelog);
  await $`just build`;
  const target = await readBinaryTarget(binaryPath);
  const { archivePath, sha256 } = await buildReleaseArchive(binaryPath);
  mkdirSync(join(root, "Formula"), { recursive: true });
  writeFileSync(formulaPath, renderFormula(version, releaseFormulaUrl(version), sha256, target));
  const notesPath = join(root, "dist", "release-notes.md");
  writeFileSync(notesPath, notes);

  await $`git add -A`;
  await $`git commit -m ${`chore: release ${tag}`}`;
  await $`git tag -a ${tag} -m ${tag}`;
  await $`git push --atomic origin ${`HEAD:refs/heads/${branch}`} ${`refs/tags/${tag}`}`;
  await $`gh release create ${tag} ${archivePath} --repo ${releaseRepo} --verify-tag --title ${tag} --notes-file ${notesPath}`;
  console.log(`Released ${tag}`);
}

if (import.meta.main) {
  await main().catch((error: unknown) => {
    console.error(`Release stopped: ${errorMessage(error)}\nInspect the local Git state and GitHub before retrying; completed steps are not rolled back.`);
    process.exitCode = 1;
  });
}

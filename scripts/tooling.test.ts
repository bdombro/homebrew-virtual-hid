import { afterEach, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildReleaseArchive, promoteChangelog, renderFormula, root } from "./formula-shared.ts";
import { parseOptions } from "./release.ts";

const fixtures: string[] = [];

afterEach(() => {
  for (const path of fixtures.splice(0)) rmSync(path, { recursive: true, force: true });
});

function fixture(): string {
  const path = mkdtempSync(join(tmpdir(), "macos-input-tooling-"));
  fixtures.push(path);
  cpSync(join(root, "scripts"), join(path, "scripts"), { recursive: true });
  writeFileSync(join(path, "VERSION"), "1.2.3\n");
  writeFileSync(join(path, "CHANGELOG.md"), "# Changelog\n\n## [Unreleased]\n\n### Added\n\n- New input.\n");
  return path;
}

test("promotes only unreleased notes and preserves older releases", () => {
  const old = "## [1.0.0] - 2026-01-01\n\n- Earlier input.\n";
  const { changelog, notes } = promoteChangelog(`# Changelog\n\n## [Unreleased]\n\n- New input.\n\n${old}`, "1.1.0", "2026-11-13");
  expect(notes).toBe("- New input.\n");
  expect(changelog).toContain("## [Unreleased]\n\n## [1.1.0] - 2026-11-13\n\n- New input.");
  expect(changelog.endsWith(old)).toBe(true);
});

test("refuses missing, duplicate, or empty unreleased sections", () => {
  for (const content of ["# Changelog", "## [Unreleased]\n\n## [1.0.0]\n\n- Old.", "## [Unreleased]\n- New.\n## [Unreleased]\n- More."]) {
    expect(() => promoteChangelog(content, "1.0.0", "2026-11-13")).toThrow();
  }
});

test("release options reject ambiguous bumps and unknown arguments", () => {
  for (const args of [[], ["minor", "patch"], ["patch", "unexpected"], ["patch", "--force"]]) {
    expect(() => parseOptions(args)).toThrow();
  }
});

test("dry-run works offline and leaves source files and directory contents unchanged", () => {
  const path = fixture();
  const before = readdirSync(path);
  const version = readFileSync(join(path, "VERSION"), "utf8");
  const changelog = readFileSync(join(path, "CHANGELOG.md"), "utf8");
  const result = Bun.spawnSync([process.execPath, join(path, "scripts/release.ts"), "minor", "--dry-run"]);
  expect(result.exitCode).toBe(0);
  expect(result.stdout.toString()).toContain("1.2.3 -> 1.3.0");
  expect(readFileSync(join(path, "VERSION"), "utf8")).toBe(version);
  expect(readFileSync(join(path, "CHANGELOG.md"), "utf8")).toBe(changelog);
  expect(readdirSync(path)).toEqual(before);
});

test("publication requires confirmation before Git or build operations", () => {
  const path = fixture();
  const result = Bun.spawnSync([process.execPath, join(path, "scripts/release.ts"), "patch"], { stdin: "ignore" });
  expect(result.exitCode).toBe(1);
  expect(result.stderr.toString()).toContain("pass --yes");
  expect(readFileSync(join(path, "VERSION"), "utf8")).toBe("1.2.3\n");
});

test("release zip contains only the executable and its hash matches actual bytes", async () => {
  const path = fixture();
  const binary = join(path, "macos-input");
  writeFileSync(binary, "#!/bin/sh\nexit 0\n", { mode: 0o755 });
  const { archivePath } = await buildReleaseArchive(binary);
  const stale = join(path, "stale.txt");
  writeFileSync(stale, "must not ship\n");
  execFileSync("zip", ["-j", archivePath, stale]);
  const rebuilt = await buildReleaseArchive(binary);
  expect(execFileSync("unzip", ["-Z", "-1", archivePath], { encoding: "utf8" })).toBe("macos-input\n");
  expect(rebuilt.sha256).toBe(createHash("sha256").update(readFileSync(archivePath)).digest("hex"));
});

test("formula constrains native builds and safely quotes local URLs", () => {
  const formula = renderFormula("1.2.3", 'file:///tmp/odd"#{name}/macos-input.zip', "a".repeat(64), {
    architecture: "arm64", minimumMacOS: "27.2",
  });
  expect(formula).toContain('MacOS.full_version >= MacOSVersion.new("27.2")');
  expect(formula).toContain("depends_on arch: :arm64");
  expect(formula).toContain('odd\\"\\#{name}');
  expect(formula).not.toContain("Authorization");
  expect(renderFormula("1.2.3", "https://example.invalid/input.zip", "a".repeat(64), {
    architecture: "universal", minimumMacOS: "14.0",
  })).not.toContain("depends_on arch:");
});

test("failed Homebrew install restores the release formula and clears its backup", () => {
  const path = fixture();
  mkdirSync(join(path, "Formula"));
  mkdirSync(join(path, "dist"));
  mkdirSync(join(path, "bin"));
  writeFileSync(join(path, "Formula/macos-input.rb"), "original release formula\n");
  writeFileSync(join(path, "dist/macos-input"), "fixture binary", { mode: 0o755 });
  writeFileSync(join(path, "bin/xcrun"), `#!/bin/sh
case "$1" in
  lipo) echo arm64 ;;
  vtool) echo '    minos 14.0' ;;
  *) exit 99 ;;
esac
`, { mode: 0o755 });
  writeFileSync(join(path, "bin/brew"), `#!/bin/sh
case "$1" in
  --repository) printf '%s\\n' "$TEST_BREW_ROOT" ;;
  list) exit 0 ;;
  install) echo 'fixture install failure' >&2; exit 17 ;;
  *) exit 99 ;;
esac
`, { mode: 0o755 });
  const result = Bun.spawnSync([process.execPath, join(path, "scripts/dev-formula.ts"), "install"], {
    env: { ...process.env, PATH: `${path}/bin:${process.env.PATH}`, TEST_BREW_ROOT: join(path, "brew") },
  });
  expect(result.exitCode).toBe(1);
  expect(result.stderr.toString()).toContain("fixture install failure");
  expect(readFileSync(join(path, "Formula/macos-input.rb"), "utf8")).toBe("original release formula\n");
  expect(existsSync(join(path, "Formula/.staging/formula.json"))).toBe(false);
});

test("quick reinstall uses the installed keg when no production formula exists yet", () => {
  const path = fixture();
  for (const directory of ["dist", "bin", "keg/bin"]) mkdirSync(join(path, directory), { recursive: true });
  writeFileSync(join(path, "dist/macos-input"), "updated binary");
  writeFileSync(join(path, "keg/bin/macos-input"), "old binary");
  writeFileSync(join(path, "bin/brew"), `#!/bin/sh
case "$1" in
  list) echo bdombro/macos-input/macos-input ;;
  --prefix)
    test "$2" = --installed && test "$3" = macos-input || exit 99
    printf '%s\\n' "$TEST_BREW_PREFIX" ;;
  *) exit 99 ;;
esac
`, { mode: 0o755 });
  const result = Bun.spawnSync([process.execPath, join(path, "scripts/dev-formula.ts"), "reinstall"], {
    env: { ...process.env, PATH: `${path}/bin:${process.env.PATH}`, TEST_BREW_PREFIX: join(path, "keg") },
  });
  expect(result.exitCode).toBe(0);
  expect(readFileSync(join(path, "keg/bin/macos-input"), "utf8")).toBe("updated binary");
});

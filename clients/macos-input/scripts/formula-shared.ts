import { createHash } from "node:crypto";
import { existsSync, readFileSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { $ } from "bun";

export const key = "macos-input";
export const releaseRepo = "bdombro/homebrew-virtual-hid";
export const managerAppPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app";
export const clientDir = join(import.meta.dir, "..");
export const root = join(clientDir, "..", "..");
export const binaryPath = join(clientDir, "dist", key);
export const formulaPath = join(root, "Formula", `${key}.rb`);

export function errorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  if (error instanceof Error && "stderr" in error && Buffer.isBuffer(error.stderr) && error.stderr.length) {
    return `${message}\n${error.stderr.toString().trim()}`;
  }
  return message;
}

export interface BinaryTarget {
  architecture: "arm64" | "x86_64" | "universal";
  minimumMacOS: string;
}

export function readVersion(): string {
  const version = readFileSync(join(clientDir, "VERSION"), "utf8").trim();
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) {
    throw new Error("VERSION must contain a major.minor.patch version.");
  }
  return version;
}

export async function runCommand(description: string, command: $.ShellPromise) {
  console.log(`==> ${description}`);
  return await command.quiet(false);
}

export async function readBinaryTarget(path: string): Promise<BinaryTarget> {
  const architectures = (await runCommand(
    `xcrun lipo -archs ${path}`, $`xcrun lipo -archs ${path}`,
  )).stdout.toString().trim().split(/\s+/);
  let architecture: BinaryTarget["architecture"];
  if (architectures.length === 1 && architectures[0] === "arm64") architecture = "arm64";
  else if (architectures.length === 1 && architectures[0] === "x86_64") architecture = "x86_64";
  else if (architectures.length === 2 && architectures.includes("arm64") && architectures.includes("x86_64")) {
    architecture = "universal";
  } else throw new Error(`Unsupported binary architectures: ${architectures.join(", ")}`);

  const build = (await runCommand(
    `xcrun vtool -show-build ${path}`, $`xcrun vtool -show-build ${path}`,
  )).stdout.toString();
  const versions = [...build.matchAll(/^\s+minos (\d+\.\d+(?:\.\d+)?)\s*$/gm)].map((match) => match[1]);
  if (!versions.length) throw new Error("Cannot determine the binary's minimum macOS version.");
  versions.sort((a, b) => a.localeCompare(b, "en", { numeric: true }));
  return { architecture, minimumMacOS: versions[versions.length - 1] };
}

export async function buildReleaseArchive(path: string): Promise<{ archivePath: string; sha256: string }> {
  const archivePath = `${path}.zip`;
  if (existsSync(archivePath)) {
    console.log(`==> Removing existing archive ${archivePath}`);
    unlinkSync(archivePath);
  }
  await runCommand(`zip -j -9 ${archivePath} ${path}`, $`zip -j -9 ${archivePath} ${path}`);
  const sha256 = createHash("sha256").update(readFileSync(archivePath)).digest("hex");
  return { archivePath, sha256 };
}

export function renderFormula(version: string, url: string, sha256: string, target: BinaryTarget): string {
  const setupInstructions = readFileSync(join(clientDir, "resources", "driver-setup.txt"), "utf8")
    .trimEnd().split("\n").map((line) => line ? `      ${line}` : "").join("\n");
  // JSON strings are valid Ruby literals; escape Ruby's interpolation separately.
  const quote = (value: string) => JSON.stringify(value).replaceAll("#{", "\\#{");
  const architecture = target.architecture === "universal"
    ? ""
    : `  depends_on arch: :${target.architecture === "arm64" ? "arm64" : "intel"}\n`;
  return `class MacosInput < Formula
  desc "Send keyboard and mouse input through Karabiner's virtual HID driver"
  homepage "https://github.com/${releaseRepo}"
  url ${quote(url)}
  version ${quote(version)}
  sha256 ${quote(sha256)}

  class MinimumMacOSRequirement < Requirement
    fatal true
    satisfy(build_env: false) { OS.mac? && MacOS.full_version >= MacOSVersion.new("${target.minimumMacOS}") }

    def message
      "macos-input requires macOS ${target.minimumMacOS} or newer."
    end
  end

  depends_on :macos
  depends_on MinimumMacOSRequirement
${architecture}
  def install
    bin.install "${key}"
  end

  def caveats
    if File.exist?("${managerAppPath}")
      return <<~EOS
        Live input needs sudo, or membership in the virtual-hid group. To join it,
        run this once:
          sudo dseditgroup -o edit -a "$USER" -t user virtual-hid
          sudo dsmemberutil flushcache
      EOS
    end

    <<~'EOS'
${setupInstructions}
    EOS
  end

  test do
    assert_match "macos-input #{version}", shell_output("#{bin}/${key} --version")
    assert_equal "validated cmd+h\\n", shell_output("#{bin}/${key} --dry-run key cmd+h")
    assert_equal "validated move\\n", shell_output("#{bin}/${key} --dry-run move percent 50 50")
  end
end
`;
}

export function releaseFormulaUrl(version: string): string {
  return `https://github.com/${releaseRepo}/releases/download/v${version}/${key}.zip`;
}

export type Bump = "major" | "minor" | "patch";

export function applyBump(version: string, bump: Bump): string {
  const parts = version.split(".").map(Number);
  if (bump === "major") return `${parts[0] + 1}.0.0`;
  if (bump === "minor") return `${parts[0]}.${parts[1] + 1}.0`;
  return `${parts[0]}.${parts[1]}.${parts[2] + 1}`;
}

export function promoteChangelog(content: string, version: string, date: string): { changelog: string; notes: string } {
  const heading = /^## \[Unreleased\][ \t]*$/gm;
  const matches = [...content.matchAll(heading)];
  if (matches.length !== 1) throw new Error("CHANGELOG.md must have exactly one ## [Unreleased] heading.");
  const match = matches[0];
  const body = content.slice(match.index + match[0].length).split(/^## /m)[0].trim();
  if (!body) throw new Error("Add release notes under ## [Unreleased] before releasing.");
  return {
    changelog: content.replace(heading, `## [Unreleased]\n\n## [${version}] - ${date}`),
    notes: `${body}\n`,
  };
}

import {
  chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, readFileSync,
  realpathSync, symlinkSync, unlinkSync, writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { $ } from "bun";
import {
  binaryPath, buildReleaseArchive, errorMessage, formulaName, formulaPath, key,
  readBinaryTarget, readVersion, releaseRepo, renderFormula, root, tap,
} from "./formula-shared.ts";

const staging = join(root, "Formula", ".staging");
const backupPath = join(staging, "formula.json");
process.chdir(root);

async function localTapPath(): Promise<string> {
  const repository = (await $`brew --repository`.quiet().text()).trim();
  const [owner, name] = tap.split("/");
  return join(repository, "Library", "Taps", owner, `homebrew-${name}`);
}

function isLocalTap(path: string): boolean {
  const status = lstatSync(path, { throwIfNoEntry: false });
  return !!status?.isSymbolicLink() && realpathSync(path) === realpathSync(root);
}

async function installFormula(local = false): Promise<void> {
  const installed = (await $`brew list --formula --full-name`.quiet().text()).trim().split("\n");
  const env = { ...process.env, ...(local ? { HOMEBREW_NO_AUTO_UPDATE: "1" } : {}) };
  if (installed.includes(formulaName)) await $`brew reinstall --formula ${formulaName}`.env(env);
  else await $`brew install --formula ${formulaName}`.env(env);
  await $`brew test ${formulaName}`;
}

function reset(): void {
  if (!existsSync(backupPath)) throw new Error("No staged formula to restore.");
  const saved: unknown = JSON.parse(readFileSync(backupPath, "utf8"));
  if (typeof saved !== "object" || saved === null || !("formula" in saved)
      || (saved.formula !== null && typeof saved.formula !== "string")) {
    throw new Error(`Invalid formula backup: ${backupPath}`);
  }
  if (saved.formula === null) {
    if (existsSync(formulaPath)) unlinkSync(formulaPath);
  } else writeFileSync(formulaPath, saved.formula);
  unlinkSync(backupPath);
}

async function installLocal(): Promise<void> {
  if (existsSync(backupPath)) throw new Error("A formula is already staged; run bun scripts/dev-formula.ts reset.");
  const target = await readBinaryTarget(binaryPath);
  const { archivePath, sha256 } = await buildReleaseArchive(binaryPath);
  const path = await localTapPath();
  if (lstatSync(path, { throwIfNoEntry: false })) {
    if (!isLocalTap(path)) throw new Error(`Tap already exists at ${path}; untap it explicitly before using this checkout.`);
  } else {
    mkdirSync(dirname(path), { recursive: true });
    symlinkSync(root, path, "dir");
  }
  mkdirSync(staging, { recursive: true });
  writeFileSync(backupPath, JSON.stringify({
    formula: existsSync(formulaPath) ? readFileSync(formulaPath, "utf8") : null,
  }), { flag: "wx" });
  try {
    writeFileSync(formulaPath, renderFormula(readVersion(), pathToFileURL(archivePath).href, sha256, target));
    await installFormula(true);
  } finally {
    reset();
  }
}

async function main(): Promise<void> {
  if (process.argv.length !== 3) throw new Error("Usage: bun scripts/dev-formula.ts install|reset|reinstall|production|uninstall");
  switch (process.argv[2]) {
    case "install":
      await installLocal();
      break;
    case "reset":
      reset();
      break;
    case "reinstall": {
      const installed = (await $`brew list --formula --full-name`.quiet().text()).trim().split("\n");
      if (!installed.includes(formulaName)) throw new Error("Run just install-local first.");
      const prefix = (await $`brew --prefix --installed ${key}`.quiet().text()).trim();
      const destination = join(prefix, "bin", key);
      if (!existsSync(destination)) throw new Error("Run just install-local first.");
      copyFileSync(binaryPath, destination);
      chmodSync(destination, 0o755);
      break;
    }
    case "production": {
      const path = await localTapPath();
      if (isLocalTap(path)) unlinkSync(path);
      await $`brew tap ${tap} ${`https://github.com/${releaseRepo}.git`}`;
      await $`git -C ${path} pull --ff-only`;
      await installFormula();
      break;
    }
    case "uninstall": {
      const installed = (await $`brew list --formula --full-name`.quiet().text()).trim().split("\n");
      if (installed.includes(formulaName)) await $`brew uninstall --formula ${formulaName}`;
      else console.log(`${formulaName} is not installed.`);
      break;
    }
    default:
      throw new Error("Usage: bun scripts/dev-formula.ts install|reset|reinstall|production|uninstall");
  }
}

if (import.meta.main) {
  await main().catch((error: unknown) => {
    console.error(`macos-input Homebrew: ${errorMessage(error)}`);
    process.exitCode = 1;
  });
}

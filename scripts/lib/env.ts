import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

/** Repo root (scripts/ lives one level below it). */
export const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
export const ENV_PATH = resolve(REPO_ROOT, ".env");

let loaded = false;

/** Load the git-ignored repo-root .env into process.env (Node's built-in loader, no dependency). */
export function loadEnv(): void {
  if (loaded) return;
  loaded = true;
  if (existsSync(ENV_PATH)) process.loadEnvFile(ENV_PATH);
}

/** Read a required env var. The error names the variable, never its value. */
export function requireEnv(name: string): string {
  loadEnv();
  const v = process.env[name];
  if (v === undefined || v === "") {
    throw new Error(`Missing ${name} in .env. Copy .env.example to .env and fill it in (or run: pnpm accounts create).`);
  }
  return v;
}

export function optionalEnv(name: string, fallback: string): string {
  loadEnv();
  const v = process.env[name];
  return v === undefined || v === "" ? fallback : v;
}

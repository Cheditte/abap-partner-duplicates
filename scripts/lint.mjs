import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execute = promisify(execFile);
const root = fileURLToPath(new URL("../", import.meta.url));
const cli = fileURLToPath(new URL("../node_modules/@abaplint/cli/abaplint", import.meta.url));
const configurations = new Map([["700", "abaplint.json"], ["758", "abaplint.v758.json"]]);

try {
  const requested = process.argv.slice(2);
  if (requested.length > 1 || (requested.length === 1 && !configurations.has(requested[0]))) {
    throw new Error("Usage: node scripts/lint.mjs [700|758]");
  }
  const selected = requested.length === 0 ? [...configurations.values()] : [configurations.get(requested[0])];
  const gate = fileURLToPath(new URL("./check-classic.mjs", import.meta.url));
  const gateResult = await execute(process.execPath, [gate], { cwd: root, windowsHide: true });
  process.stdout.write(gateResult.stdout);
  process.stderr.write(gateResult.stderr);
  for (const configuration of selected) {
    const { stdout, stderr } = await execute(process.execPath, [cli, configuration], {
      cwd: root, windowsHide: true, maxBuffer: 8 * 1024 * 1024,
    });
    process.stdout.write(stdout);
    process.stderr.write(stderr);
  }
} catch (error) {
  if (error.stdout) process.stdout.write(error.stdout);
  if (error.stderr) process.stderr.write(error.stderr);
  console.error(error.message ?? error);
  process.exitCode = 1;
}

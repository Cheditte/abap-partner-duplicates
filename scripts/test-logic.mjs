import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, writeFile, copyFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execute = promisify(execFile);
const root = fileURLToPath(new URL("../", import.meta.url));
const coreRevision = "f735eed652288c8ed85b3083a187cc3e7e4a9b97";

function requiredMatch(text, expression, label) {
  const match = text.match(expression);
  if (!match) throw new Error(`Cannot extract ${label}; update the logic-test harness for the changed report structure`);
  return match[0];
}

function classPart(source, name, kind) {
  return requiredMatch(source, new RegExp(`CLASS ${name} ${kind}\\b[\\s\\S]*?ENDCLASS\\.`, "iu"), `${name} ${kind}`);
}

function method(implementation, name) {
  return requiredMatch(implementation, new RegExp(`  METHOD ${name}\\.[\\s\\S]*?  ENDMETHOD\\.`, "iu"), `${name} implementation`);
}

/** Copy selected static declarations and unchanged method bodies, excluding SAP I/O methods. */
function staticClass(source, name, methods) {
  const definition = classPart(source, name, "DEFINITION");
  const implementation = classPart(source, name, "IMPLEMENTATION");
  const declarations = methods.map((methodName) => requiredMatch(definition,
    new RegExp(`    CLASS-METHODS ${methodName}\\b[\\s\\S]*?\\.`, "iu"), `${name}=>${methodName} declaration`));
  return `CLASS ${name} DEFINITION FINAL. PUBLIC SECTION.\n${declarations.join("\n")}\nENDCLASS.\n`
    + `CLASS ${name} IMPLEMENTATION.\n${methods.map((name_) => method(implementation, name_)).join("\n\n")}\nENDCLASS.`;
}

async function run(args, cwd, filename) {
  try {
    const { stdout, stderr } = await execute(process.execPath, args, { cwd, windowsHide: true, maxBuffer: 8 * 1024 * 1024 });
    await writeFile(path.join(cwd, filename), stdout + stderr);
    process.stdout.write(stdout);
    process.stderr.write(stderr);
    return stdout;
  } catch (error) {
    const output = (error.stdout ?? "") + (error.stderr ?? "");
    await writeFile(path.join(cwd, filename), output);
    process.stderr.write(output);
    throw error;
  }
}

try {
  const report = await readFile(path.join(root, "src/zche_dupl_find.prog.abap"), "utf8");
  const parts = [
    "TYPE-POOLS abap.\nTYPES: bu_partner TYPE c LENGTH 10, bu_partnerrole TYPE c LENGTH 6, bu_group TYPE c LENGTH 4, bptaxtype TYPE c LENGTH 4.",
    requiredMatch(report, /INTERFACE lif_dupl\.[\s\S]*?ENDINTERFACE\./iu, "shared types"),
    classPart(report, "lcx_error", "DEFINITION"), classPart(report, "lcx_error", "IMPLEMENTATION"),
    staticClass(report, "lcl_text", ["get", "num"]),
    ...[...report.matchAll(/CLASS ltc_\w+ DEFINITION DEFERRED\./giu)].map((match) => match[0]),
  ];
  for (const name of ["lcl_tax_id", "lcl_normalizer", "lcl_matcher"]) {
    parts.push(classPart(report, name, "DEFINITION"), classPart(report, name, "IMPLEMENTATION"));
  }
  parts.push(staticClass(report, "lcl_finder", ["apply_decisions", "add_tax_id_findings"]));
  parts.push(staticClass(report, "lcl_app", ["check_settings"]));
  const testStart = report.search(/CLASS ltc_\w+ DEFINITION\b(?!\s+DEFERRED\b)/iu);
  const testEnd = report.search(/^INITIALIZATION\./mu);
  if (testStart < 0 || testEnd <= testStart) throw new Error("Cannot locate the report's test section");
  const tests = report.slice(testStart, testEnd);
  const expected = [...tests.matchAll(/^\s*METHODS\s+\w+\s+FOR TESTING\b/gmu)].length;
  if (expected === 0) throw new Error("No test methods found");

  const runs = path.join(root, ".logic-tests/runs");
  await mkdir(runs, { recursive: true });
  const stage = await mkdtemp(path.join(runs, "run-"));
  const source = path.join(stage, "src");
  await mkdir(source);
  console.log(`Logic-test evidence: ${stage}`);
  await writeFile(path.join(stage, "source-manifest.json"), JSON.stringify({
    source: "src/zche_dupl_find.prog.abap", sha256: createHash("sha256").update(report).digest("hex"),
    expectedTests: expected, openAbapCore: coreRevision,
  }, null, 2));
  await writeFile(path.join(source, "zcl_dupl_harness.clas.locals_imp.abap"), parts.join("\n\n"));
  await writeFile(path.join(source, "zcl_dupl_harness.clas.testclasses.abap"), tests);
  await writeFile(path.join(source, "zcl_dupl_harness.clas.abap"),
    "CLASS zcl_dupl_harness DEFINITION PUBLIC FINAL CREATE PUBLIC. ENDCLASS.\nCLASS zcl_dupl_harness IMPLEMENTATION. ENDCLASS.\n");
  await copyFile(path.join(root, "tests/logic/zcl_dupl_harness.clas.xml"), path.join(source, "zcl_dupl_harness.clas.xml"));
  const configuration = JSON.parse(await readFile(path.join(root, "tests/logic/abap_transpile.json"), "utf8"));
  if (configuration.libs?.[0]?.ref !== coreRevision) throw new Error("Unexpected library revision");
  await writeFile(path.join(stage, "abap_transpile.json"), JSON.stringify(configuration, null, 2));
  const transpiler = path.join(root, "node_modules/@abaplint/transpiler-cli/abap_transpile");
  const buildOutput = await run([transpiler], stage, "transpile.log");
  if (!buildOutput.includes(`commit: ${coreRevision}`)) throw new Error("Pinned library revision not confirmed by transpiler");
  const output = await run([path.join(stage, "output/index.mjs")], stage, "runtime.log");
  const executed = [...output.matchAll(/: running /gu)].length;
  if (executed !== expected) throw new Error(`Expected ${expected} tests, executed ${executed}`);
  console.log(`${executed} transpiled logic tests passed. SAP acceptance remains required.`);
} catch (error) {
  console.error(error.message ?? error);
  process.exitCode = 1;
}

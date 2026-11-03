import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { checkClassicSyntax } from "./lib/classic-syntax.mjs";

try {
  const source = await readFile(fileURLToPath(new URL("../src/zche_dupl_find.prog.abap", import.meta.url)), "utf8");
  const issues = checkClassicSyntax(source);
  source.split(/\r?\n/u).forEach((line, index) => {
    if ([...line].length > 72) issues.push({ line: index + 1, message: "Source exceeds 72 columns; classic SE38 uploads can truncate it" });
  });
  for (const issue of issues) console.error(`zche_dupl_find.prog.abap:${issue.line}: ${issue.message}`);
  if (issues.length > 0) process.exitCode = 1;
  else console.log("Classic ABAP compatibility gate passed");
} catch (error) {
  console.error(error.message ?? error);
  process.exitCode = 1;
}

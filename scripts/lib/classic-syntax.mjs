import core from "@abaplint/core";

const { Registry, MemoryFile, Expressions, BuiltIn } = core;

/** Extra project compatibility checks for forms that v700 abaplint can accept. */
export function checkClassicSyntax(source) {
  // Parse with current grammar so later syntax remains visible to the gate.
  const registry = new Registry().addFile(new MemoryFile("zclassic.prog.abap", source)).parse();
  const issues = [];
  for (const object of registry.getObjects()) {
    for (const file of object.getABAPFiles?.() ?? []) {
      for (const statement of file.getStatements()) {
        const code = statement.concatTokensWithoutStringsAndComments();
        const line = statement.getStart().getRow();
        const add = (message) => issues.push({ line, message });
        if (/\b(?:DATA|FINAL|FIELD-SYMBOL)\s*\(/iu.test(code)) add("Inline declarations are outside the classic 7.00 target");
        if (/\b(?:NEW|VALUE|CONV|CAST|COND|SWITCH|CORRESPONDING|REDUCE|FILTER|EXACT)\s+(?:#|[\w=>~-]+)\s*\(/iu.test(code)) {
          add("Constructor expressions are outside the classic 7.00 target");
        }
        if (/\bWITH\s+EMPTY\s+KEY\b/iu.test(code)) add("WITH EMPTY KEY is outside the classic 7.00 target");
        if (/&&/u.test(code)) add("String chaining with && is outside the classic 7.00 target");
        if (/[\w>)]\s*\[(?=\s*[^\s\]])/u.test(code)) add("Table expressions are outside the classic 7.00 target");
        if (statement.findAllExpressionsRecursive(Expressions.StringTemplate).length > 0) {
          add("String templates are outside the classic 7.00 target");
        }
        for (const parameter of statement.findAllExpressionsRecursive(Expressions.MethodCallParam)) {
          for (const call of parameter.findAllExpressionsRecursive(Expressions.MethodCallChain)) {
            const text = call.concatTokensWithoutStringsAndComments();
            const unqualified = text.match(/^(\w+)\s*\(/u)?.[1];
            // Built-in functions are checked by the versioned abaplint pass.
            if (unqualified && BuiltIn.searchBuiltin(unqualified)) continue;
            add(`Evaluate a method call into a variable before passing it as an argument: ${text}`);
          }
        }
      }
    }
  }
  return issues.filter((issue, index, all) => all.findIndex((other) => other.line === issue.line && other.message === issue.message) === index);
}

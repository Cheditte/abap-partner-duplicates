import { test } from "node:test";
import assert from "node:assert/strict";
import { checkClassicSyntax } from "../scripts/lib/classic-syntax.mjs";

const gate = (source) => checkClassicSyntax(`REPORT zclassic.\n${source}`);

test("classic separate method evaluation is accepted", () => {
  assert.deepEqual(gate("DATA lv TYPE i. lv = inner( ). outer( iv = lv )."), []);
});
test("nested local method call is rejected", () => {
  assert.ok(gate("DATA lv TYPE i. lv = outer( iv = inner( ) ).").some((issue) => issue.message.includes("before passing")));
});
test("nested static and instance calls are rejected", () => {
  assert.ok(gate("cl_aunit_assert=>assert_equals( act = lo_cut->calculate( ) exp = 1 ).").length > 0);
});
test("a multiline nested call is rejected", () => {
  assert.ok(gate("outer(\n iv = lcl_cut=>calculate( )\n ).").length > 0);
});
test("builtin functions in arguments remain allowed", () => {
  assert.deepEqual(gate("DATA lv TYPE i. lv = outer( iv = strlen( text ) )."), []);
});
test("comments and quoted examples do not trigger the gate", () => {
  assert.deepEqual(gate('* DATA(lv) = NEW #( ).\nDATA lv TYPE string. lv = `NEW #( ) && table[ 1 ]`. " outer( inner( ) )'), []);
});
test("inline declarations are rejected", () => {
  assert.ok(gate("DATA(lv) = 1.").some((issue) => issue.message.includes("Inline")));
});
test("constructors are rejected", () => {
  assert.ok(gate("DATA lv TYPE string. lv = CONV string( 1 ).").some((issue) => issue.message.includes("Constructor")));
});
test("templates and chaining are rejected", () => {
  assert.ok(gate("DATA lv TYPE string. lv = |abc| && `def`.").some((issue) => issue.message.includes("templates")));
});
test("table expressions are rejected", () => {
  assert.ok(gate("DATA lv TYPE i. lv = lt_values[ 1 ].").some((issue) => issue.message.includes("Table expressions")));
});
test("empty keys are rejected", () => {
  assert.ok(gate("DATA lt TYPE STANDARD TABLE OF string WITH EMPTY KEY.").some((issue) => issue.message.includes("EMPTY KEY")));
});

// Empty square brackets copy an internal-table body in classic ABAP.
test("classic table-body assignments remain allowed", () => {
  assert.deepEqual(gate("target = source[]. target = source[ ]."), []);
});

// Regression cases for the REVIEW.md rules in tools/content-validate.mjs. Exits non-zero if any case misbehaves.
//   node tools/content-review-test.mjs
// Each case copies content/ and tools/ to a temporary directory, edits REVIEW.md there and runs the validator on the
// copy, so the repository itself is never touched.
import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { repoRoot } from "./content-lib.mjs";

const review = readFileSync(join(repoRoot, "content/REVIEW.md"), "utf8");
const row = id => review.split("\n").find(line => line.startsWith(`| ${id} |`));
const cells = line => line.slice(1, -1).split("|").map(cell => cell.trim());
const format = cellList => `| ${cellList.join(" | ")} |`;
/** Returns the row `id` with the given cells replaced (0 ID, 1 Pack, 2 Version, 3 SHA-256, 4 Reviewer). */
const edit = (id, changes) => format(cells(row(id)).map((cell, i) => (i in changes ? changes[i] : cell)));
const replaceRow = (text, id, line) => text.replace(row(id), line);
const fakeSha = "0".repeat(64);

const cases = [
  {
    name: "(a) named R8, then a blank suwar row reusing the ID R8",
    review: replaceRow(replaceRow(review, "R9", edit("R9", { 0: "R8" })), "R8", edit("R8", { 4: "Someone" })),
    fails: /R8: duplicate review ID/
  },
  {
    name: "(b) named `|R8|` written without spaces, then blank R9",
    review: replaceRow(review, "R8", `|${cells(edit("R8", { 4: "Someone" })).join("|")}|`),
    fails: /R9: suwar rows after R8 \(the first with a named reviewer\) must name a reviewer/
  },
  {
    name: "(c) named R8 1.0.0, blank R10 1.0.1, named R9 1.1.0 (current)",
    review: replaceRow(
      replaceRow(review, "R9", `${format(["R10", "suwar", "1.0.1", fakeSha, "", "test", "Awaiting review"])}\n${edit("R9", { 4: "Someone" })}`),
      "R8", edit("R8", { 4: "Someone" })
    ),
    fails: /R10: suwar rows after R8 \(the first with a named reviewer\) must name a reviewer/
  },
  { name: "(d) REVIEW.md as committed", review, passes: true },
  {
    name: "(e) adhkar: blank reviewer on the manifest's row R7 (1.1.1)",
    review: replaceRow(review, "R7", edit("R7", { 4: "" })),
    fails: /R7: a named reviewer is required to ship adhkar 1\.1\.1/
  },
  {
    name: "(e) ruqyah: blank reviewer on the manifest's row R4 (1.0.1)",
    review: replaceRow(review, "R4", edit("R4", { 4: "" })),
    fails: /R4: a named reviewer is required to ship ruqyah 1\.0\.1/
  },
  {
    name: "blank suwar R8, then named R9 (blank rows before the first named one stay legal)",
    review: replaceRow(review, "R9", edit("R9", { 4: "Someone" })),
    passes: true
  },
  {
    name: "a review row that cannot be parsed is an error, not skipped",
    review: review.replace(/\n*$/, `\n| R10 | suwar | 1.2.0 |\n`),
    fails: /cannot parse review row «\| R10 \| suwar \| 1\.2\.0 \|»/
  },
  {
    name: "(f) named R8 written without the leading pipe (`R8 | … |`), then blank R9",
    review: replaceRow(review, "R8", edit("R8", { 4: "Someone" }).replace(/^\| /, "")),
    fails: /R9: suwar rows after R8 \(the first with a named reviewer\) must name a reviewer/
  },
  {
    name: "(g) named R8 written with fullwidth pipes (｜), then blank R9",
    review: replaceRow(review, "R8", edit("R8", { 4: "Someone" }).replace(/\|/g, "｜")),
    fails: /cannot parse review row «｜ R8 ｜/
  },
  {
    name: "a review row after the table (past a blank line) is an error, not skipped",
    review: review.replace(/\n*$/, `\n\n${edit("R8", { 0: "R10", 2: "1.2.0", 4: "Someone" })}\n`),
    fails: /review-like line outside the review table «\| R10 \| suwar \| 1\.2\.0/
  }
];

const dir = mkdtempSync(join(tmpdir(), "athkar-review-"));
let failures = 0;
try {
  cpSync(join(repoRoot, "content"), join(dir, "content"), { recursive: true });
  cpSync(join(repoRoot, "tools"), join(dir, "tools"), { recursive: true });
  for (const testCase of cases) {
    writeFileSync(join(dir, "content/REVIEW.md"), testCase.review);
    const run = spawnSync(process.execPath, [join(dir, "tools/content-validate.mjs")], { encoding: "utf8" });
    const output = `${run.stdout}${run.stderr}`.trim();
    const ok = testCase.passes ? run.status === 0 : run.status !== 0 && testCase.fails.test(output);
    if (!ok) failures++;
    console.log(`${ok ? "✓" : "✗"} ${testCase.name}: exit ${run.status}${ok ? "" : `\n    ${output.replace(/\n/g, "\n    ")}`}`);
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}
if (failures) {
  console.error(`${failures} review case(s) failed`);
  process.exit(1);
}

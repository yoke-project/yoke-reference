// A reporter for Node.js's test runner that writes each top-level test's result as the lines the record
// writer reads: one {"Action": …, "Test": …} per test, keyed by the test function's own name, which is
// what a marker names; a failure carries its error. Subtests answer through the test they are part of.
//
// Usage: node --test --test-reporter=./ci/node-results.mjs --test-reporter-destination=<file> …

export default async function* results(source) {
  for await (const { type, data } of source) {
    if ((type !== "test:pass" && type !== "test:fail") || data.nesting !== 0 || data.details?.type === "suite") continue;
    if (data.skip || data.todo) {
      yield JSON.stringify({ Action: "skip", Test: data.name }) + "\n";
      continue;
    }
    if (type === "test:fail") {
      const error = data.details?.error;
      const said = String(error?.cause?.stack ?? error?.cause ?? error?.stack ?? error ?? "failed");
      yield JSON.stringify({ Action: "output", Test: data.name, Output: said }) + "\n";
    }
    yield JSON.stringify({ Action: type === "test:pass" ? "pass" : "fail", Test: data.name }) + "\n";
  }
}

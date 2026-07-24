---
description: Run existing tests and quality gates and report the evidence without fixing failures
---

# Test

Treat this as read-only except for disposable test outputs.

1. Read repository instructions and identify the changed or questioned contract.
2. Find the required local gates and the smallest decisive tests.
3. Run focused tests first, then broaden in proportion to risk.
4. Cover relevant failure, boundary, retry, configuration, and recovery states.
5. Investigate surprising failures enough to separate product defects from test, fixture, or environment defects.
6. Clean up disposable outputs.

Report exact commands, results, skipped coverage, and confidence. Do not edit source, tests, docs, or configuration unless the user separately asks for fixes.

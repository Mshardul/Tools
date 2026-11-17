# Test suite review

**Status:** proposed, awaiting review.

**Scope:** what the test suite protects for the app as a whole, and how it is reshaped without losing protection. It covers GrabberKitTests, AppUnitTests, the plugin tests and the shell script tests. It builds on the end-to-end layer and release gate from the release hardening phase and does not change them.

---

## Intent

The suite was written ticket by ticket. A test belongs in it only if a regression it catches would be visible to a user or would break a release. Tests that restate an implementation, test a test double, or exist only because a ticket needed a green bar do not meet that, and they cost maintenance on every change.

The risk in reshaping a suite is a silent loss: a removed test that was the only guard of some behaviour. Nothing leaves the suite on judgement alone. Every removal or rewrite is backed by evidence that a surviving test still catches what the removed one caught.

The unit suite proves the logic is right. The end-to-end layer proves the built artefact works. Neither duplicates the other.

## 1. The rule and the buckets

Every test falls into one bucket, recorded in the ledger.

| Bucket | Meaning | Disposition |
| --- | --- | --- |
| Protects behaviour | Real input to a user-visible outcome: parsers, classifiers, copy pinned to cause, engine outcomes, persistence round trips, the plugin tests | keep |
| Duplicated | One concern sliced across several files by ticket, with overlapping assertions | merge |
| Mirrors implementation | Restates the code, such as an exact argument list or a path-precedence matrix, so a rename breaks it with no user impact | rewrite to assert the effect |
| Tests a double | Exercises a fake that every other test already uses | remove |
| Ticket-scoped | Exists to close one ticket and protects nothing beyond it | merge into the concern it belongs to, or remove |

A test that proves nothing by construction, such as one that fakes the very condition it claims to check, is rewritten or moved to the end-to-end layer.

## 2. Evidence for a removal or rewrite

Four parts. A merge that keeps every assertion needs none of the witness work and only the inventory check.

**Baseline.** Before any change, record a green run, the full list of test names, a repeated-run result that exposes intermittent failures, and a coverage snapshot mapping each production file to the tests that cover it.

**Mutation witness.** For each removal or rewrite, name the production behaviour the test guards and break it on purpose: flip a condition, drop a flag, skip a retry. A different surviving test must fail. If none does, the test is the only guard, so it stays or its assertion moves into the merged or rewritten test. The witness is recorded in words with the command that was run.

**Coverage as a first filter.** After each cluster changes, any production function that lost all coverage is flagged. Coverage cannot see weak assertions, so it finds only the obvious losses and never replaces the witness.

**Inventory.** Every old test name maps to a new test or to an approved removal. Assertion counts for merged files match.

## 3. Mutation harness

Mutations run in a scratch copy of the app folder in the session scratchpad, driven with `make test ONLY=...` there. The real tree is never mutated. The copy must build with its fetched tools and must not leave a second `MediaGrabber.app` on the machine; `make test` drops its build copy, and this is confirmed before the first witness. A witness that exposes a real bug becomes a ticket only after the code is read to confirm the claim.

## 4. The ledger

One markdown table, one paragraph per line.

| File | Tests | Bucket | Protected behaviour | Verdict | Witness | Approval |
| ---- | ----- | ------ | ------------------- | ------- | ------- | -------- |

Clean files get one row per file. Mixed files get one row per test. The approval column stays empty until the owner names the file or cluster and says yes; nothing in the stages below that deletes or rewrites starts without it.

## 5. Stages

Protection never dips. Each stage ends with the full suite green.

1. **Baseline and ledger.** Record the baseline, draft every row, and review the ledger cluster by cluster. No test changes.
2. **Merges.** Assertion-preserving. Checked by the inventory and an unchanged coverage snapshot.
3. **Rewrites.** The new test lands first, the witness runs, and only then does the old test go. Argument-list tests assert the effect of a request, not the exact list. Path-precedence matrices become table tests. A test that faked its own precondition runs against a real layout or moves to the end-to-end layer.
4. **Removals.** Small batches, each with a witness and an explicit approval for each named file.
5. **Close.** A final gate dry run, a coverage diff against the baseline, and the finished ledger kept beside this spec.

## 6. Dependencies

Rewrites and removals depend on the end-to-end layer and the release gate already being in place, because some unit tests are removed on the grounds that the built-app run now covers them. The intermittent-failure check in the baseline repeats the one made before the gate went required, since a flaky test in a required gate blocks a release for no app fault.

## 7. Keeping it healthy

The rule in section 1 is written into `CLAUDE.md` so new tests meet it when they are written. A test names the user-visible behaviour it protects; test files are named for the concern, not the ticket; a test double is never given tests of its own.

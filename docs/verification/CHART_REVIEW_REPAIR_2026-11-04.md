# Chart item boundaries after independent review

Reviewer B reproduced a regression in `85ffccc`: year-labelled rows became extra
bars, and labels or units after one value leaked into the next comma-separated
item. The parent accepted A-1 and reproduced it with behavioral tests.

The parser now removes grouping commas from recognized numbers before splitting
list items. Within an item it supports labels before values or values before
labels. A year-like four-digit token followed by another value remains in its
label, as do numbered labels such as Q1. Unpunctuated label/value lists remain
supported. An unrepresentable number refuses the chart rather than dropping that
value and displaying a partial result.

The new tests cover `sales 2023 100, sales 2024 200`, month/year labels, `5 apples,
3 pears`, unpunctuated value/label lists, units, grouping commas and nonfinite
values. The tests initially produced ten failed assertions. All 13 chart tests
now pass. The full Linux core suite executes 378 tests, skips one opt-in live test
and has zero failures. Logs are `chart-review-before.txt` and
`chart-review-fixed-core.txt`.

This is a bounded data parser, not general language understanding. Independent
fix-diff review and an integrated Apple build remain pending. No phone chart
rendering result is claimed. Conversation warnings B-1 through B-4 are owned by
the already-running Mac fix worker; the parent did not modify those files here.

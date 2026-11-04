# Conversation integration checkpoint

The parent integrated the conversation branch through `d3a23ef`, excluding its
copy of `85ffccc` because that repair was already on master. The integrated tree
also contains the journal-owned action-plan core from `d6f88bf`. Plan parsing and
app plan cards are not wired yet. The installed phone source remains `7857cd68`.

Source review found that draft reconciliation treated every SQL error as an empty
ledger and that AppModel independently swallowed reconciliation errors. Both now
propagate errors. A missing table is checked explicitly. Startup does not publish
an Assistant with unreconciled drafts after a failed check.

A new repeated-save test reproduced a Linux Foundation replacement failure after
the first successful save. History replacement now uses a same-directory atomic
rename after protection and backup exclusion have been verified on the temporary
file. The final path is checked again, and temporary files are removed on failure.
This change needs an Apple build and protection readback. The Mac worker's earlier
build does not cover it.

Both new tests failed before the repairs. The integrated Linux core suite now
executes 375 tests, skips one opt-in live test and has zero failures. The log is
`conversations-parent-core.txt`. The tests cover stale draft refusal and repeated
history replacement across reopen. The first test build also exposed a missing
conditional FoundationNetworking import, which is repaired. A test assertion was
changed to allow sub-microsecond Date encoding rounding while checking message
identity, order and content.

The previous Mac worker reported signed and unsigned Release success at
`ff54688f1276fcd635317ef900d6f8a1e92a2716`, with exact shipping resources, but did not
install. Its simulator tests failed closed when complete file protection was not
reported. No real-phone protection, keyboard, conversation or new-label result is
established. These are open checks, not passes.

Fresh independent reviews must cover the conversation implementation and parent
repairs, the `85ffccc` fix diff, and the new action-plan claim unit. The original
Mac owner was retired with no pending children before replacement ownership.
No training candidate, threshold or shipping resource changed.

# Parent review of the first request store

Recovered commit `f327cae11301ab097f1ed4f3394cf660647c1e4a` on `t3/0d4df96a`.
Its completed first run reports 17 targeted tests and 220 total tests, with one
skip and zero failures. A later empty continuation did not erase that result.
The source and tests were read in full. This commit is not integrated or wired
to app input yet.

Independent review must check these source-traced concerns with reproductions.

- `claim` allows a claim before the first `recoverOnLaunch`. That first recovery
  then changes every claimed row to interrupted, including the live owner's new
  claim. The caller contract says recovery comes first, but the API permits the
  unsafe order. Enforce the lifecycle or prove live claims cannot become retryable.
- `setTranscript` validates grapheme count but does not reserve UTF-8 bytes against
  `maxTotalBytes`. Stage sums only the original immutable body byte count. Voice
  transcripts can therefore exceed the promised active-payload cap. A long
  combining-character sequence can also be one grapheme with many bytes.
- File protection and backup exclusion use `try?`, so opening succeeds if either
  protection operation fails. Verify how to refuse storage honestly on Apple
  platforms and how journal files inherit the intended protection.
- The same-process ownership registry reads `isOwner` under a different lock
  from its writer. Check real concurrent open/close behavior and Darwin `flock`
  semantics, rather than counting sequential second-instance tests as race proof.

These are review hypotheses grounded in source paths, not observed iPhone defects.
The existing implementation usefully covers body immutability, ordinary CAS claims,
terminal cleanup, bounded original bodies and explicit owner lifetime. Caller wiring,
datetime review, effect-ledger reconciliation, voice and camera remain separate work.

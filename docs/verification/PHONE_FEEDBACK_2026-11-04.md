# Phone observations and follow-up

The user tested installed source 7857cd68 (the Sonnet UI build). These are user-reported observations, not automated device evidence.

- Airplane Mode on and Wi-Fi off: “What is 2 + 2?” answered 4.
- Keyboard Done dismisses the keyboard. Intermittently the keyboard covers the text field while typing.
- “Make a chart: rent 1200, food 400, transit 130” returned a plain-text chart. Asking for a chart in HTML showed an input modal.
- Complete text-message requests send reliably in the user's testing. Some “text …” requests still return the old skill-choice restatement prompt.
- A group-chat request was reduced to the first part of the group name as a person. Exact group name was not requested or collected.

Parent messaging repair 7810437 is newer than the installed app. It has 314 passing core tests with one pre-existing skip, but has not been built or tested on the iPhone. Incomplete drafts remain in session memory. Named-group routing and keyboard occlusion are open as of this record.

The chart fallback was reproduced with scripted classifier choices. Explicit chart commands containing numbers now use the deterministic local formatter and produce fenced HTML for the existing isolated inline renderer. The actual route decision is retained; this formatter is not a claim of classifier accuracy. A chart instruction inside message content stays message content. Large finite chart numbers no longer overflow Int or bar-width arithmetic, and non-finite values are refused. Parent full suite executes 321 tests, with one skip and zero failures.

Evidence: chart-routing-before.txt and chart-routing-fixed-core.txt. No new phone runtime result exists for this patch.

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

## Parent repair after later feedback

Named group requests now stop before contact parsing with an explicit unsupported response. This applies both to initial commands and a group-name answer to a recipient question. A group mention inside a marked message body stays literal. This is an app capability limit, not a claim that iOS forbids all group messages. Apple's public compose API accepts recipient phone numbers; it does not provide the app's current single-contact contract with a group-name resolver. Reference: [Apple recipient API](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller/recipients).

Additional regressions preserve quotes, URLs and colons in message text, keep app words in an unmarked body from choosing the destination, leave the body empty after a channel-only suffix, and keep a new numeric chart request separate from an unfinished message. The user also reported a previously working message request later becoming “hii” in chat. A same-assistant repeated-request test now stages review cards even after chat generation and a deliberately wrong later skill pick. It records zero effect calls before confirmation. This is scripted evidence, not a diagnosis of the phone model's internal state; the next Mac worker must inspect private device decision records before claiming such a cause.

Updated parent full suite: 329 executed, one pre-existing live skip, zero failures. Evidence: message-boundaries-core.txt. These changes have not yet been installed on the phone. Keyboard occlusion, separate conversations/clear, and readable explanations for values are assigned to the next Mac UI scope. Input-store caller integration and multi-step execution remain unfinished.

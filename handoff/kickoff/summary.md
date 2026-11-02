# Meta Global AI Developer Hackathon: Kickoff Livestream Summary
**Date:** Mon Oct 26, 2026 · **Host platform:** Cerebral Valley (Vimeo Live event 6292874)
**Program:** about 12:00:10 to 12:22:30 ET (about 22 min). A countdown card ran before it and an end card ran after it. The stream ended at about 12:27:55 ET.
**Sources:** `transcript.txt` (faster-whisper medium.en) and `slides_ocr.txt` (tesseract plus slide text read by eye). Timestamps are ET wall clock. ASR spellings are marked *[?]* where uncertain. Names come from the on-screen lower-thirds.
**No Q&A segment.** The host sent all questions to Discord.

---

## Speakers (from on-screen name cards)
| Time (ET) | Speaker | Title (as shown) |
|---|---|---|
| 12:00:29 | **Ivan Porollo** | Founder, Cerebral Valley (host/MC) |
| 12:01:59 | **Saurabh Baji** | Engineering Director, Model API, Meta |
| 12:07:28 | **Aishwarya Goel** | GTM, Baseten (said on stream: "I'm on the marketing team") |
| 12:08:42 | **Andrew Hinh** | Developer Relations Engineer, Modal |
| 12:09:24 | **Sinan Ozdemir** | Head of AI Developer Education, Fireworks AI |

## Agenda (as run)
1. **11:27 to 12:00:** pre-show countdown card ("Kickoff starting in…", in partnership with Baseten, Fireworks AI, Modal). No speech.
2. **12:00:** Ivan's welcome and agenda.
3. **12:02 to 12:07:** keynote by Saurabh Baji (Meta): vision, which Muse models to use, and tips.
4. **12:07 to 12:10:** partner intros from Baseten, Modal, and Fireworks AI.
5. **12:10 to 12:22:** Ivan on logistics: overview, tracks, themes, rules, banned projects, prizes, timeline, Discord, live sessions, credits, judging, rubric, and submission.
6. **12:22:30 to 12:27:55:** end card ("$1 MILLION IN PRIZES · OCT 26–NOV 4"), then the stream ended.

---

## Host opening (Ivan Porollo)
- "Hello everyone. My name is Ivan. I'm with Cerebral Valley. We host some of the largest hackathons in the world…" [12:00:29]
- "…there's not many hackathons in the world that give out a million dollars in prizes. So if you're here today, you're one of the lucky folks that got selected to participate…" [12:00:58]
- Agenda: Meta speakers, then partners, then housekeeping rules, then the hack starts. **Live chat for the session goes in the Discord general chat.** [12:01:17–12:01:45]

## Meta keynote (Saurabh Baji, Engineering Director, Model API)
- Theme: "At Meta Super Intelligence Labs, we've been moving quickly to advance our models…" The goal "is to compress the time between an idea and a working product." [12:02:40–12:02:51] (part of this passage was inaudible or not transcribed)
- "This hackathon is an opportunity to test an idea, get a prototype working, learn where it breaks, and improve it…" "What you build helps us learn too: which capabilities are the most useful, where the tools need to improve, and what developers want to do next." [12:03:08–12:03:26]
- **Meta models and tools he highlighted** [12:03:32–12:04:21]:
  - **Muse Spark** and **Muse Wonder** on the **Meta Model API**: "give you reasoning capabilities for applications and agents that need to work through complex tasks."
  - **Muse Code**: "can help you move from an idea into implementation with agents that can work across a project, write and test code, and support longer engineering tasks."
  - **Muse Image** and **Muse Voice** for projects involving images or speech. One transcription pass heard "Muse Voice Transcribe" *[?]*.
  - **Muse Glimmer** and **Muse Spark Open** (open weights): "open up possibilities for building locally on your own hardware or through our partners, Fireworks, Baseten and Modal."
  - The stream did not mention SAM 3.1, Llama, or other new model or API launches.
- **Credits:** "We're helping cover the compute with **$150 in free Model API credits**, so you have room to experiment… **Check the email from the event to claim your credits.**" [12:04:24–12:04:36]
- **Advice on what to build and how** [12:04:40–12:06:32]:
  - "Start with the problem you understand. Think about a task that you have to repeat, a process that takes too long, or something that people in your community struggle to access."
  - His examples: an agent that helps a small business through a complicated workflow; a tool to make sense of information, create visual content, or interact with software through speech; something that makes developers more effective; AI brought into a field where you have expertise.
  - "**Pick a clear user and a clear job to help them accomplish.**" [12:05:21]
  - "**Aim for a working prototype that you can demonstrate.** Put it in someone's hands early, watch how they use it and let that feedback shape your next iteration." [12:05:32]
  - "Try an approach that you haven't used before. Ask questions. Share what you learn and help other teams get past blockers." [12:06:10]
  - "Keep checking whether your prototype delivers the result you intended. Look at the output, test the workflow, and learn from the failures." [12:06:18]
  - "Many of the best ideas at Meta started at a hackathon table. This week, that table stretches across the world." [12:06:37]

## Partner intros
- **Baseten (Aishwarya Goel)** [12:07:28]: Baseten does "inference and post-training for open and custom models" for companies including "Lovable, Cursor, Harvey, Notion, Open Evidence". Selected builders get "**$100 credits and up to 2 million TPM**" *(the ASR heard "$2 million"; the slide says 2M TPM rate limits)*. "Once you're selected, expect an email from us." She will be in Discord, and Baseten has a channel there.
- **Modal (Andrew Hinh)** [12:08:42]: cloud infrastructure "from getting serverless GPUs to doing inference, sandboxes and training." Offering "**$100 in credits for the first thousand teams**." The slide says "up to 1,000 participants", credits for Meta open-weights models. Tag him in Modal's Discord channel.
- **Fireworks AI (Sinan Ozdemir)** [12:09:24]: inference and training platform. Credits are coming, and redemption details will be posted in the Fireworks Discord channel. He has been "training language models for a little over 10 years… even before the transformer was even invented". He will answer questions in Discord on using, benchmarking, and training models.

---

## Event structure
- **10 days:** Oct 26 to Nov 4. Hacking starts right after kickoff. [12:11:10]
- **Two tracks.** You applied to one of them. [12:11:20; slide 12:11:34]
  - **Indie Developer:** for individual builders and students ("indie hackers"). Judged on creativity, technical ambition, and whether it works.
  - **Startup:** for teams and founders building a real product ("incorporated startups"). Judged on technical execution and whether it holds up in production.
- **Two themes (the problem statements).** Either track can build toward either theme. [slide 12:11:54; speech 12:12:02]
  - **Build for Your World:** "Bring Meta's models into your domain. Solve a problem you know firsthand, free up time and mental space, and make something possible that wasn't before." Ivan added: "…a problem that you know firsthand… that's keeping you up at night."
  - **Push the Frontier:** "Use Meta's models to tackle challenges in software, robotics, manufacturing, energy, materials and beyond. Show us what becomes possible when these models meet the real world."

## Rules ("Build it new, build it in the open") [slide 12:12:54; speech 12:12:33–12:13:47]
- **New work only.** Build it between Oct 26 and Nov 4. Startups can bring a product, but only work done during the event counts. Teams with prior work must "call out… where that new work starts" in the submission.
- **Teams of up to four.** Solo builders are welcome. **All teammates must be approved.** If a teammate wasn't approved, use #team-search.
- **Public repos.** The GitHub repository must be public: "we will be evaluating all of them."
- **Demo only what you built.** Judges must be able to tell what your team created during the event, or the project is disqualified.
- **No banned projects.** Anything that breaks legal, ethical, or platform policies, or that uses code, data, or assets you don't have rights to, is disqualified.

## Overdone projects to avoid [slide 12:13:54]
AI-generated medical advice · Basic RAG apps · Simple image analyzers · Streamlit apps · Dashboards as the main feature · "AI for Education" chatbots · AI job application screeners · AI nutrition coaches · Personality analyzers · Sports analyzers or coaches. The slide notes this is not a complete list, and that "medical advice" includes AI mental-health advisors and skin-blemish detectors.
- Ivan: "simple chat wrappers, simple RAG apps, image analyzers, or medical advice generators… The point of this hackathon is… to push the frontier or to bring something in your world and essentially **push these Meta models to the edge**… try and come up with something more unique." [12:14:04–12:14:35]

## Prizes: $1,000,000 cash [slides 12:14:34–12:15:44]
| Place | Indie Developer ($400K) | Startup ($550K) |
|---|---|---|
| 1st | $150K | $250K |
| 2nd | $100K | $150K |
| 3rd | $75K | $75K |
| 4th | $50K | $50K |
| 5th | $25K | $25K |

**Bonus prizes, $50K total.** "When you're submitting… make sure to call out if you're submitting to this prize track." [12:15:23]
| Prize | Amount | What it rewards / how it's judged |
|---|---|---|
| Most Viral Project | $20K | The demo with the most engagement on X after the event. Post your demo on X and submit the link (in the submission form). Most likes, reposts, and comments by **Nov 8, 11:59 PM ET** wins. |
| Best Build on Meta Open Weights | $10K | Best project on **Muse Glimmer or Muse Spark Open**, on your own hardware or partner inference. Flagged in round one. The infra partner verifies it runs on an eligible open-weight model. |
| Community Vote | $10K | Most votes in the public project gallery, one vote per verified account. Winner announced **Nov 16**. "Distribute… your project to your friends and they can upvote it." |
| Best Agentic Use-Case | $5K | Strongest use of AI agents to complete tasks, make decisions, or run multi-step workflows. Judges score autonomy, effectiveness, and practical usefulness. |
| Best Creative Build | $5K | Most original creative project built with **Muse Image or Muse Wonder**. Flagged in round one. Scored on originality, execution, and use of the model. |

## Timeline [slide 12:16:14; speech 12:16:15–12:17:14]
- **Oct 26:** kickoff at 12:00 PM ET. Hacking starts.
- **Oct 27 to Nov 3:** live sessions and office hours on Discord.
- **Nov 4, 9:00 PM ET:** submissions due (hacking ends).
- **Nov 5 to 8:** first round of judging. No action needed from you.
- **Nov 9, 12:00 PM ET:** closing ceremony. Top finalists present, and judges judge the projects live.
- **Nov 16:** community vote winner announced on Discord.

## Workshops and office hours [slide 12:17:54; speech 12:16:27, 12:17:57]
| Date | Session | Speaker |
|---|---|---|
| Tue Oct 27 | Meta Engineering Workshop Part 1 | Suraj Subramanian (Meta) |
| Wed Oct 28 | Meta Engineering Workshop Part 2 | Yash Khare (Meta) |
| Fri Oct 30 | Fireworks AI Workshop | Sinan Ozdemir (Fireworks AI) |
- Sessions start at **12:00 PM ET** unless noted. Every session is recorded and posted to #resources.
- **Office hours:** "on each weekday… in morning ET time… the Meta team will be online answering any questions in the office-hours channel." [12:16:37]

## Discord ("home base for the next ten days") [slide 12:17:24]
- **Join:** https://cv.inc/e/meta-ai-developer-hackathon/discord. Ivan: "the URL of the event, and then just add /discord to the end, or just use that QR code."
- Channels: **#announcements** (official updates and deadlines) · **#questions** (ask the CV team, ping @CV; run as a forum) · **#office-hours** (ask the Meta team) · **#resources** (docs, credit forms, recordings) · **#team-search** (find teammates, up to four) · **#intros**. Each partner (Baseten, Modal, Fireworks) also has its own channel.
- Ivan said Discord support bots are available that carry the event information. He said the kickoff "will be recorded", and the slide says the recording will be posted in #resources today.

## Credits and access [slide 12:18:24; speech 12:18:23–12:19:07]
| Provider | Amount | Details |
|---|---|---|
| **Meta** | **$150** | Meta Model API credits for every participant |
| Baseten | $100 | Credits plus 2M TPM rate limits, up to 2,000 participants |
| Modal | $100 | Credits for Meta open-weights models, up to 1,000 participants |
| Fireworks | $25 | Credits for select participants, plus a workshop with Sinan Ozdemir |
- **How to claim:** request forms open in **#resources** at kickoff. They are also on the event details page on the Cerebral Valley platform: "the event link you signed up on, you should now see an **information icon** on there that you can click."
- Teams will distribute credits **in batches**. **Partner credits are selected by the partners**, "up to a certain amount of participants."
- Saurabh said to "check the email from the event to claim your credits." Baseten said selected builders will get an email.

## Judging [slides 12:19:14, 12:20:24; speech 12:19:13–12:20:36]
1. **Stage 1, pass/fail:** "Does the project reasonably fit a theme and use Meta AI products?"
2. **Stage 2, rubric scoring:** Meta-team judges score every passing project 0 to 10 on the rubric (the rubric is also on the event details page).
3. **Stage 3, live final round (Nov 9):** top 5 per track. "Judges will tune in, watch the three-minute video that you submit and essentially give feedback on it." They then rank the finalists 1st to 5th.

**Rubric** (the same rubric is used in Stage 2 and the final. Each criterion is scored 0 to 10.)
| Criterion | Weight | Definition (slide) |
|---|---|---|
| **Impact** | **30%** | Real-world potential, who benefits, and fit with a problem statement |
| Use of Meta AI tooling | 25% | Creative use beyond a basic integration |
| Technical depth | 20% | Sound, refined engineering with real craft |
| Demo | 25% | A working demo that holds up, and a demo video worth watching |
- Ivan: "we're focused on impact first." [12:20:24]

## Submission requirements [slide 12:20:34; speech 12:20:37–12:21:19]
"Submit four things by Nov 4, 9:00 PM ET":
1. **Submit on the CV platform, with every teammate:** cerebralvalley.ai/e/meta-ai-developer-hackathon/hackathon/submit. A "Submit project" button appears on the event page after kickoff.
2. **A 3-minute demo video.** Show only what your team built during the event, because judges score from it. Ivan called it the "very important thing to submit."
3. **A public GitHub repo.** "Check that it opens in a logged-out browser before you submit."
4. **Before the deadline:** Wednesday, Nov 4 at 9:00 PM ET. "Don't wait for the last hour."
- Also: call out any prior work and where the new work starts, flag any bonus prizes you're entering, and include your X post link for Most Viral.
- "Review the form early so you know what's coming." [12:21:19]

## Tips on what wins (combined from all speakers)
- Impact counts most (30%): a real user, a real problem, and a clear fit with one of the two themes.
- Use Meta's tools in a creative way that goes past a basic integration (25%). Push the Muse models "to the edge."
- The 3-minute video drives Stage 3 and counts toward the 25% Demo score. It needs to show a working demo that holds up and only what you built during the event.
- Avoid the overdone list (chat wrappers, basic RAG, Streamlit apps, dashboards, medical advice, and so on).
- "Pick a clear user and a clear job." Get a working prototype in front of users early and iterate.
- Ivan's last advice: "Get started to think not only about the project idea, but then how you will present it to the judges as well and how you build it." [12:22:13]

## Closing
- "Happy hacking folks! I'm excited to see what you can build with the Meta models. Good luck!" [12:22:20]
- **What happens next (slide):** today, credit forms and the kickoff recording go to #resources. Tue Oct 27 at 12:00 PM ET is the first live session. Wed Nov 4 at 9:00 PM ET submissions are due.

## Q&A
- There was no live Q&A. Ivan said questions coming in through chat and Discord would be answered there during the day and week ("I know there's a lot in the chat, so we will be going through that today and answering"). [12:21:46]

## Transcription caveats
- ASR mangled names, which were corrected from the lower-thirds: "Evan" → Ivan, "Sara Baji" → Saurabh Baji, "Base10" → Baseten, "Siraj" → Suraj.
- One ASR pass heard "best live build" at 12:16:10. The slide says **Best Creative Build**.
- A few seconds of the keynote around 12:02:43 to 12:02:51 were not transcribed.

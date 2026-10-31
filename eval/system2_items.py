# Adapted from Habib's Gate-1 eval (written 2026-10-31, within the hackathon window).
# Gate-1 eval items. Date context given to model: Saturday 2026-10-31 15:00, America/New_York.
NOW = "Current date/time: Saturday 2026-10-31 15:00 (America/New_York, UTC-4)."

EMAIL = """From: Dana Ruiz <dana@acme.io>
Subject: Re: Q4 launch
Hi team, quick update: the Q4 launch moves from Nov 12 to Nov 19 because the payments vendor needs another week for certification. Marketing should hold the press release until we confirm on Nov 14. Eng: please freeze the release branch by Nov 16. Budget is unchanged at $240k. Thanks, Dana"""

# (id, prompt, reference, grading keys: list of alternatives-lists that must ALL appear (case-insens), any-of within each)
QA = [
 ("qa01", f"Summarize this email in 2 sentences:\n\n{EMAIL}", "Launch moved Nov 12->Nov 19 due to payments vendor certification; hold PR until Nov 14 confirmation; freeze branch Nov 16; budget unchanged $240k.", [["19"],["vendor","certif","payment"]]),
 ("qa02", f"From this email, what date must engineering freeze the release branch? Answer with just the date.\n\n{EMAIL}", "Nov 16", [["16"]]),
 ("qa03", f"From this email, list the action items and who owns each.\n\n{EMAIL}", "Marketing: hold press release until Nov 14 confirmation; Eng: freeze release branch by Nov 16.", [["marketing"],["press"],["eng"],["freeze"]]),
 ("qa04", "A store sells pens at 3 for $4. How much do 18 pens cost? Show brief reasoning and give the final answer.", "$24", [["24"]]),
 ("qa05", "Alice is older than Bob. Bob is older than Carol. Dave is younger than Carol. Who is the second youngest?", "Carol", [["carol"]]),
 ("qa06", "A train leaves at 2:45 PM and the trip takes 3 hours 50 minutes. What time does it arrive?", "6:35 PM", [["6:35"]]),
 ("qa07", "If I have 5 meetings of 45 minutes each with 10-minute breaks between consecutive meetings, starting at 9:00 AM, when does the last meeting end?", "1:25 PM (5*45=225 + 4*10=40 => 265 min => 13:25)", [["1:25","13:25"]]),
 ("qa08", "Fix the bug in this Python function and show the corrected code:\n\ndef average(nums):\n    total = 0\n    for n in nums:\n        total += n\n    return total / len(nums) if nums else total / 0\n", "Return 0 (or None/raise) for empty list instead of dividing by zero.", [["return 0","return none","raise","0.0"]]),
 ("qa09", "This Swift code doesn't compile: `let names = [\"a\",\"b\"]; names.append(\"c\")`. Why, and how do you fix it?", "names is a let constant; use var.", [["var"]]),
 ("qa10", "What is wrong with this SQL? `SELECT name, COUNT(*) FROM users;` Give the fixed query.", "Missing GROUP BY name.", [["group by"]]),
 ("qa11", "Document:\n\"The Pixel Pro warranty covers manufacturing defects for 24 months. Water damage is excluded. Battery replacements are covered only if capacity drops below 80% within the first 12 months.\"\n\nQuestion: My battery is at 75% capacity after 18 months. Is a replacement covered? Answer yes or no and why.", "No — battery coverage only applies within the first 12 months.", [["no"],["12"]]),
 ("qa12", "Document:\n\"Employees accrue 1.5 vacation days per month worked. Unused days roll over up to a maximum balance of 30 days.\"\n\nQuestion: An employee starts with 25 days and works 6 more months without taking leave. What is their balance?", "30 (25+9=34 capped at 30)", [["30"]]),
 ("qa13", "Explain in 2-3 sentences what a KV cache is in transformer inference and why it speeds up decoding.", "Stores past keys/values so each new token only computes attention for itself, avoiding recomputation.", [["key"],["value"],["recomput","reuse","previous","past"]]),
 ("qa14", "I have $1,200. I spend 25% on rent, then one third of what's left on food. How much remains?", "$600", [["600"]]),
 ("qa15", "Write a one-line Python expression that returns the list of even numbers from a list called xs.", "[x for x in xs if x % 2 == 0]", [["% 2 == 0","%2==0","% 2==0"]]),
]

TOOLS = [
 {"type":"function","function":{"name":"create_reminder","description":"Create an iOS reminder.","parameters":{"type":"object","properties":{"title":{"type":"string"},"due_iso":{"type":"string","description":"ISO 8601 local datetime"}},"required":["title","due_iso"]}}},
 {"type":"function","function":{"name":"create_calendar_event","description":"Create a calendar event.","parameters":{"type":"object","properties":{"title":{"type":"string"},"start_iso":{"type":"string"},"end_iso":{"type":"string"},"attendees":{"type":"array","items":{"type":"string"}}},"required":["title","start_iso","end_iso","attendees"]}}},
 {"type":"function","function":{"name":"send_message","description":"Send an iMessage/SMS to a contact.","parameters":{"type":"object","properties":{"contact":{"type":"string"},"body":{"type":"string"}},"required":["contact","body"]}}},
 {"type":"function","function":{"name":"search_memory","description":"Search the user's personal notes/memory.","parameters":{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}}},
 {"type":"function","function":{"name":"answer_directly","description":"Answer the user directly with no action.","parameters":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}}},
]

# expected: tool, dict of arg checks: ("dt", "YYYY-MM-DDTHH:MM") | ("kw", [words all must appear]) | ("eq", value) | ("list_kw", [names]) | ("any", None)
TC = [
 ("tc01","Remind me to call the dentist tomorrow at 9am.","create_reminder",{"title":("kw",["dentist"]),"due_iso":("dt","2026-11-01T09:00")}),
 ("tc02","Set a reminder for Monday at 6:30pm to take out the trash.","create_reminder",{"title":("kw",["trash"]),"due_iso":("dt","2026-11-02T18:30")}),
 ("tc03","Remind me in 2 hours to check the oven.","create_reminder",{"title":("kw",["oven"]),"due_iso":("dt","2026-10-31T17:00")}),
 ("tc04","Put a 1-hour meeting called Design Review on my calendar for Tuesday at 2pm with Priya and Sam.","create_calendar_event",{"title":("kw",["design","review"]),"start_iso":("dt","2026-11-03T14:00"),"end_iso":("dt","2026-11-03T15:00"),"attendees":("list_kw",["priya","sam"])}),
 ("tc05","Schedule lunch with Omar on November 5th from 12:30 to 1:30pm.","create_calendar_event",{"title":("kw",["lunch"]),"start_iso":("dt","2026-11-05T12:30"),"end_iso":("dt","2026-11-05T13:30"),"attendees":("list_kw",["omar"])}),
 ("tc06","Block 30 minutes tomorrow at 10am for 'Gym', just me.","create_calendar_event",{"title":("kw",["gym"]),"start_iso":("dt","2026-11-01T10:00"),"end_iso":("dt","2026-11-01T10:30"),"attendees":("list_kw",[])}),
 ("tc07","Text Mom that I'll be home by 8.","send_message",{"contact":("kw",["mom"]),"body":("kw",["8"])}),
 ("tc08","Send a message to Jake saying the meeting moved to Thursday.","send_message",{"contact":("kw",["jake"]),"body":("kw",["thursday"])}),
 ("tc09","Tell Sarah I'm running 10 minutes late.","send_message",{"contact":("kw",["sarah"]),"body":("kw",["10"])}),
 ("tc10","What was the wifi password I saved for the cabin?","search_memory",{"query":("kw",["wifi"])}),
 ("tc11","Find my notes about the Q4 launch plan.","search_memory",{"query":("kw",["q4"])}),
 ("tc12","Did I write down my passport number somewhere?","search_memory",{"query":("kw",["passport"])}),
 ("tc13","What's 15% of 80?","answer_directly",{"text":("kw",["12"])}),
 ("tc14","What's the capital of Australia?","answer_directly",{"text":("kw",["canberra"])}),
 ("tc15","Thanks, that's all for now!","answer_directly",{"text":("any",None)}),
]

RAW = [  # no grammar, native ATEM tool format via chat template
 ("raw01","Remind me to buy milk tomorrow at 8am.","create_reminder",{"title":("kw",["milk"]),"due_iso":("dt","2026-11-01T08:00")}),
 ("raw02","Text Alex that dinner is at 7.","send_message",{"contact":("kw",["alex"]),"body":("kw",["7"])}),
 ("raw03","Schedule a call with Lena on Wednesday 4-5pm titled Budget Sync.","create_calendar_event",{"title":("kw",["budget"]),"start_iso":("dt","2026-11-04T16:00"),"end_iso":("dt","2026-11-04T17:00"),"attendees":("list_kw",["lena"])}),
 ("raw04","What did I note about my landlord's phone number?","search_memory",{"query":("kw",["landlord"])}),
 ("raw05","Remind me Friday at noon to submit the expense report.","create_reminder",{"title":("kw",["expense"]),"due_iso":("dt","2026-11-06T12:00")}),
 ("raw06","Let Chris know I'll send the deck tonight.","send_message",{"contact":("kw",["chris"]),"body":("kw",["deck"])}),
 ("raw07","Search my memory for the hotel confirmation number in Lisbon.","search_memory",{"query":("kw",["hotel"])}),
 ("raw08","Add 'Dentist' to my calendar Nov 10 at 3pm for 45 minutes.","create_calendar_event",{"title":("kw",["dentist"]),"start_iso":("dt","2026-11-10T15:00"),"end_iso":("dt","2026-11-10T15:45"),"attendees":("list_kw",[])}),
 ("raw09","Remind me tonight at 9 to call Grandpa.","create_reminder",{"title":("kw",["grandpa"]),"due_iso":("dt","2026-10-31T21:00")}),
 ("raw10","Message Priya: running late, start without me.","send_message",{"contact":("kw",["priya"]),"body":("kw",["late"])}),
]

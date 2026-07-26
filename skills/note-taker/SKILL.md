---
name: note-taker
description: "Transform conference transcripts or raw notes into comprehensive, structured summaries using a six-section format. Triggers: 'take notes on this', 'summarize this transcript', 'synthesize these notes', 'structure this session', 'organize these meeting notes'."
---

# Conference Note-Taking & Synthesis

Produce a comprehensive, structured summary from any conference session transcript or raw notes.

## Input

Paste the raw transcript (auto-generated, messy, or incomplete) or scattered notes. The system handles imperfect source material.

## Six-Section Output Format

### 1. Session Overview

- **Session Title:** Exact title if stated; infer if absent, mark **[Inferred]**
- **Speaker(s):** Names, titles, affiliations — mark **[not stated]** if missing
- **Date / Event:** Date and event name if stated
- **Audience Level:** Beginner / Intermediate / Advanced — infer from content density
- **Core Theme:** 1–2 sentence summary of central argument or purpose
- **One-Line Summary:** Single sentence distilling the most important message

### 2. Key Takeaways & Highlights

- Extract the most important concepts, insights, and data points using strong action verbs
- Keep bullets concise but include the supporting reason or evidence in a sub-bullet where it adds value
- Call out hard numbers, statistics, and specific claims separately so they're easy to find
- Aggregate by speaker if multiple voices; note agreements or disagreements

### 3. Detailed Breakdown

Organize chronologically. Add approximate timestamps or section markers if present.

For each segment capture:
- The point made
- The supporting argument, example, or data
- Any caveats the speaker raised

Highlight all **frameworks, models, case studies, and methodologies** — explain how each works, not just its name.

Include notable quotes verbatim (with quotation marks) where exact wording matters.

Comprehensively extract every distinct idea, topic, and key point. If the speaker mentioned it briefly, it belongs here if it's a real idea.

### 4. Actionable Next Steps

- Extract specific tasks, recommendations, or homework the speaker suggested
- List every recommended tool, resource, technique, concept, paper, person, or book — with a one-line note on why
- Separate **explicit recommendations** ("you should do X") from **implied opportunities** — mark as **[Inferred]**

### 5. Q&A Summary

- Summarize each audience question and the speaker's answer as a Q/A pair
- Note any questions the speaker **deferred, dodged, or couldn't answer** — these reveal open problems

### 6. Open Questions & Follow-Ups

- List anything left unresolved, promised for later, or worth researching
- Note any contradictions or points that warrant fact-checking

## Ground Rules

1. **Be faithful first.** Capture what the speaker actually said. Infer or fill gaps only when necessary, then mark clearly as **[Inferred]**.
2. **Preserve reasoning, not just conclusions.** Capture the *why* — evidence, logic, examples, data — not only the takeaway.
3. **Flag uncertainty.** If the transcript is garbled, inaudible, or ambiguous, note as **[unclear in transcript]** rather than guessing.
4. **Distinguish fact from claim.** Mark opinions/predictions as the speaker's stance. Present stated facts and cited data as facts.
5. **Define jargon.** For technical terms or acronyms, add a bracketed plain-English definition on first use — e.g., RAG [Retrieval-Augmented Generation].
6. **No hallucinated details.** Do not invent names, numbers, titles, or citations. If unknown, write **[not stated]**.

## Formatting

- Clean markdown, with **bold** for key terms and concepts
- Professional, objective, comprehensive tone — no filler, no praise of the speaker
- Bracketed definitions for technical terms and obscure acronyms
- If the transcript is too sparse to fill a section, write **[Not enough information in transcript]** rather than padding it

## Processing Notes

- Auto-generated transcripts may contain duplicate sentences, mid-sentence cuts, or hallucinated punctuation — transcribe meaning accurately even when source is corrupted
- Incomplete transcripts (early ending, missing sections): note this explicitly rather than inventing content
- Multiple speakers: attribute clearly. If speaker identification is unclear, mark as **[Unidentified Speaker]**
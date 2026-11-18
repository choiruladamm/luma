---
type: explanation
purpose: Explain how paragraph groups remain stable for reading and AI.
sections: [Purpose and stability, Grouping rules, Boundaries and identity]
---

# Paragraph grouping

## Purpose and stability

Short consecutive paragraphs form a group at import, so a tap can translate a useful passage instead of one short line. Group indices are stored and provide stable units for cached AI results.

## Grouping rules

`assignGroups` uses `GroupRules.longThreshold`, `targetChars`, `maxChars` and `maxParagraphs`. A long paragraph forms a group on its own, even when it exceeds `maxChars`. Otherwise a group closes before adding a paragraph that would exceed the maximum size or count, and closes after reaching the target size.

## Boundaries and identity

Headings and scene breaks end the current group and have no group index. Groups never cross chapters; indices start at zero within each chapter. For the behavior of Lanjut, see [Reader interaction](design.md#reader-interaction).

---
paths: ["apps/mobile/**/*.dart"]
---

# Dart: conditional logic

- Ternaries at most 1 level deep in the widget tree.
- More than 2 branches, or labels/text derived from model state: extract to a getter in an extension on the model (e.g. `book.progressLabel`), body is sequential `if/return`.
- State that can grow: enum + switch expression.

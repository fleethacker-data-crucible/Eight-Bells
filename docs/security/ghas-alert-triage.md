# GHAS alert triage (sprint 2026-11)

Open code-scanning alerts on Eight Bells as of this sprint. Each row is fixed in this change, or left as-is with the GitHub dismissal reason an owner should apply. This document does not dismiss anything; dismissal stays in the GitHub UI.

| Alert | Rule | Path | Disposition | Reason | GitHub dismissal |
| --- | --- | --- | --- | --- | --- |
| code-scanning 1 | js/incomplete-multi-character-sanitization | tests/sourcelinks.test.js:13 | fixed | The round-trip check stripped every tag with `/<[^>]*>/`, which can leave a `<script`. It now removes only the buttons `linkRefs` inserts, then decodes the entities that function wrote. | |
| code-scanning 2 | js/incomplete-multi-character-sanitization | tools/gen-icons.mjs:43 | fixed | The one-shot `/<!--...-->/` replace can splice the surrounding text into a new `<!--` (`<!<!--note-->--`). Comment removal is now a scan that repeats until no `<!--` remains, including an unclosed comment. Lucide 1.54.0 icons still extract to the markup already committed in `web/icons.js`. | |
| code-scanning 3 | js/xss-through-dom | web/app.js:129 | accept: false positive | The sink is `imagePreview.src = URL.createObjectURL(file)` for a file the operator picked. `createObjectURL` returns only a `blob:` URL, so it cannot be a `javascript:` URL, and an `<img>` does not execute script from SVG or HTML. The preview behavior is unchanged. | false positive |

No alert is left as "needs owner decision." Alert 3 stays open until an owner dismisses it as a false positive.

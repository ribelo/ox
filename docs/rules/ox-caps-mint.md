# ox-caps-mint

^ncapslint-nf4t ^ncapslint-8jcy ^ncapslint-x3gi

## Definition

Minting or naming Ox_caps_door is legal only when the owning Dune stanza directly declares ox_caps.door. A direct ox_test dependency also authorizes Ox_test.powerbox, and only that test mint; it never authorizes naming Ox_caps_door or minting through Ox_app.with_powerbox. Module selectors and include_subdirs establish ownership; arbitrary transitive dependencies, sibling stanzas and comments grant nothing. Pathnames never grant permission.

The shipped allow-list is empty. Explicit --allow remains supported, but no wrapper, Door, library, tool or pathname receives a default exception.

## What this does not cover

Only literal Dune library/executable/test stanzas, modules selectors and include_subdirs are interpreted. Included/generated Dune forms, variables and conditional dependency expressions are not evaluated and do not grant minting. Source identity can miss opaque re-exports; typed evidence resolves compiler paths.

[Violating fixture](<../../test/caps/rules/violating/mint.ml>) and
[clean fixture](<../../test/caps/rules/clean/mint.ml>) form the rule/fixture/page triangle, checked by --self-check.

Compiled negative fixtures use a file-level `ox_lint.fixture` marker naming their rule: only the default scan skips them; explicit scans retain every finding and reject a dead marker when its rule is selected. Repository tests verify these findings with typed evidence; installed `--self-check` audits the source-only bundle structurally. See [fixture scope](<../caps.md#fixture-scope>).

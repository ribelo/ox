# ox-caps-mint

^ncapslint-nf4t ^ncapslint-8jcy ^ncapslint-x3gi

## Definition

Minting or naming Ox_caps_door is legal only when the owning Dune stanza directly declares ox_caps.door. Module selectors and include_subdirs establish ownership; transitive dependencies, sibling stanzas and comments grant nothing. Pathnames never grant permission.

The shipped allow-list is empty. Explicit --allow remains supported, but no wrapper, Door, library, tool or pathname receives a default exception.

## What this does not cover

Only literal Dune library/executable/test stanzas, modules selectors and include_subdirs are interpreted. Included/generated Dune forms, variables and conditional dependency expressions are not evaluated and do not grant minting. Source identity can miss opaque re-exports; typed evidence resolves compiler paths.

[Violating fixture](<../../test/caps/rules/violating/mint.ml>) and
[clean fixture](<../../test/caps/rules/clean/mint.ml>) form the rule/fixture/page triangle, checked by --self-check.

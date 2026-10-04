# ox-caps-forge

^ncapslint-nf4t ^ncapslint-8jcy ^ncapslint-x3gi

## Definition

Obj.magic is rejected in every checked implementation: an unchecked cast cannot create genuine capability authority. The shipped per-rule allow-list is empty, including the former reserved trusted-cast path.

The shipped allow-list is empty. Explicit --allow remains supported, but no wrapper, Door, library, tool or pathname receives a default exception.

## What this does not cover

This rule resolves Obj.magic references, including aliases. It does not establish the safety of foreign primitives, arbitrary external casts or code absent from the typed tree. Source-only identity has no whole-program view.

[Violating fixture](<../../test/caps/rules/violating/forge.ml>) and
[clean fixture](<../../test/caps/rules/clean/forge.ml>) form the rule/fixture/page triangle, checked by --self-check.

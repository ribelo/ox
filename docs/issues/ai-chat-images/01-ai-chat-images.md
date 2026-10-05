---
status: completed
package: ox_ai_chat
consumer: Leash pilot picture input (pic-k4ij, etagap-qq75)
---

# Typed image parts in chat requests

## Problem Statement

Leash's pilot needs a screenshot as an image part, not base64 embedded in page text
(pic-k4ij). Ox chat messages accept only strings, so the planner owns a second content
model, PNG base64 encoding and a direct `Ox_ai.Transport.post_json` call with an 8 MiB
request bound (etagap-qq75). That protocol work belongs in Ox.

## Solution

`ox_ai_chat` request messages carry ordered text and image-URL parts. Text-only messages
retain the existing string wire format; messages containing an image use OpenAI's content
array. Pure constructors cover a text message and a PNG data URL or image part.
`Chat.complete` remains the single completion call, with string-only replies.

## User Stories

1. As a planner author, I want ordered text and image-URL parts on a request message, so
   that a screenshot reaches the model as an image beside its prompt. ^nimg-4k7p
2. As a planner author, I want PNG bytes converted into a data URL or image part by a
   pure helper, so that I do not maintain my own base64 encoder. ^nimg-b2u8
3. As a text-helper author, I want a one-line text message constructor and unchanged
   text-only request bytes, so that image support does not alter existing calls. ^nimg-t9q3
4. As a codec consumer, I want `request_of_yojson` to read both string and part-array
   content, so that requests round-trip and malformed parts are refused. ^nimg-r6w1
5. As a planner author, I want one `Chat.complete` call with text and PNG parts returning
   string content and usage, so that I can drop the hand-built transport call without
   weakening reply decoding or request bounds. ^nimg-c8v5

## Implementation Decisions

- `Types.content_part` is `Text of string | Image_url of string`; image URLs may be
  HTTPS or data URLs. No fetching or URL validation is added. Request `Types.message`
  carries a part list; `Types.reply_message` keeps required string content, and choices
  use only that reply type (^nimg-4k7p ^nimg-c8v5, preserving ^nchat-wtog).
- All-text lists concatenate without separators and encode as a plain string, including
  the empty list as an empty string. A list containing any image encodes every part in
  order as `{"type":"text","text":...}` or
  `{"type":"image_url","image_url":{"url":...}}` (^nimg-4k7p ^nimg-t9q3).
- Wire records stay derived per ADR-0008; only the string-or-array content codec is
  custom. String decoding produces one text part; array decoding preserves boundaries.
  An all-text list therefore round-trips through its concatenated wire string, not its
  original segmentation (^nimg-r6w1).
- `Types.text_message`, `Types.png_data_url` and `Types.image_png` are pure. The PNG
  helper reuses `Ox_http.Ws_base64.encode_string`, already available through the existing
  `ox_http` dependency; no encoder move or new dependency is needed (ADR-0005/0007).
  Bytes are encoded as supplied, without inspecting PNG headers (^nimg-b2u8 ^nimg-t9q3).
- `Chat.complete` keeps its arguments. `Chat.create ~max_request_bytes:(8 * 1024 * 1024)`
  is the existing way Leash allows large image requests; defaults, transport policy and
  string-only reply decoding are unchanged (^nimg-c8v5).
- Migrate only callers in Ox. Leash and other consuming repositories are inspected
  read-only and migrate separately. Interface contracts cite these stories.

## Testing Decisions

- One named offline test per story under `test/ai/test_chat.ml`, using the existing fake
  chat server for wire and completion assertions.
- Assert exact compact image-request JSON with text/image/text/image order, exact base64
  for known bytes (including padding), and exact unchanged text-only request bytes.
- Decode and re-encode both forms; refuse unknown/missing/wrongly typed content parts.
- Complete an image request with the existing configurable bound, check content and usage,
  and reject array/null/missing reply content without retry (^nchat-wtog). Existing text
  tests remain unchanged except their shared message constructors.
- Run install, full tests, formatting and caps gates; no live provider test is needed.

## Out of Scope

JSON, audio and video parts; image detail settings; URL fetching or validation; PNG
validation; tools; streaming; multipart replies; new request-size knobs; migration of Leash
or any other consumer repository.

## Verified

All four required gates passed with exit code 0: `nix develop -c dune build @install`,
`nix develop -c dune test`, `nix develop -c dune build @fmt` and
`nix develop -c scripts/caps-gate`. The capability gate reported zero findings, zero typed
undecided modules and zero tracked-source coverage holes.

The chat suite has 34 cases, including one named case for each image story: exact ordered
image JSON (^nimg-4k7p), binary PNG base64 and padding (^nimg-b2u8), unchanged text wire
bytes (^nimg-t9q3), both request forms and malformed parts (^nimg-r6w1), and completion,
usage, request bounds and string-only fail-closed replies (^nimg-c8v5). The bounds case
refuses an image request above the default 4 MiB without opening a socket, then accepts
the same request through the existing 8 MiB configuration. Existing text cases pass;
the live smoke remains opt-in and was not run.

Only Ox callers were migrated. Other-repository `Ox_ai_chat` usage was found in Leash;
its planner workaround and text-helper callers remain untouched for their own migration.

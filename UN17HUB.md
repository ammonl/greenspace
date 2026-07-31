# UN17HUB.md — Shared Rules for the UN17 Village Sites

Synced to every repo under the `ammonl` account and the `AmmonLarson`
organization, so a new UN17 site picks these rules up without anyone extending a
list. If you are reading this in a repo that is not one of the UN17 sites below,
it does not apply to you.

`CLAUDE.md` still applies; this file adds what is true of the UN17 family
specifically and overrides `CLAUDE.md` where the two conflict. A repo's own
`AGENTS.md` overrides both.

## The family

These sites are built and maintained together, and residents move between them
as one thing. The repos:

| Repo             | Site                      | What it does                               |
| ---------------- | ------------------------- | ------------------------------------------ |
| `un17hub`        | `un17hub.com`             | FAQs, references, manuals; the shared docs |
| `un17-calendar`  | `calendar.un17hub.com`    | Printable community calendar               |
| `loppemarked`    | `loppemarked.un17hub.com` | Flea-market table booking                  |
| `greenspace`     | `greenspace.un17hub.com`  | Rooftop planter-box registration           |
| `un17-resources` | `resources.un17hub.com`   | Greenhouse use plans                       |
| `pictionary`     | `pictionary.un17hub.com`  | Sketch17, the drawing-and-guessing game    |
| `potluck`        | `potluck.un17hub.com`     | Shared-meal sign-up sheets                 |

## The shared About / Privacy / Terms pages live in `un17hub`

`un17hub.com/about/`, `/privacy/`, and `/terms/` are the canonical About,
Privacy Policy, and Terms of Service **for all of these sites**, in English and
Danish. Each app has a section with a stable anchor — `#hub`, `#calendar`,
`#loppemarked`, `#greenspace`, `#resources`, `#sketch17`, `#potluck` — so an app
can deep-link its own subsection (`https://un17hub.com/privacy/#potluck`).

**Those pages state facts about your app, and they live in another repo.** They
go stale silently: nothing in your repo's tests will fail when your change makes
the privacy page wrong.

So when a change alters any of the following, update the shared pages in
`un17hub` as part of the same piece of work — not as a follow-up:

- what the app is for, or who may use it
- whether there is a sign-in, and what kind
- what personal data is stored, or what is dropped
- what other residents can see
- which third-party providers are involved
- the rules residents are expected to follow (eligibility, one-per-apartment
  limits, waiting-list order, cancellation)
- how someone deletes their data, or asks you to

If you cannot open a PR against `un17hub` in the same session, say so plainly in
your PR description and file a ticket against `un17hub` describing the exact
change needed and the anchor it belongs under. Do not leave it implicit.

The anchors are a published interface: `un17hub`'s `tests/check_doc_anchors.js`
fails if one disappears, so link them freely, and coordinate a rename.

## Check the siblings — do not infer them

When a feature, functional change, or instruction update may affect sibling
repos, **request access to those repos and read them.** Being unable to see a
repo is not a reason to write what it probably does.

This is a real failure mode, not a hypothetical: the shared pages initially
described `loppemarked` as a read-only information page with no form, because
the session had the static info page inside `un17hub` in front of it and never
fetched the `loppemarked` repo, which is a booking platform storing names,
emails, and addresses.

- Derive per-app claims from that app's own code — its types, routes,
  validators, and migrations — rather than from its README or another repo's
  description of it. Repo docs go stale; the shipped code does not.
- A component existing is not the feature shipping. Check that it is actually
  imported and reachable before describing it to residents.
- Where a fact cannot be verified, write it as unknown and track it, rather
  than filling the gap with something plausible.

Sibling changes worth checking for: shared anchors and links, the
`@un17/logo` component and its required fonts, bilingual (English/Danish)
copy conventions, and anything the shared docs assert.

## Bilingual by default

Every resident-facing surface is English and Danish. A change that adds or edits
user-visible text in one language is not finished until the other is done —
including the shared pages, where a missing Danish string means a Danish reader
gets an English one or nothing at all.

## The shared logo

The animated `<un17-logo>` comes from the `un17-brand` repo, published as
`@un17/logo` and loaded from a CDN at a pinned version. It draws its wordmark in
**Amatic SC** and **Caveat**, so a page that uses the component must load those
fonts as well as its own body faces — otherwise the mark renders in fallback
faces and looks broken. Check an existing page's font `<link>` before adding a
new one.

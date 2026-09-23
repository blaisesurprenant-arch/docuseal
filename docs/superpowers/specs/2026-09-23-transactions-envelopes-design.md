# Transactions & Envelopes — Design Spec

Date: 2026-09-23
Status: Approved for planning

## Purpose

Add a "transaction" concept to this DocuSeal fork, sitting alongside the
existing Templates/Submissions system. A transaction represents a real-world
deal (e.g. "123 E Main St Unit A") with a defined set of parties. From a
transaction you build one or more "envelopes" — bundles of documents drawn
from the template library, combined into a single signing session, sent to
a chosen subset of the transaction's parties.

Success looks like: creating a transaction, adding parties with contact info
once, then repeatedly sending different document bundles to different
combinations of those parties over the life of the deal, without re-entering
contact info or re-selecting documents from scratch each time.

## Out of scope

- Native multi-template support in `Submission` itself (rejected approach,
  see Approach section below) — envelopes work via template merging instead.
- Per-document, per-party field visibility within a single envelope. If a
  document needs a different party combination than the rest of the
  envelope, it goes in a separate envelope instead (see Core Flows).
- Changing how signing, PDF generation, audit trails, or webhooks work.
  Envelopes produce a normal `Submission` and ride on all of that unchanged.

## Chosen approach: merged synthetic template per envelope

DocuSeal's `Submission` model belongs to exactly one `Template`. To bundle
several templates into a single signing session without touching that core
assumption, building an envelope clones the selected templates' documents,
schema, and fields into one new merged `Template` record (reusing the
existing `Templates::Clone` / `Templates::CloneAttachments` machinery), then
creates a `Submission` from that merged template exactly as DocuSeal does
today for any submission. This keeps the entire signing pipeline (field
editor, signing ceremony, completed-PDF assembly, audit trail, webhooks)
untouched — envelopes only change what feeds into it.

Two other approaches were considered and rejected:
- **Native multi-template submissions** (join table + teaching the signing
  pipeline to span N templates) — touches PDF generation, field lookup,
  progress tracking, and API serializers throughout a large codebase that
  currently assumes one template per submission everywhere. High risk, and
  every future `git merge upstream` would risk conflicting with these
  changes.
- **Separate submissions grouped under one label** — simplest to build, but
  each party would get separate signing links/emails per document instead
  of one bundled signing session, which was explicitly ruled out in favor
  of a single combined signing experience.

## Data model

**`Role`** (global, per-account list)
- `name` (string, unique per account)
- The shared vocabulary both transaction parties and template role
  placeholders draw from.

**`Transaction`**
- `name` (e.g. "123 E Main St Unit A")
- `status`
- `account_id`, `created_by_user_id`
- `has_many :transaction_parties`
- `has_many :envelopes`

**`TransactionParty`**
- `belongs_to :transaction`
- `belongs_to :role`
- `party_type` (enum: `individual` / `business`)
- Individual fields: `first_name`, `last_name`
- Business fields: `company_name`, `signer_first_name`, `signer_last_name`,
  `signer_title`
- Shared fields: `email`, `phone`, `address` (street/city/state/zip),
  `mailing_address` (same shape, nullable — null means "same as address")

**`Envelope`**
- `belongs_to :transaction`
- `belongs_to :template` (the merged/synthetic template built for this
  envelope — distinct from any master template in the library)
- `belongs_to :submission, optional: true` (set once sent)
- `name`
- `status` (enum: `draft` / `sent` / `completed` / `voided`)

**`EnvelopeSourceTemplate`** (join, provenance only)
- `belongs_to :envelope`
- `belongs_to :source_template, class_name: 'Template'` (the original
  master template this envelope's merge pulled from)
- `position` (order the documents were combined in)

**`EnvelopePart`** (join)
- `belongs_to :envelope`
- `belongs_to :transaction_party`
- Records which of the transaction's parties are actually included in this
  specific envelope.

## Core flows

### Creating a transaction

New "Transactions" area → "New Transaction": name it, then add parties one
at a time. For each party: pick a `Role` from the global list, or type a
new one (which gets appended to the global list for reuse on future
transactions). Toggle Individual/Business, fill in the relevant contact
fields. A transaction can be created with zero parties and have them added
later; parties can also be edited after the fact.

### Building an envelope

From a transaction's page, "New Envelope" → pick one or more templates from
the library to include. For each template picked, its baked-in role
placeholders (e.g. "Buyer", "Seller") are matched against the transaction's
existing parties by exact name. Any placeholder that doesn't match an
existing party's role blocks that template from being added until the user
either adds a new party for that role or maps the placeholder to a
different existing party. Once every selected template's roles resolve to
real parties, the user picks which of those resolved parties are actually
included in *this* envelope — defaults to "all of them," narrowable to
exclude some (e.g. sending an inspection addendum only to the Buyer). If a
different combination of documents/parties is needed later, that's a new,
separate envelope on the same transaction, never a partial exception within
one envelope.

### Merging and sending

On confirm, a merge service:
1. Clones each selected template's documents, schema, and fields
   (`Templates::Clone` / `Templates::CloneAttachments`).
2. Remaps attachment UUIDs across the clones to avoid collisions.
3. Unifies same-named role placeholders across the merged documents into
   single submitter slots (safe because roles are shared vocabulary — see
   Role model above).
4. Creates one new `Template` row representing the merged envelope
   document set, and records provenance via `EnvelopeSourceTemplate` rows.

A `Submission` is then created from that merged template exactly as
DocuSeal does today for any manually-built submission, with submitters
populated from the included `TransactionParty` records — contact info
(name/email/phone/address) prefilled into any field whose name matches the
prefill convention (see Autofill Convention below) — and sent through the
normal DocuSeal send flow as one bundled signing session.

### Tracking

The transaction detail page lists every envelope ever built for it
(draft/sent/completed/voided), each linking through to its underlying
Submission's existing DocuSeal tracking page (signing progress, audit
trail) rather than duplicating that UI. This makes the transaction the
single place to see every document bundle ever sent for a given deal,
including later addenda as new envelopes.

## Autofill convention

Contact-info prefill works by matching a party's contact fields
(name/email/phone/address/mailing address/company/title, as applicable to
`individual` vs `business`) to merged-template fields by field *name*, using
a fixed vocabulary (e.g. a field literally named "Email" for a given
submitter role gets that party's email). This is the same "shared
vocabulary, matched by name, with a manual override available" pattern
already used for roles — template authors need to name autofill-eligible
fields using this convention for prefill to kick in; fields named anything
else are left for the signer to fill in manually as normal.

## UI / Navigation

- New top-level nav item **"Transactions"**, a peer to Templates and
  Submissions (not nested under either, since it consumes both).
- **Transactions list** — searchable list of transaction names + status,
  same pattern as the existing Templates/Submissions dashboards.
- **Transaction detail page** — parties (add/edit) and envelopes (status +
  link into the underlying Submission's tracking page).
- **New Envelope** — a guided multi-step flow living on the transaction
  detail page: pick templates → resolve/confirm roles → confirm included
  parties → review → send.
- **Roles settings page** — lists the global role vocabulary (rename/remove
  unused ones), mirroring the existing Template Folders settings pattern.

## Error handling / edge cases

- **Unresolvable role at envelope-build time** — blocks that template from
  being added until mapped or a new party is added. Never silently drops
  fields for an unmapped role.
- **Renaming/deleting a global Role** — template placeholders are role-name
  strings baked into each template's `submitters` JSON, not a live foreign
  key, so renaming a Role does not retroactively rename existing templates'
  placeholders. Not a hard blocker — it just means a stale name resolves
  via the same "unresolved role" prompt at next envelope-build time, one
  extra click to remap.
- **Editing a party's contact info after an envelope is already sent** — no
  retroactive effect; prefill values are baked into the Submission at send
  time (matches DocuSeal's existing submission behavior). Only affects
  *future* envelopes on that transaction.
- **Editing/archiving a master template after it's been used in an
  envelope** — safe, no effect on already-built envelopes, since each
  envelope's merged template is an independent clone. This is the intended
  "duplicated into the transaction" behavior.
- **Draft envelopes** — the guided build flow can be saved mid-way and
  resumed, mirroring DocuSeal's existing draft-submission behavior.
- **Voiding a sent envelope** — reuses DocuSeal's existing
  archive/void-submission mechanism, reflected on the envelope's status.

## Testing approach

- Model specs for the new associations/validations (`Role`, `Transaction`,
  `TransactionParty`, `Envelope`, `EnvelopeSourceTemplate`, `EnvelopePart`).
- Unit spec on the merge service: combining N templates' documents/schema/
  fields into one, verifying role-name unification and no attachment-UUID
  collisions.
- Request/system spec covering the guided envelope-build flow, including
  the unresolved-role branch.
- Follows this codebase's existing RSpec + FactoryBot conventions rather
  than introducing a new test style.

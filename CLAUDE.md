# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Single-tenant Rails 8.1 / Ruby 4.0 invoicing app. SQLite everywhere, no Redis, no Node (Propshaft + importmap). See `README.md` for features and the MCP setup.

## Commands

```bash
bin/setup                                    # install gems, prepare databases
bin/dev                                      # dev server
bin/rails test                               # unit + integration (Minitest, parallel)
bin/rails test test/models/invoice_test.rb:42  # one test by line
bin/rails test:system                        # Capybara + headless Chrome
bin/rubocop                                  # rubocop-rails-omakase
bin/brakeman --no-pager
bin/ci                                       # full local pipeline (config/ci.rb)
```

`bin/ci` also runs `RAILS_ENV=test bin/rails db:seed:replant`; GitHub CI does not, so broken seeds pass PR checks. CI's `validate-ubl` job runs `test/builders/ubl_invoice_builder_test.rb` against the JP PINT validator, whose assets come from `bin/fetch-ubl-assets`.

## Architecture

- **Invoice lifecycle** (`app/models/invoice.rb`): `draft → preparing → sent → paid`, with `failed` as the delivery-error state (`retry_delivery!` back to preparing, or `revert_to_draft!`). `InvoiceDeliveryJob` calls `deliver!`, which creates a Stripe Checkout session for card clients, renders the PDF through `CloudflarePdfGateway`, builds UBL XML with `UblInvoiceBuilder`, attaches both, marks it sent, then mails it. The job's `retry_on`/`discard_on` list decides which external errors mark the invoice failed.
- **Invariants enforced by validations:** a non-draft invoice is frozen except payment and reminder fields; sent and paid invoices must have both `pdf` and `ubl_xml` attached (tests use `attach_deliverables` from `test/test_helper.rb`); totals recalculate only while draft; invoice numbers come from `Business#next_invoice_number` under a row lock. Line item descriptions are snapshotted, so copy edits never change issued invoices.
- **Monthly generation:** `InvoiceGenerationJob` (`config/recurring.yml`, 1st of the month) builds invoices from active retainers plus unbilled `ExtraHour`s; billed extra hours become immutable.
- **Singletons via `Current`:** `Business` is a single record; `Current.user` comes from the session cookie (`Authentication` concern).
- **Token APIs:** `ApiTokenAuthentication` authenticates bearer tokens, and each controller declares the purpose it accepts (`requires_api_token :chrome_extension` for `Api::*`, `:agent` for `McpController`). A token with the wrong purpose gets 403.
- **MCP server:** `POST /mcp` (`McpController`) wraps the `mcp` gem's Streamable HTTP transport, stateless. Tools live in `app/tools/` as `MCP::Tool` subclasses and get the token through `server_context`.
- **Audit trail:** PaperTrail on the domain models. Controllers that write must `before_action :set_paper_trail_whodunnit` after authentication (PaperTrail 17 does not add it), and `user_for_paper_trail` must return the user id: `whodunnit` is a string column.
- **Background jobs** run inside Puma (`SOLID_QUEUE_IN_PUMA`); Queue, Cache and Cable each have their own SQLite database.
- **Locales:** invoices render in the client's locale (`config/locales/invoice.{en,ja}.yml`).

## Conventions

- Enums are string-backed: `enum :status, %w[ draft sent ].index_by(&:itself)`. Never integer enums.
- Minitest with fixtures (`test/fixtures/`), Mocha for stubs, WebMock blocks outbound HTTP.
- System tests are timing-sensitive; read the notes in `test/application_system_test_case.rb` before blaming app code for a flake.
- The repo is public: fixtures, seeds and screenshots use fake data only.
- Merging to `main` deploys automatically (Kamal via GitHub Actions). Never run `bin/kamal deploy` by hand.

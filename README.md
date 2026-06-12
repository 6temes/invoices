<div align="center">

# Invoices

### Single-tenant invoicing for a freelance consultancy, built on Rails 8.

Clients · retainer contracts · extra-hours tracking · automated monthly invoices · Stripe payments · bilingual (EN/JA) PDF export · tax reporting.

[![CI](https://github.com/6temes/invoices/actions/workflows/ci.yml/badge.svg)](https://github.com/6temes/invoices/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Ruby](https://img.shields.io/badge/Ruby-4.0-CC342D.svg)
![Rails](https://img.shields.io/badge/Rails-8.1-D30001.svg)

[Features](#features) ◆ [Setup](#setup) ◆ [Testing](#testing) ◆ [Architecture](#architecture) ◆ [Deployment](#deployment)

</div>

---

A single-tenant Rails app that runs the billing for one freelance consultancy in Tokyo — from logging extra hours against a retainer, to generating the monthly invoice, taking payment, and exporting everything the accountant needs at tax time. It runs on a single VPS with SQLite, no Redis, and no Node.

## Features

- **Clients** — manage customers with addresses, locale (EN/JA), and payment method (bank transfer or credit card)
- **Retainers** — monthly contracts with hours, rates, and automatic invoice line item generation
- **Extra Hours** — log additional work from the UI or via a Chrome extension, automatically billed on the next invoice
- **Invoices** — create manually or generate monthly from active retainers; draft → sent → paid workflow
- **PDF Generation** — renders localized invoice HTML to PDF via Cloudflare Browser Rendering
- **Stripe Payments** — credit card clients get a Stripe Checkout link; a webhook handles payment confirmation
- **Email Delivery** — sends invoices as PDF attachments via Gmail SMTP
- **Tax Export** — CSV and ZIP (all PDFs) export by calendar year
- **Chrome Extension** — log hours directly from GitHub issues, matched to clients by repo
- **Bilingual** — invoices render in English or Japanese based on client locale

## Setup

> **Prerequisites:** Ruby 4.0 and SQLite. No Node.js — assets run on Propshaft + importmap.

```bash
bin/setup       # Install dependencies, prepare the database
bin/dev         # Start the development server
```

## Testing

```bash
bin/rails test          # Unit and integration tests (Minitest)
bin/rails test:system   # System tests (Capybara + headless Chrome)
bin/ci                  # Full pipeline: lint, security scan, tests, seeds
```

## Architecture

Everything is SQLite — application data plus the Solid trifecta (Queue, Cache, Cable) in separate databases. Background jobs run in-process inside Puma (`SOLID_QUEUE_IN_PUMA`), so there's no separate worker process to contend for the database. Litestream continuously replicates the SQLite files off-box for backup.

```
Browser ──Hotwire (Turbo + Stimulus)──► Rails 8.1 (Puma)
                                          ├─ Solid Queue (in-process jobs)
                                          ├─ Solid Cache / Solid Cable
                                          ├─ SQLite ──Litestream──► off-site backup
                                          ├─ Stripe Checkout (card payments + webhook)
                                          └─ Cloudflare Browser Rendering (HTML → PDF)
```

**Domain model**

- **Business** is a singleton (one record), accessed via `Current.business`.
- **Client** has a locale that sets invoice language and a payment method (bank transfer or credit card).
- **Retainer** is a monthly contract; one active retainer per client.
- **ExtraHour** records become immutable once billed to an invoice line item.
- **Invoice** flows draft → sent → paid; non-draft invoices are frozen except payment fields.

A recurring job generates the monthly invoices from active retainers on the 1st of each month.

## Deployment

Deployed with [Kamal](https://kamal-deploy.org) and Docker to a single VPS, behind a Cloudflare Tunnel. **CI/CD deploys automatically on merge to `main`** (GitHub Actions runs `kamal deploy`); infrastructure values come from GitHub Actions secrets, never from the repo. SQLite databases and Active Storage files persist on a mounted volume.

## Tech Stack

| Layer | Choice |
|---|---|
| Framework | Rails 8.1 |
| Language | Ruby 4.0 |
| Database | SQLite (+ Litestream backup) |
| Asset Pipeline | Propshaft + importmap-rails |
| Frontend | Hotwire (Turbo + Stimulus) |
| Background Jobs | Solid Queue (in-process) |
| Cache | Solid Cache |
| WebSockets | Solid Cable |
| PDF | Cloudflare Browser Rendering |
| Payments | Stripe Checkout |
| Email | Gmail SMTP (Action Mailer) |
| Error Monitoring | Rails Informant |
| Deployment | Kamal + Docker |
| CI | GitHub Actions |

## Contributing

This is a single-tenant app tailored to one business, open-sourced as a working reference for a no-Redis, no-Node, SQLite-on-one-box Rails 8 setup. It isn't built for multi-tenant use, but issues and pull requests are welcome — especially ones that sharpen the patterns above.

## License

Released under the [MIT License](LICENSE).

---

<div align="center">

Made in Tokyo with ❤️ and 🤖

</div>

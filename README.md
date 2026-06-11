# Invoices

A single-tenant Rails invoicing app for a freelance consultancy based in Tokyo. Manages clients, retainer contracts, extra hours tracking, automated monthly invoice generation, Stripe payments, PDF export, and tax reporting.

Built with Rails 8.1, Ruby 4.0, SQLite, Hotwire (Turbo + Stimulus), and Propshaft. Deployed with Kamal to a single VPS.

## Features

- **Clients** — manage customers with addresses, locale (EN/JA), and payment method (bank transfer or credit card)
- **Retainers** — monthly contracts with hours, rates, and automatic invoice line item generation
- **Extra Hours** — log additional work from the UI or via a Chrome extension, automatically billed on the next invoice
- **Invoices** — create manually or generate monthly from active retainers; draft → sent → paid workflow
- **PDF Generation** — renders localized invoice HTML to PDF via Cloudflare Browser Rendering
- **Stripe Payments** — credit card clients get a Stripe Checkout link; webhook handles payment confirmation
- **Email Delivery** — sends invoices as PDF attachments via Gmail SMTP
- **Tax Export** — CSV and ZIP (all PDFs) export by calendar year
- **Chrome Extension** — log hours directly from GitHub issues, matched to clients by repo
- **Bilingual** — invoices render in English or Japanese based on client locale

## Setup

```bash
bin/setup       # Install dependencies, prepare database
bin/dev         # Start development server
```

## Testing

```bash
bin/rails test          # Unit and integration tests (Minitest)
bin/rails test:system   # System tests (Capybara + headless Chrome)
bin/ci                  # Full CI pipeline: lint, security, tests, seeds
```

## Deployment

Deployed with [Kamal](https://kamal-deploy.org) via Docker. Configuration in `config/deploy.yml`. SQLite databases and Active Storage files persist on a mounted volume.

```bash
bin/kamal deploy    # Deploy to production
```

## Tech Stack

| Layer | Choice |
|---|---|
| Framework | Rails 8.1 |
| Language | Ruby 4.0 |
| Database | SQLite |
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

---

Made in Tokyo with ❤️ and 🤖

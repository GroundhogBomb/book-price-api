# Book Price API

English

A portfolio project that turns book pages from [Books to Scrape](https://books.toscrape.com/) into a versioned JSON API. Built with Ruby, Rails API-only, Mongoid, MongoDB Community, and a JavaScript client example. The source is a scraping practice site; its prices and ratings are synthetic.

**Scrape and store first, query later.** API requests read saved MongoDB snapshots and never fetch the website. `last_scraped_at` indicates when a book was last successfully saved. Scraping is manual; no scheduler or background service is required.

## Architecture

```text
Manual rake task
    |
BooksToScrape adapter (URL policy, Parser, dependency assembly)
    |
Fetcher: HTTP -> HTML
    |
Parser: HTML -> canonical raw fields
    |
Validator / Normalizer: raw fields -> validated, typed records
    |
BatchValidator: approve the entire page before any book write
    |
BookRepository: source + UPC upsert / legacy URL adoption
    |
MongoDB: books (snapshots) + scrape_runs (audit records)
    ^
    | queries only
GET /api/v1/books     -> filters / stable sorting -> v1 serializer -> JSON
GET /api/v1/books/:id ---------------------------> v1 serializer -> JSON
```

| Component | Interface and responsibility |
| --- | --- |
| `Scraping::HttpFetcher` | `get(url)` returns HTML or raises `NetworkError` with the final reason and attempt count. Receives a URL policy and settings. |
| Site Parser | `catalogue(html, url:)` returns `book_urls` and `next_url`; `book(html, url:)` returns canonical raw fields. Unrecognized structure raises `ParseError`; missing values remain nil for validation. |
| `Scraping::Normalizer` | `call(raw)` returns a frozen, typed hash or raises `ValidationError` with affected fields. Converts prices to integer cents, normalizes URLs, and validates values. No HTML, HTTP, or database access. |
| `Scraping::BatchValidator` | Evaluates page size, structural errors, and critical-field rejection rates. Returns acceptance, reasons, and warnings without writing data. |
| `Scraping::BookRepository` | `prepare!` maintains indexes; `upsert_from_scrape!(attributes)` persists by identity and safely adopts legacy documents. |
| `Scraping::RunRecorder` | Creates and finalizes one `ScrapeRun` per scrape. |
| API / `BookFilters` / v1 serializer | Validate query parameters, read MongoDB, and produce the public JSON contract. |

`Scraping::Runner` coordinates these interfaces without site selectors or references to a specific adapter. HTML changes belong in the affected site's Parser. A future source can provide its own Parser, URL policy, adapter entry point, and settings while reusing the shared pipeline. An offline fixture adapter tests this boundary; Books to Scrape remains the only real target.

## Design decisions

### Stable identity and legacy data

Books are identified by **`source + upc`**, not URL. The current source is `books_to_scrape`. UPC is read from the detail page and stored as a string, preserving leading zeros; this site's UPC should not be assumed to be a numeric retail barcode. A changed URL updates the same source/UPC document.

Index preparation creates a partial unique compound index for documents whose source and UPC are strings, creates an ordinary URL lookup index, then removes legacy URL uniqueness. It does not delete documents and can run repeatedly.

When a valid scrape matches a legacy URL with no UPC, persistence fills in the identity in place, retaining `_id` and `created_at`. Ambiguous legacy matches or identity conflicts are reported without merging or deleting records. Documents outside a successful batch remain unchanged. Missing legacy `source`, `upc`, and `stock_quantity` values serialize as `null`.

Prices are stored as integer `price_cents` and returned as numeric `price` with `currency` (GBP for this site). `stock_quantity` is a nullable integer: an unspecified quantity stays null rather than being inferred from the availability flag. Books missing from a later scrape are not automatically removed.

### Whole-page validation

All detail pages in a catalogue batch are fetched, parsed, and normalized **before any book in that batch is written**.

- An empty catalogue or an unrecognized catalogue structure is rejected. An unreadable catalogue stops pagination because its next link is unknown.
- Any unrecognized detail-page structure rejects the batch. Subsequent catalogue pages can still be processed when their links are known.
- A batch is rejected when **at least 25%** of successfully fetched details have missing or invalid price, rating, or UPC. Network failures are not counted as missing fields.
- Below that threshold, invalid individual books are rejected and valid books may be saved. A batch with no valid records is also rejected.
- The expected page size of 20 is advisory, never a rejection rule by itself.

Rejected batches do not change existing book values, identities, or timestamps. This is a validation gate, not a database transaction: a database failure after approval may leave successful writes in place. Identity-based upserts make retrying safe.

### Failure classification and audit

Each `ScrapeRun` stores source, start/end times, status, fetched-page and saved-book counts, rejected batches, classified failures, reasons, warnings, the page-limit flag, and a settings snapshot. The rake summary includes its `run_id`.

Categories are `network`, `parse`, `validation`, `persistence`, and `internal`. Failure entries include `kind`, `url`, `reason`, and `scope`; exhausted network failures include `attempts`. Rejected individual books are recorded under `validation`, with `scope=book` and affected `fields`, rather than only being logged. A field rejection and a batch rejection are separate events. Intermediate retries are logged without being counted as additional failed books.

Statuses are `running`, `completed`, `completed_with_errors`, or `failed`. Failed or interrupted runs must not be treated as successful; abrupt process termination or database unavailability may leave a `running` record. `pages_fetched` counts retrieved catalogue pages; `books_saved` includes updates. Any final failure causes the rake task to exit nonzero.

### Additive-only v1 contract

`GET /api/v1/books` and `GET /api/v1/books/:id` share these frozen field names and existing types:

`id`, `title`, `price`, `currency`, `rating`, `in_stock`, `url`, `category`, `last_scraped_at`, `source`, `upc`, `stock_quantity`.

v1 may add fields but may not rename, remove, or change existing fields or their meaning. Contract tests lock the output sets; additive changes must retain existing assertions. Missing identity/quantity fields remain null. IDs are strings, timestamps are ISO 8601 strings or null, and quantity is an integer or null.

List responses retain `data` and `meta` (`page`, `per_page`, `total`, `total_pages`); detail responses retain `data`, and errors retain `error`. Unversioned book routes are removed. `/up` remains a process health check, not a database or source-site readiness check.

## Installation

Requires Ruby >= 3.3, Rails 8.0, Mongoid 9, and MongoDB Community 8.0. `Gemfile.lock` pins application dependencies; `.ruby-version` records the development Ruby version. Active Record and SQL databases are not used.

macOS with Homebrew:

```sh
brew install ruby@3.4
brew tap mongodb/brew
brew trust mongodb/brew
brew install mongodb-community@8.0

# Run in each new terminal; leave the system Ruby unchanged.
export PATH="$(brew --prefix ruby@3.4)/bin:$PATH"
bundle install
```

The default URI is `mongodb://127.0.0.1:27017/book_price_api_development`. Export `MONGODB_URI` to override it. `.env.example` documents settings; the application does not automatically load `.env`. Production requires explicit `MONGODB_URI` and `SECRET_KEY_BASE` values. Never commit real credentials.

## Start and stop

From the repository root:

```sh
bin/mongo-start
bin/rails server -b 127.0.0.1
```

The API is available at `http://127.0.0.1:3000/api/v1/books`; the list is empty until books have been scraped. Stop Rails with `Ctrl-C`, then run:

```sh
bin/mongo-stop
```

Low-resource defaults use one Rails process with two threads and a MongoDB WiredTiger cache of 0.25GB. Total MongoDB memory may exceed that cache limit. MongoDB binds only to `127.0.0.1:27017`; data, logs, and PID files stay in ignored `storage/`, `log/`, and `tmp/` directories. Do not use `brew services start` or register startup services. Investigate port conflicts without stopping unrelated processes.

See [Environment and Resource Defaults](docs/environment.md) for details.

## Scrape

With MongoDB running, use another terminal with Homebrew Ruby selected:

```sh
# Follow all catalogue pages and fetch their detail pages.
bundle exec rake books:scrape

# Limit the run to the first two catalogue pages.
MAX_PAGES=2 bundle exec rake books:scrape
```

A full-site run can take many minutes because every book requires a detail request. Successful repeat scrapes update existing identities. Valid legacy records are adopted automatically, so no separate network migration command is needed.

Settings live in [`config/scraping.yml`](config/scraping.yml):

| Setting | Default |
| --- | --- |
| Open / read / write timeout | 10 / 20 / 10 seconds |
| `max_attempts` | 3 total attempts, including the initial request |
| `interval` | At least 1 second after each request completes |
| `user_agent` | `BookPriceAPI/1.0 (educational portfolio scraper; books.toscrape.com only)` |
| `max_pages` | null for all pages; optional positive-integer `MAX_PAGES` override |
| `critical_rejection_ratio` | 0.25 |
| `expected_page_size` | 20, warning only |

The summary contains `pages_fetched`, `books_saved`, `batches_rejected`, `failure_counts`, `failures`, `warnings`, `limited`, and `run_id`. `limited=true` means the configured limit was reached while another page remained. Reasons are also logged to the Rails environment log.

## API examples

Filters can be combined and include their numeric boundaries:

| Parameter | Accepted values | Default |
| --- | --- | --- |
| `min_price`, `max_price` | Nonnegative amount, up to 8 integer digits and 2 decimals; min must not exceed max | Unrestricted |
| `min_rating` | Integer 1–5 | Unrestricted |
| `in_stock` | Exactly `true` or `false` | Unrestricted |
| `category` | Case-sensitive exact name, such as `Poetry` or `Romance` | Unrestricted |
| `sort` | `price_asc`, `price_desc`, `rating_asc`, `rating_desc`, `title_asc`, `title_desc` | URL ascending |
| `page` | Integer 1–1000000 | 1 |
| `per_page` | Integer 1–100 | 20 |

All sort modes use `_id` ascending as the final tie-breaker for stable pagination on an unchanged dataset. Unknown sort values and invalid scalar, array, or object parameters return JSON 400. Database unavailability returns JSON 503.

```sh
curl 'http://127.0.0.1:3000/api/v1/books?min_price=10&max_price=30&min_rating=3&in_stock=true&sort=price_asc&page=1&per_page=2'
curl 'http://127.0.0.1:3000/api/v1/books?category=Poetry&sort=rating_desc'
```

Response shape (illustrative, not the result of the filters above; replace the placeholder ID with a returned ID):

```json
{
  "data": [{
    "id": "<book-id>",
    "title": "A Light in the Attic",
    "price": 51.77,
    "currency": "GBP",
    "rating": 3,
    "in_stock": true,
    "url": "https://books.toscrape.com/catalogue/a-light-in-the-attic_1000/index.html",
    "category": "Poetry",
    "last_scraped_at": "2025-01-01T00:00:00Z",
    "source": "books_to_scrape",
    "upc": "a897fe39b1053632",
    "stock_quantity": 22
  }],
  "meta": {"page": 1, "per_page": 20, "total": 1, "total_pages": 1}
}
```

No matches or a page beyond the results returns an empty `data` array. Fetch a detail with an actual returned ID:

```sh
curl 'http://127.0.0.1:3000/api/v1/books/<book-id>'
```

Details use `{"data": {...}}`; missing or malformed IDs return JSON 404. The JavaScript example uses Node.js >= 18 with built-in `fetch` and no npm dependencies:

```sh
node examples/books.mjs 30 3
```

## Testing

Start MongoDB on demand, then run:

```sh
bundle exec rails test
```

Tests use saved HTML and in-memory adapters. External HTTP requests are blocked, and tests run sequentially against the fixed local `book_price_api_test` database, ignoring `MONGODB_URI` to protect other data. Coverage includes parsing, normalization, batch guards, retries, identity/index migration, audit records, source interfaces, the v1 contract, filters, sorting, pagination, errors, and health checks.

See [Testing & Verification](docs/verification.md) for coverage and focused test commands. Stop MongoDB when finished.

## Responsible scraping

- Only scrape the designated practice site, `https://books.toscrape.com/`.
- Send a clear User-Agent and wait at least one second between requests, including retries.
- Do not use proxies, CAPTCHA bypass, anti-bot evasion, redirects, or alternate hosts.
- Retry network failures, HTTP 429, and 5xx responses within the configured attempt limit. Do not retry 404 or follow redirects; implicit HTTP retries are disabled.

## Known limitations

- Data is a saved snapshot, not real-time availability or market pricing; the source is synthetic.
- Only one real source is implemented. The second-source adapter exists only as an offline interface test.
- Batch validation is not a database transaction. Successful writes survive later persistence failures.
- Missing source books are not automatically deleted; ambiguous legacy matches require manual resolution.
- Pagination is stable for an unchanged dataset, not a cross-request snapshot during concurrent updates.
- Abrupt termination can leave an unfinished audit record. `/up` checks the Rails process only.
- AWS Linux deployment and load testing are outside the current implementation.

Collaboration rules are documented in [AGENTS.md](AGENTS.md).

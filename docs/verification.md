# Testing & Verification

The test suite exercises the pipeline and API using saved HTML and in-memory adapters. It requires a local MongoDB instance but does not fetch the source website.

## Run the suite

From the repository root with Homebrew Ruby selected:

```sh
export PATH="$(brew --prefix ruby@3.4)/bin:$PATH"
bundle install
bin/mongo-start
bundle exec rails test
bin/mongo-stop
```

Tests run sequentially to limit resource use and avoid cleanup races. The test configuration uses only `mongodb://127.0.0.1:27017/book_price_api_test`, ignores `MONGODB_URI`, and checks the database name before cleanup. Book and audit data created by the suite is removed from that test database; development data is not cleared.

HTTP requests are blocked by the test helper. Parser tests read saved files under `test/fixtures/files/`; HTTP tests inject a fake transport and clock. Database tests use MongoDB to exercise real indexes and persistence behavior.

## Coverage

| Area | Behavior checked |
| --- | --- |
| HTML parsing | Catalogue links and pagination, canonical raw detail fields, UPC, availability, quantity, Unicode text, missing fields, and unrecognized structures. |
| Normalization | Integer cents, ratings and quantities, nullable quantities, URL normalization, required fields, invalid values, and inconsistent stock information. |
| HTTP boundaries | Request spacing including retries, bounded attempts, final network errors, rejected hosts/schemes/ports, and no redirect following. |
| Page validation | Empty catalogues, changed detail structure, critical-field failures at or below the rejection threshold, advisory page sizes, and preservation of existing documents after rejection. |
| Identity and persistence | Unique source/UPC pairs, repeated scrapes, changed URLs, distinct sources, partial indexes, legacy URL adoption, retained identifiers/timestamps, and ambiguous matches without data loss. |
| Audit records | Start/end times, statuses, saved-book counts, classified failure reasons, retry attempts, and interrupted runs marked as failed. |
| Source interfaces | An offline adapter reuses shared normalization, validation, persistence, and serialization without changing the real source adapter. |
| API contract | Exact v1 field sets for lists and details, existing types, null new fields on legacy documents, and removed unversioned routes. |
| Queries | Combined filters, inclusive price/rating boundaries, explicit false availability, all whitelisted sorts, deterministic tie-breaks, pagination metadata, and empty result pages. |
| Errors and health | Invalid parameters returning JSON 400, malformed/missing IDs returning JSON 404, and the retained `/up` route. |

Rejected individual books are represented as `validation` events with `scope=book`, their URL, affected fields, and a reason. Batch rejection is a distinct event and must occur before any book writes for that batch.

## Focused checks

Run only the relevant files when investigating a failure:

```sh
bundle exec rails test test/services/books_to_scrape/parser_test.rb
bundle exec rails test test/services/scraping/normalizer_test.rb
bundle exec rails test test/services/scraping/pipeline_test.rb
bundle exec rails test test/models/book_test.rb
bundle exec rails test test/integration/books_contract_test.rb
bundle exec rails test test/integration/books_api_test.rb
```

Choose verification appropriate to the change. Documentation-only changes do not need a live scrape. After fixing a failing check, rerun the affected checks rather than repeatedly running unrelated verification.

## What these tests do not establish

Offline fixtures detect regressions against saved page structures; they do not establish that the live site still matches those fixtures. The suite does not establish production readiness, load capacity, or AWS deployment behavior. Batch validation protects against bad input but does not provide transaction rollback after a database failure.

`/up` checks whether Rails can respond, not whether MongoDB or the source website is available. Unfinished `running` audit records should not be interpreted as successful runs.

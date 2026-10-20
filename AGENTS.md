# Collaboration Rules

## Scope and architecture

- Use Ruby >= 3.3, Rails API-only, Mongoid, MongoDB Community, and JavaScript. Do not introduce Active Record, a SQL database, heavy dependencies, or background services without an explicit task requirement.
- Read this file, the README, and the current Git state before making changes. Ask for clarification when requirements or necessary information are unclear.
- Treat repository files as the source of truth. Do not import unrelated project, conversation, or personal context.
- Preserve the pipeline: Fetcher -> Parser -> Validator/Normalizer -> persistence. API requests query stored data and must not trigger scraping.
- Parsers extract canonical raw fields. Normalizers own business validation and type conversion, without reading HTML, performing HTTP, or writing to the database.
- Keep site selectors in the site's Parser. HTML changes should not require changes to shared HTTP, persistence, or API code.
- Shared `Scraping` code must not reference a concrete site module. New sources provide independent adapters and settings through the existing interfaces without changing other source modules or the API.

## Responsible scraping and data integrity

- The only authorized real target is `https://books.toscrape.com/`. Reject other hosts, non-HTTPS URLs, proxies, and redirects.
- Set a clear User-Agent and wait at least one second between requests, including retries. Do not bypass CAPTCHAs or anti-bot controls.
- Retry network errors within configured limits and record the reason. An individual book failure must not terminate the entire scrape.
- Support full-site pagination by default. Bounded manual checks may use the first two catalogue pages when requested.
- Persist title, price/currency, rating, availability, nullable stock quantity, detail URL, category, source, and UPC. Identity is `source + upc`, enforced by a partial unique index and atomic upserts. URL is an ordinary mutable field.
- Adopt legacy documents by compatible source and URL when UPC is missing, preserving their ID and creation time. Exclude unidentified records from identity uniqueness. Report ambiguous matches without deleting or forcibly merging documents.
- Fetch, parse, normalize, and validate the entire catalogue batch before writing any book in it. Reject empty batches and changed detail structures.
- Reject a batch when missing or invalid price, rating, or UPC affects at least 25% of successfully fetched details. Manage the threshold in `config/scraping.yml`. Below the threshold, reject invalid books individually; the expected page size of 20 is advisory only.
- Centralize timeouts, attempts, spacing, User-Agent, maximum pages, and batch settings in the configuration file.
- Record one `ScrapeRun` per scrape, with start/end times, status, counters, warnings, and failure reasons classified as `network`, `parse`, `validation`, `persistence`, or `internal`.
- Record rejected individual books as `validation` events with `scope=book`, URL, reason, and affected fields. Logs or a batch-level rejection alone are insufficient.
- A rejected batch must leave existing book data unchanged. Do not treat interrupted or unfinished audit records as successful runs.

## API compatibility

- Use `/api/v1/books` and `/api/v1/books/:id`; retain `/up`. Do not restore unversioned book routes.
- v1 is additive only. Do not rename, remove, change the type of, or change the meaning of existing fields: `id`, `title`, `price`, `currency`, `rating`, `in_stock`, `url`, `category`, `last_scraped_at`, `source`, `upc`, `stock_quantity`.
- Preserve list envelopes `data`/`meta` and metadata keys `page`, `per_page`, `total`, `total_pages`; preserve detail `data` and error `error` envelopes.
- Return null for missing new fields on legacy records. Do not fabricate source, UPC, or quantity. Additive changes must update contract tests while retaining assertions for existing fields.
- Validate query parameters and allow only whitelisted sort modes. Maintain a deterministic ID tie-breaker for pagination.

## Local resources and tests

- Use the designated Homebrew Ruby without replacing the operating system's Ruby.
- Start MongoDB only when needed and stop it afterward. Do not use `brew services start`, register startup services, or stop unrelated processes.
- Retain low-resource defaults; avoid unnecessary processes, containers, or dependencies.
- Tests use saved HTML or in-memory adapters and must not access external HTTP endpoints. Use only the isolated local test database for test cleanup; never clear development or production data.
- Keep verification proportional to the task. Run the full suite once when required, then rerun only affected failing checks after repairs. Documentation-only work does not require live scraping or extra API requests.
- Do not add independent agents or expand acceptance work without authorization.

## Public repository hygiene

- Keep tracked content free of developer home paths, local account or host names, personal contact details, unrelated project references, and recruiting-company names.
- Keep internal agent state under ignored `.codex/` local to the checkout. When removing it from tracking, preserve the local files.
- Never commit database files, backups, runtime logs, temporary files, real secrets, or `.env` files. `.env.example` must contain only non-sensitive examples.
- Public documentation describes behavior, usage, coverage, and limitations. Do not publish conversation history, acceptance diaries, local run statistics, or personal resource constraints.
- Distinguish synthetic test literals and public source data from personal information. Do not change application behavior during documentation or privacy cleanup.
- Treat actual private keys, sk-prefixed secrets, JWTs, AWS credentials, and random secret values as blockers. Permit placeholders, test literals, explanatory text, public identifiers, and dependency integrity checksums.

## Git and documentation

- Work on `main` and commit each completed work item with a descriptive message. Do not force-push, rewrite history, or overwrite unrelated work.
- Maintain `README.md` as the primary English guide and `README.zh-CN.md` as its Chinese companion, with reciprocal links and consistent technical content. Keep `docs/` in English.
- Document installation, process lifecycle, scraping, API usage, tests, architecture, and known limitations without presenting unimplemented features as complete.
- Summarize completed work concisely with commit hashes and material issues.

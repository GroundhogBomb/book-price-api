# Saved HTML Fixtures

The fixtures are saved pages from the designated scraping practice site:

- `catalogue.html`: https://books.toscrape.com/
- `book.html`: https://books.toscrape.com/catalogue/a-light-in-the-attic_1000/index.html

Tests read these files offline. Missing-field, availability, and pagination variants are derived from them in memory. The test suite does not download or refresh fixtures, and its helper blocks HTTP requests.

When updating a fixture, obtain it separately, review the HTML changes, and update the affected Parser tests. Keep source provenance and avoid adding local paths or personal metadata.

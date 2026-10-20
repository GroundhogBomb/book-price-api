// Node.js >= 18; uses built-in fetch with no extra packages.
// Usage: node examples/books.mjs [max_price] [min_rating]
const [maxPrice = "30", minRating = "3"] = process.argv.slice(2);
const url = new URL("/api/v1/books", process.env.BOOKS_API_URL || "http://127.0.0.1:3000");
url.search = new URLSearchParams({
  max_price: maxPrice,
  min_rating: minRating,
  in_stock: "true",
  page: "1",
  per_page: "5",
});
try {
  const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
  console.table(body.data);
  console.log("Pagination:", body.meta);
} catch (error) {
  console.error("API request failed:", error.message);
  process.exitCode = 1;
}

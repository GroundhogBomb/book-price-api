# Environment and Resource Defaults

## Dependencies

Use Ruby >= 3.3, Rails 8.0, Mongoid 9, and MongoDB Community 8.0. Application dependencies are pinned in `Gemfile.lock`; `.ruby-version` records the development Ruby version. The application uses Mongoid instead of Active Record and does not require a SQL database.

For macOS with Homebrew:

```sh
brew install ruby@3.4
brew tap mongodb/brew
brew trust mongodb/brew
brew install mongodb-community@8.0
export PATH="$(brew --prefix ruby@3.4)/bin:$PATH"
bundle install
```

Select Homebrew Ruby in each new terminal without replacing the operating system's Ruby. `bin/setup` installs missing application dependencies without starting services.

The JavaScript example requires Node.js >= 18 and uses built-in `fetch`. It needs no npm packages.

## Low-resource defaults

- Start MongoDB manually with `bin/mongo-start`; stop it with `bin/mongo-stop` after use.
- Do not register MongoDB with `brew services start`, launchd, or another startup service.
- MongoDB binds to `127.0.0.1:27017` and uses a 0.25GB WiredTiger cache. Total process memory can exceed the cache limit.
- Rails uses one process and two threads by default. `RAILS_MAX_THREADS` can override the thread count.
- MongoDB files live in `storage/mongodb/`, logs in `log/`, and PID files in `tmp/pids/`. These runtime files are ignored by Git.
- Stop Rails with `Ctrl-C` before shutting down MongoDB. Database contents remain on disk.
- If a port is occupied, identify the process before taking action; do not stop unrelated services.

## Configuration

The default development URI is `mongodb://127.0.0.1:27017/book_price_api_development`. Export `MONGODB_URI` to override it. `.env.example` is a reference, not an automatically loaded environment file.

Tests use the fixed local `book_price_api_test` database and ignore `MONGODB_URI`. Never direct destructive test cleanup at development or production databases.

Production mode requires explicit `MONGODB_URI` and `SECRET_KEY_BASE` values. Keep secrets out of Git. AWS Linux deployment is not implemented; the helper scripts above target local macOS development.

Scraping timeouts, attempts, interval, User-Agent, page limit, expected page size, and rejection threshold are centralized in [`config/scraping.yml`](../config/scraping.yml).

## References

- [Mongoid compatibility tables](https://www.mongodb.com/docs/drivers/compatibility/?driver-language=ruby&ruby-driver-framework=mongoid): framework, runtime, and server compatibility.
- [MongoDB installation on macOS](https://www.mongodb.com/docs/v8.0/tutorial/install-mongodb-on-os-x/): installation and manual process management.
- [MongoDB partial indexes](https://www.mongodb.com/docs/v8.0/core/index-partial/): conditional uniqueness for identified documents.
- [Rails community discussion of Mongoid](https://www.reddit.com/r/rails/comments/11yr6mc/): community experience with document modeling; use the official compatibility tables and locked dependencies for version requirements.

See the [main README](../README.md) for application usage.

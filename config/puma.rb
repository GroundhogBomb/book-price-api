# One process with a small thread pool for local development.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 2)
threads threads_count, threads_count
port ENV.fetch("PORT", 3000)
plugin :tmp_restart
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

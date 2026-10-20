require "net/http"
require "openssl"

module Scraping
  class HttpFetcher
    NETWORK_ERRORS = [Timeout::Error, SocketError, SystemCallError, IOError,
                      OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError].freeze

    def initialize(settings:, url_policy:, logger: Rails.logger,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                   sleeper: ->(seconds) { sleep(seconds) }, transport: nil)
      @settings, @url_policy, @logger = settings, url_policy, logger
      @clock, @sleeper, @transport = clock, sleeper, transport || method(:request)
    end

    # Returns HTML or raises NetworkError with the final reason and attempt count.
    def get(url)
      uri = URI(@url_policy.normalize(url))
      reason, attempts = nil, 0
      @settings.max_attempts.times do |index|
        throttle
        attempts = index + 1
        begin
          response = @transport.call(uri)
          code = response.code.to_i
          return response.body if code == 200
          reason = "HTTP #{code}"
          @logger.warn("fetch url=#{uri} attempt=#{attempts}/#{@settings.max_attempts} status=#{code}")
          break unless code == 429 || code >= 500
        rescue *NETWORK_ERRORS => e
          reason = "#{e.class}: #{e.message}"
          @logger.warn("fetch url=#{uri} attempt=#{attempts}/#{@settings.max_attempts} error=#{reason}")
        ensure
          @last_finished_at = @clock.call
        end
      end
      @logger.error("fetch exhausted url=#{uri} attempts=#{attempts} reason=#{reason}")
      raise NetworkError.new(reason, url: uri.to_s, attempts: attempts)
    end

    private

    def throttle
      return unless @last_finished_at
      remaining = @settings.interval - (@clock.call - @last_finished_at)
      @sleeper.call(remaining) if remaining.positive?
    end

    def request(uri)
      http = Net::HTTP.new(uri.host, uri.port, nil) # Explicitly disable environment proxies.
      http.use_ssl = true
      http.open_timeout = @settings.open_timeout
      http.read_timeout = @settings.read_timeout
      http.write_timeout = @settings.write_timeout
      http.max_retries = 0
      http.start { |connection| connection.get(uri.request_uri, "User-Agent" => @settings.user_agent) }
    end
  end
end

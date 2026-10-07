# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Payriff
  class Transport
    MAX_ERROR_BODY = 500
    CONNECTION_ERRORS = [
      IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, EOFError
    ].freeze

    def initialize(base_url:, app_key:, merchant_id:, timeout:, open_timeout:)
      @base_uri = URI(base_url.to_s.chomp("/"))
      @app_key = app_key
      @merchant_id = merchant_id
      @timeout = timeout
      @open_timeout = open_timeout
    end

    def execute(method, path, query: nil, headers: nil, body: nil, merchant_envelope: false)
      status, raw = send_request(method, path, query, headers, body, merchant_envelope, "application/json")
      PayriffObject.convert(unwrap(status, raw))
    end

    def download(method, path)
      status, raw = send_request(method, path, nil, nil, nil, false, "application/pdf, application/json")
      return raw.b if (200..299).cover?(status)

      unwrap(status, raw)
      raise ApiError.new("Unexpected response", http_status: status)
    end

    private

    def send_request(method, path, query, headers, body, merchant_envelope, accept)
      payload = request_body(body, merchant_envelope)
      uri = URI(@base_uri.to_s + path + query_string(query))
      request = Net::HTTPGenericRequest.new(method, !payload.nil?, true, uri)
      request["Accept"] = accept
      request["User-Agent"] = "payriff-ruby/#{VERSION}"
      request["Authorization"] = @app_key
      (headers || {}).each { |name, value| request[name] = value.to_s unless value.nil? || value.to_s.empty? }
      if payload
        request["Content-Type"] = "application/json"
        request.body = payload
      end
      response = http(uri).request(request)
      [response.code.to_i, response.body.to_s]
    rescue *CONNECTION_ERRORS => e
      raise ConnectionError, "Payriff request failed: #{e.message}"
    end

    def http(uri)
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @open_timeout
        http.read_timeout = @timeout
        http.write_timeout = @timeout
      end
    end

    def query_string(query)
      pairs = (query || []).reject { |_, v| v.nil? || v.to_s.empty? }
      return "" if pairs.empty?

      "?" + pairs.map { |k, v| "#{Util.escape(k)}=#{Util.escape(v)}" }.join("&")
    end

    def request_body(body, merchant_envelope)
      if merchant_envelope
        raise ArgumentError, "merchant_id must be configured on Payriff::Client for this operation" if @merchant_id.to_s.empty?

        body = { "merchant" => @merchant_id, "body" => body || {} }
      end
      body.nil? ? nil : JSON.generate(body)
    end

    def unwrap(status, raw)
      root = begin
        raw.empty? ? nil : JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
      ok = (200..299).cover?(status)
      unless root.is_a?(Hash) && root.key?("code")
        raise ApiError.new(ok ? "Unexpected response from Payriff" : truncate(raw, status), http_status: status)
      end

      code = root["code"]&.to_s
      unless ok && code == ResultCodes::SUCCESS
        raise ResultCodes.to_error(root["message"]&.to_s, status, code, root["responseId"]&.to_s)
      end

      root["payload"]
    end

    def truncate(raw, status)
      return "Payriff request failed (HTTP #{status})" if raw.empty?

      text = raw.dup.force_encoding(Encoding::UTF_8).scrub
      text.length > MAX_ERROR_BODY ? "#{text[0, MAX_ERROR_BODY]}..." : text
    end
  end
end
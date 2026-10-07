# frozen_string_literal: true

require "test_helper"

class TransportTest < PayriffTest
  def test_unwraps_payload_on_success
    @server.ok("GET", "/api/v3/orders/ORD-1", { "orderId" => "ORD-1", "paymentStatus" => "APPROVED" })

    order = @server.client.orders.get("ORD-1")

    assert_equal "ORD-1", order.order_id
    assert_equal "APPROVED", order.payment_status
    assert_equal "ORD-1", order[:order_id]
  end

  def test_sends_auth_and_client_headers
    @server.ok("GET", "/api/v3/orders/ORD-1", { "orderId" => "ORD-1" })

    @server.client.orders.get("ORD-1")

    headers = @server.last.headers
    assert_equal "app-key", headers["authorization"]
    assert_equal "payriff-ruby/#{Payriff::VERSION}", headers["user-agent"]
    assert_equal "application/json", headers["accept"]
    refute headers.key?("content-type")
  end

  def test_encodes_path_segments_and_query
    @server.ok("PATCH", "/api/v3/expire-status", nil)

    assert_nil @server.client.orders.expire("ORD 1/2+3")

    assert_equal "PATCH", @server.last.method
    assert_equal "/api/v3/expire-status?orderId=ORD%201%2F2%2B3", @server.last.url
  end

  def test_rejects_blank_path_segment_before_sending
    error = assert_raises(ArgumentError) { @server.client.orders.get(" ") }

    assert_equal "order_id must not be blank", error.message
    assert_empty @server.requests
  end

  def test_merchant_envelope_requires_merchant_id
    error = assert_raises(ArgumentError) { @server.client(merchant_id: nil).invoices.get("inv-1") }

    assert_equal "merchant_id must be configured on Payriff::Client for this operation", error.message
    assert_empty @server.requests
  end

  FAILURES = [
    [200, "15000", Payriff::ApiError],
    [401, "14010", Payriff::AuthenticationError],
    [401, "14013", Payriff::AuthenticationError],
    [200, "14014", Payriff::AuthenticationError],
    [401, "14015", Payriff::AuthenticationError],
    [400, "15400", Payriff::ValidationError],
    [400, "99999", Payriff::ValidationError],
    [403, "99999", Payriff::AuthenticationError],
    [402, "01000", Payriff::RequestRejectedError],
    [402, "01200", Payriff::InsufficientBalanceError],
    [402, "01300", Payriff::PayoutLimitError],
    [402, "01400", Payriff::PayoutLimitError],
    [402, "01500", Payriff::PayoutLimitError],
    [500, "15000", Payriff::ApiError],
    [503, "15000", Payriff::ApiError]
  ].freeze

  FAILURES.each do |status, code, klass|
    define_method("test_maps_http_#{status}_code_#{code}_to_#{klass.name.split('::').last}") do
      @server.stub("GET", "/api/v3/orders/ORD-1", status: status,
                                                 body: { "code" => code, "message" => "Failure reason", "responseId" => "resp-1" })

      error = assert_raises(Payriff::ApiError) { @server.client.orders.get("ORD-1") }

      assert_instance_of klass, error
      assert_equal "Failure reason", error.message
      assert_equal [status, code, "resp-1"], [error.http_status, error.code, error.response_id]
    end
  end

  def test_missing_message_falls_back_to_http_status
    @server.stub("GET", "/api/v3/orders/ORD-1", status: 500, body: { "code" => "15000" })

    error = assert_raises(Payriff::ApiError) { @server.client.orders.get("ORD-1") }

    assert_equal "Payriff request failed (HTTP 500)", error.message
  end

  def test_non_json_error_body_keeps_status_and_truncates
    @server.stub("GET", "/api/v3/orders/ORD-1", status: 502, headers: { "Content-Type" => "text/html" }, body: "x" * 600)

    error = assert_raises(Payriff::ApiError) { @server.client.orders.get("ORD-1") }

    assert_equal [502, nil], [error.http_status, error.code]
    assert_equal "#{'x' * 500}...", error.message
  end

  def test_success_status_without_envelope_is_rejected
    @server.stub("GET", "/api/v3/orders/ORD-1", body: { "orderId" => "ORD-1" })

    error = assert_raises(Payriff::ApiError) { @server.client.orders.get("ORD-1") }

    assert_equal "Unexpected response from Payriff", error.message
  end

  def test_redirects_are_not_followed
    @server.stub("GET", "/api/v3/orders/ORD-1", status: 302, headers: { "Location" => "/api/v3/orders/OTHER" },
                                               body: { "code" => "15000", "message" => "Redirect" })

    error = assert_raises(Payriff::ApiError) { @server.client.orders.get("ORD-1") }

    assert_equal "Redirect", error.message
    assert_equal 1, @server.requests.size
  end

  def test_download_returns_bytes
    @server.stub("GET", "/api/v3/acquiring/receipt/ORD-1", headers: { "Content-Type" => "application/pdf" }, body: "%PDF-1.7")

    assert_equal "%PDF-1.7".b, @server.client.orders.download_receipt("ORD-1")
    assert_equal "application/pdf, application/json", @server.last.headers["accept"]
  end

  def test_download_maps_envelope_error
    @server.stub("GET", "/api/v3/acquiring/receipt/ORD-1", status: 400, body: { "code" => "15400", "message" => "Receipt not found" })

    assert_raises(Payriff::ValidationError) { @server.client.orders.download_receipt("ORD-1") }
  end

  def test_connection_failure_raises_connection_error
    client = Payriff::Client.new(app_key: "app-key", base_url: "http://127.0.0.1:1")

    error = assert_raises(Payriff::ConnectionError) { client.orders.get("ORD-1") }

    assert_equal 0, error.http_status
  end

  def test_timeout_raises_connection_error
    client = Payriff::Client.new(app_key: "app-key", base_url: "http://10.255.255.1", open_timeout: 0.05)

    assert_raises(Payriff::ConnectionError) { client.orders.get("ORD-1") }
  end

  def test_client_validation
    assert_equal "app_key is required", assert_raises(ArgumentError) { Payriff::Client.new(app_key: " ") }.message
    assert_equal "Invalid RSA public key", assert_raises(ArgumentError) { Payriff::Client.new(app_key: "k", card_encryption_key: "nope") }.message

    client = Payriff::Client.new(app_key: "k")
    %i[orders payments cards transactions payouts invoices].each { |s| refute_nil client.public_send(s) }
    refute_includes client.inspect, "k\""
  end
end
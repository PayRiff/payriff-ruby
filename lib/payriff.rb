# frozen_string_literal: true

require "openssl"
require_relative "payriff/version"
require_relative "payriff/errors"
require_relative "payriff/util"
require_relative "payriff/payriff_object"
require_relative "payriff/card"
require_relative "payriff/transport"
require_relative "payriff/services"
require_relative "payriff/client"

module Payriff
  NOT_A_CALLBACK = "Not a Payriff order callback"

  def self.parse_order_callback(body)
    root = body.is_a?(Hash) ? body : JSON.parse(body.to_s)
    payload = root.is_a?(Hash) ? root["payload"] || root[:payload] : nil
    raise ArgumentError, NOT_A_CALLBACK unless payload.is_a?(Hash) && !(payload["orderId"] || payload[:orderId]).nil?

    PayriffObject.convert(payload.transform_keys(&:to_s))
  rescue JSON::ParserError
    raise ArgumentError, NOT_A_CALLBACK
  end
end
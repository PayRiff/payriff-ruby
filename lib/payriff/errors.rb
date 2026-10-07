# frozen_string_literal: true

module Payriff
  class Error < StandardError
    attr_reader :http_status, :code, :response_id

    def initialize(message, http_status: 0, code: nil, response_id: nil)
      super(message)
      @http_status = http_status
      @code = code
      @response_id = response_id
    end
  end

  class ApiError < Error; end
  class AuthenticationError < ApiError; end
  class ValidationError < ApiError; end
  class RequestRejectedError < ApiError; end
  class InsufficientBalanceError < ApiError; end
  class PayoutLimitError < ApiError; end
  class ConnectionError < Error; end

  module ResultCodes
    SUCCESS = "00000"

    BY_CODE = {
      "14010" => AuthenticationError,
      "14013" => AuthenticationError,
      "14014" => AuthenticationError,
      "14015" => AuthenticationError,
      "01300" => PayoutLimitError,
      "01400" => PayoutLimitError,
      "01500" => PayoutLimitError,
      "01200" => InsufficientBalanceError,
      "01000" => RequestRejectedError,
      "15400" => ValidationError
    }.freeze

    def self.to_error(message, http_status, code, response_id)
      msg = message.nil? || message.empty? ? "Payriff request failed (HTTP #{http_status})" : message
      klass = BY_CODE[code] ||
              case http_status
              when 401, 403 then AuthenticationError
              when 400 then ValidationError
              else ApiError
              end
      klass.new(msg, http_status: http_status, code: code, response_id: response_id)
    end
  end
end
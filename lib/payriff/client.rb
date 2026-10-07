# frozen_string_literal: true

module Payriff
  class Client
    PRODUCTION_URL = "https://api.payriff.com"

    attr_reader :orders, :payments, :cards, :transactions, :payouts, :invoices

    def initialize(app_key:, merchant_id: nil, timeout: 60, open_timeout: 10, card_encryption_key: nil, base_url: PRODUCTION_URL)
      raise ArgumentError, "app_key is required" if app_key.nil? || app_key.to_s.strip.empty?
      raise ArgumentError, "timeouts must be positive" unless timeout.to_f.positive? && open_timeout.to_f.positive?

      transport = Transport.new(base_url: base_url, app_key: app_key, merchant_id: merchant_id,
                                timeout: timeout, open_timeout: open_timeout)
      key = CardEncryptor.parse_key(card_encryption_key || CardEncryptor::PRODUCTION_KEY)
      @orders = Services::Orders.new(transport)
      @payments = Services::Payments.new(transport, key)
      @cards = Services::Cards.new(transport)
      @transactions = Services::Transactions.new(transport)
      @payouts = Services::Payouts.new(transport)
      @invoices = Services::Invoices.new(transport)
    end

    def inspect
      "#<Payriff::Client>"
    end
  end
end
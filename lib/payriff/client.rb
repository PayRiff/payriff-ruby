# frozen_string_literal: true

module Payriff
  class Client
    REGIONS = {
      azerbaijan: { base_url: "https://api.payriff.com", currency: "AZN" }.freeze,
      saudi: { base_url: "https://api.gccpay.sa", currency: "SAR" }.freeze
    }.freeze

    attr_reader :orders, :payments, :cards, :transactions, :payouts, :invoices

    def initialize(app_key:, merchant_id: nil, timeout: 60, open_timeout: 10, region: :azerbaijan, base_url: nil)
      raise ArgumentError, "app_key is required" if app_key.nil? || app_key.to_s.strip.empty?
      raise ArgumentError, "timeouts must be positive" unless timeout.to_f.positive? && open_timeout.to_f.positive?

      config = REGIONS[region.to_s.to_sym] or raise ArgumentError, "unknown region: #{region}"

      transport = Transport.new(base_url: base_url || config[:base_url], app_key: app_key, merchant_id: merchant_id,
                                timeout: timeout, open_timeout: open_timeout)
      @orders = Services::Orders.new(transport, config[:currency])
      @payments = Services::Payments.new(transport, config[:currency])
      @cards = Services::Cards.new(transport)
      @transactions = Services::Transactions.new(transport)
      @payouts = Services::Payouts.new(transport)
      @invoices = Services::Invoices.new(transport, config[:currency])
    end

    def inspect
      "#<Payriff::Client>"
    end
  end
end
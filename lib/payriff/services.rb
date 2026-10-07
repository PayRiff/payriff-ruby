# frozen_string_literal: true

module Payriff
  module Services
    class Base
      include Util

      def initialize(transport)
        @transport = transport
      end

      def inspect
        "#<#{self.class.name}>"
      end
    end

    class Orders < Base
      def create(amount:, currency: "AZN", language: nil, operation: "PURCHASE", description: nil, callback_url: nil,
                 redirect_url: nil, card_save: nil, three_ds: nil, auto_payment_type: nil, installment: nil,
                 full_name: nil, phone_number: nil, metadata: nil, fields: nil, request_rrn: nil)
        body = compact(
          "amount" => to_amount(required(amount, "amount"), "amount"),
          "currency" => stringify(currency),
          "language" => stringify(language),
          "operation" => stringify(operation),
          "description" => description,
          "callbackUrl" => callback_url,
          "redirectUrl" => redirect_url,
          "cardSave" => card_save,
          "threeDS" => three_ds,
          "autoPaymentType" => stringify(auto_payment_type),
          "installment" => installment&.transform_keys(&:to_s)&.transform_values { |v| stringify(v) },
          "fullName" => full_name,
          "phoneNumber" => phone_number,
          "metadata" => metadata,
          "fields" => fields
        )
        @transport.execute("POST", "/api/v3/orders", headers: { "X-REQUEST-RRN" => request_rrn }, body: body)
      end

      def get(order_id)
        @transport.execute("GET", "/api/v3/orders/#{segment(order_id, 'order_id')}")
      end

      def get_status(order_id)
        @transport.execute("GET", "/api/v3/orders/#{segment(order_id, 'order_id')}/status")
      end

      def get_by_request_rrn(request_rrn)
        @transport.execute("GET", "/api/v3/orders/#{segment(request_rrn, 'request_rrn')}/rrn")
      end

      def expire(order_id)
        segment(order_id, "order_id")
        @transport.execute("PATCH", "/api/v3/expire-status", query: [["orderId", order_id]])
        nil
      end

      def refund(order_id, amount: nil, refund_reason: nil, callback_url: nil)
        body = compact("orderId" => required(order_id, "order_id"), "amount" => to_amount(amount, "amount"),
                       "refundReason" => refund_reason, "callbackUrl" => callback_url)
        @transport.execute("POST", "/api/v3/refund", body: body)
        nil
      end

      def complete(order_id, amount: nil, callback_url: nil)
        body = compact("orderId" => required(order_id, "order_id"), "amount" => to_amount(amount, "amount"),
                       "callbackUrl" => callback_url)
        @transport.execute("POST", "/api/v3/complete", body: body)
        nil
      end

      def download_receipt(order_id_or_rrn)
        @transport.download("GET", "/api/v3/acquiring/receipt/#{segment(order_id_or_rrn, 'order_id_or_rrn')}")
      end
    end

    class Payments < Base
      def initialize(transport, public_key)
        super(transport)
        @public_key = public_key
      end

      def direct_pay(amount:, description:, card:, operation: "PURCHASE", currency: "AZN", callback_url: nil,
                     three_ds: nil, custom_fields: nil, card_save: false, request_rrn: nil)
        body = compact(
          "amount" => to_amount(required(amount, "amount"), "amount"),
          "operation" => stringify(operation),
          "currency" => stringify(currency),
          "description" => required(description, "description"),
          "callbackUrl" => callback_url,
          "threeDS" => three_ds,
          "customFields" => custom_fields
        )
        raise ArgumentError, "card must be a Payriff::Card" unless card.is_a?(Card)

        encrypted = card.encrypted_payload(@public_key)
        body["paymentData"] = { "paymentWay" => "DIRECT", "encryptedMessage" => encrypted[:message], "cardSave" => card_save ? true : false }
        @transport.execute("POST", "/api/v3/directPay",
                           headers: { "X-REQUEST-RRN" => request_rrn, "x-secret-key" => encrypted[:secret_key] }, body: body)
      end

      def auto_pay(card_uuid:, amount:, description:, operation: "PURCHASE", currency: "AZN", callback_url: nil,
                   three_ds: nil, one_click_payment: nil, request_rrn: nil)
        body = compact(
          "cardUuid" => required(card_uuid, "card_uuid"),
          "amount" => to_amount(required(amount, "amount"), "amount"),
          "operation" => stringify(operation),
          "currency" => stringify(currency),
          "description" => required(description, "description"),
          "callbackUrl" => callback_url,
          "threeDS" => three_ds,
          "isOneCLickPayment" => one_click_payment
        )
        @transport.execute("POST", "/api/v3/autoPay", headers: { "X-REQUEST-RRN" => request_rrn }, body: body)
      end
    end

    class Cards < Base
      def save(customer_ref:, callback_url:, description: nil, language: nil, metadata: nil, idempotency_key: nil)
        body = compact(
          "customerRef" => required(customer_ref, "customer_ref"),
          "callbackUrl" => required(callback_url, "callback_url"),
          "description" => description,
          "language" => stringify(language),
          "metadata" => metadata
        )
        @transport.execute("POST", "/api/v3/cards/save", headers: { "X-Idempotency-Key" => idempotency_key }, body: body)
      end

      def get_save(card_save_id)
        @transport.execute("GET", "/api/v3/cards/save/#{segment(card_save_id, 'card_save_id')}")
      end

      def list(customer_ref)
        segment(customer_ref, "customer_ref")
        @transport.execute("GET", "/api/v3/cards/save", query: [["customerRef", customer_ref]]) || []
      end

      def delete(card_uuid)
        @transport.execute("DELETE", "/api/v3/cards/#{segment(card_uuid, 'card_uuid')}")
        nil
      end
    end

    class Transactions < Base
      def list(order_id: nil, rrn: nil, status: nil, amount: nil, description: nil, name: nil, full_name: nil,
               card_number: nil, booking_id: nil, invoice_code: nil, from: nil, to: nil, page: 0, size: 10)
        query = [
          ["orderId", order_id], ["rrn", rrn], ["status", stringify(status)], ["amount", amount],
          ["description", description], ["name", name], ["fullName", full_name], ["cardNumber", card_number],
          ["bookingId", booking_id], ["invoiceCode", invoice_code],
          ["from", filter_date(from, "from")], ["to", filter_date(to, "to")]
        ] + page_query(page, size)
        @transport.execute("GET", "/api/v3/transactions", query: query)
      end
    end

    class Payouts < Base
      def create(transfer_amount:, description:, full_name:, fin_code:, card_pan: nil, bank_name: nil, card_type: nil,
                 request_rrn: nil, customer_code: nil, voen: nil, birth_date: nil, callback_url: nil, idempotency_key: nil)
        amount = to_amount(required(transfer_amount, "transfer_amount"), "transfer_amount")
        raise ArgumentError, "transfer_amount must be at least 1" if amount < 1

        body = compact(
          "transferAmount" => amount,
          "description" => required(description, "description"),
          "fullName" => required(full_name, "full_name"),
          "finCode" => required(fin_code, "fin_code"),
          "cardPan" => card_pan,
          "bankName" => bank_name,
          "cardType" => card_type,
          "requestRrn" => request_rrn,
          "customerCode" => customer_code,
          "voen" => voen,
          "birthDate" => birth_date,
          "callbackUrl" => callback_url
        )
        @transport.execute("POST", "/api/v3/payout", headers: { "X-IDEMPOTENCY-KEY" => idempotency_key },
                                                     body: body, merchant_envelope: true)
      end

      def get_by_request_rrn(request_rrn)
        @transport.execute("GET", "/api/v3/payout/info/#{segment(request_rrn, 'request_rrn')}")
      end

      def check_cardholder(card_pan)
        pan = card_pan.to_s.gsub(/[\s-]/, "")
        raise ArgumentError, "card_pan must be a 16-digit number" unless pan.match?(/\A[0-9]{16}\z/)

        @transport.execute("POST", "/api/v3/payout/check-cardholder", body: { "cardPan" => pan }).to_s
      end

      def list(rrn: nil, status: nil, amount: nil, description: nil, full_name: nil, fin_code: nil, bank_source: nil,
               from: nil, to: nil, page: 0, size: 10)
        query = [
          ["rrn", rrn], ["status", stringify(status)], ["amount", amount], ["description", description],
          ["fullName", full_name], ["finCode", fin_code], ["bankSource", bank_source],
          ["from", filter_date(from, "from")], ["to", filter_date(to, "to")]
        ] + page_query(page, size)
        @transport.execute("GET", "/api/v3/payouts", query: query)
      end

      def download_receipt(request_rrn)
        @transport.download("GET", "/api/v3/payout/receipt/#{segment(request_rrn, 'request_rrn')}")
      end
    end

    class Invoices < Base
      def create(amount: nil, amount_dynamic: nil, currency: "AZN", language: nil, full_name: nil, email: nil,
                 phone_number: nil, description: nil, custom_message: nil, expire_date: nil, approve_url: nil,
                 cancel_url: nil, decline_url: nil, redirect_url: nil, installment_product_type: nil,
                 installment_period: nil, direct_pay: nil, send_sms: nil, send_whatsapp: nil, send_email: nil,
                 metadata: nil, external_transaction_id: nil)
        raise ArgumentError, "amount is required" if amount_dynamic != true && amount.nil?

        body = compact(
          "amount" => to_amount(amount, "amount"),
          "amountDynamic" => amount_dynamic,
          "currencyType" => stringify(currency),
          "languageType" => stringify(language),
          "fullName" => full_name,
          "email" => email,
          "phoneNumber" => phone_number,
          "description" => description,
          "customMessage" => custom_message,
          "expireDate" => date_time(expire_date),
          "approveURL" => approve_url,
          "cancelURL" => cancel_url,
          "declineURL" => decline_url,
          "redirectURL" => redirect_url,
          "installmentProductType" => stringify(installment_product_type),
          "installmentPeriod" => installment_period,
          "directPay" => direct_pay,
          "sendSms" => send_sms,
          "sendWhatsapp" => send_whatsapp,
          "sendEmail" => send_email,
          "metadata" => metadata,
          "externalTransactionId" => external_transaction_id
        )
        @transport.execute("POST", "/api/v2/invoices", body: body, merchant_envelope: true)
      end

      def get(invoice_uuid)
        segment(invoice_uuid, "invoice_uuid")
        @transport.execute("POST", "/api/v2/get-invoice", body: { "uuid" => invoice_uuid }, merchant_envelope: true)
      end
    end
  end
end
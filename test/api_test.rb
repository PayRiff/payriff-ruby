# frozen_string_literal: true

require "test_helper"
require_relative "card_test"

class OrdersTest < PayriffTest
  ORDER_INFO = {
    "orderId" => "ORD-1", "amount" => 10.5, "currencyType" => "AZN", "paymentStatus" => "APPROVED",
    "createdDate" => "2026-10-01T14:05:09.123456",
    "transactions" => [{
      "uuid" => "6f1c2a4e-0b7d-4c3e-9a51-2d8e7f6b1c90", "status" => "APPROVED",
      "cardDetails" => { "maskedPan" => "416974******1979", "brand" => "VISA" },
      "installment" => { "type" => "BIRKART", "period" => "PERIOD_3" }
    }]
  }.freeze

  def test_create_sends_body_and_rrn_header
    @server.ok("POST", "/api/v3/orders", {
      "orderId" => "ORD-1", "paymentUrl" => "https://pay.payriff.com/ORD-1", "transactionId" => 77,
      "comissionRate" => 2.5, "amount" => 10.0, "fee" => 0.25, "totalAmount" => 10.25
    })

    response = @server.client.orders.create(
      amount: "10.00",
      language: :az,
      description: "Order #1",
      callback_url: "https://shop.az/cb",
      installment: { type: :birkart, period: "PERIOD_3" },
      metadata: { "cartId" => "c-9" },
      request_rrn: "rrn-1"
    )

    sent = @server.last
    assert_equal "rrn-1", sent.headers["x-request-rrn"]
    assert_equal "application/json", sent.headers["content-type"]
    assert_equal({ "amount" => 10.0, "currency" => "AZN", "language" => "AZ", "operation" => "PURCHASE",
                   "description" => "Order #1", "callbackUrl" => "https://shop.az/cb",
                   "installment" => { "type" => "BIRKART", "period" => "PERIOD_3" }, "metadata" => { "cartId" => "c-9" } }, sent.json)
    assert_equal ["ORD-1", "https://pay.payriff.com/ORD-1", 77, 2.5, 10.25],
                 [response.order_id, response.payment_url, response.transaction_id, response.commission_rate, response.total_amount]
  end

  def test_create_omits_rrn_header_and_empty_maps
    @server.ok("POST", "/api/v3/orders", { "orderId" => "ORD-1" })

    @server.client.orders.create(amount: 1, metadata: {})

    refute @server.last.headers.key?("x-request-rrn")
    assert_equal({ "amount" => 1.0, "currency" => "AZN", "operation" => "PURCHASE" }, @server.last.json)
  end

  def test_create_rejects_missing_or_invalid_amount
    assert_equal "amount is required", assert_raises(ArgumentError) { @server.client.orders.create(amount: nil) }.message
    assert_equal "amount must be a number", assert_raises(ArgumentError) { @server.client.orders.create(amount: "ten") }.message
    assert_empty @server.requests
  end

  { get: "/api/v3/orders/ORD-1", get_status: "/api/v3/orders/ORD-1/status" }.each do |method, path|
    define_method("test_#{method}_parses_order_info") do
      @server.ok("GET", path, ORDER_INFO)

      order = @server.client.orders.public_send(method, "ORD-1")

      assert_equal path, @server.last.url
      assert_equal ["ORD-1", 10.5, "AZN", "APPROVED", "2026-10-01T14:05:09.123456"],
                   [order.order_id, order.amount, order.currency_type, order.payment_status, order.created_date]
      tx = order.transactions.first
      assert_equal ["416974******1979", "VISA", "PERIOD_3"], [tx.card_details.masked_pan, tx.card_details.brand, tx.installment.period]
      assert_equal ORDER_INFO.dig("transactions", 0, "uuid"), order.to_h[:transactions][0][:uuid]
    end
  end

  def test_get_by_request_rrn_encodes_segment
    @server.ok("GET", "/api/v3/orders/rrn%201%2F2/rrn", ORDER_INFO)

    assert_equal "ORD-1", @server.client.orders.get_by_request_rrn("rrn 1/2").order_id
  end

  def test_missing_fields_read_as_nil
    @server.ok("GET", "/api/v3/orders/ORD-1", { "orderId" => "ORD-1", "paymentStatus" => "SOMETHING_NEW" })

    order = @server.client.orders.get("ORD-1")

    assert_equal "SOMETHING_NEW", order.payment_status
    assert_nil order.invoice_uuid
    assert_raises(NoMethodError) { order.to_str }
  end

  def test_refund_and_complete_send_body
    @server.ok("POST", "/api/v3/refund", nil)
    @server.ok("POST", "/api/v3/complete", nil)
    client = @server.client

    assert_nil client.orders.refund("ORD-1", amount: 5, refund_reason: "damaged")
    assert_equal({ "orderId" => "ORD-1", "amount" => 5.0, "refundReason" => "damaged" }, @server.last.json)

    client.orders.complete("ORD-1", amount: 7.5)
    assert_equal({ "orderId" => "ORD-1", "amount" => 7.5 }, @server.last.json)

    assert_equal "order_id is required", assert_raises(ArgumentError) { client.orders.refund(nil) }.message
  end
end

class PaymentsTest < PayriffTest
  def test_direct_pay_encrypts_card_and_sends_secret_key
    @server.ok("POST", "/api/v3/directPay", {
      "orderId" => "ORD-1", "threeDS" => true, "redirect" => true, "redirectUrl" => "https://acs.bank/3ds",
      "transactionResponse" => { "status" => "CREATED", "requestRrn" => "req-1" }
    })

    response = @server.client(card_encryption_key: CardKeys.public_base64).payments.direct_pay(
      amount: 1,
      description: "Order #1",
      callback_url: "https://shop.az/cb",
      card_save: true,
      request_rrn: "rrn-1",
      card: Payriff::Card.new(pan: "4169741330151979", card_holder: "JOHN DOE", expiry_month: "11", expiry_year: "2027", cvv: "123")
    )

    sent = @server.last
    assert_equal "rrn-1", sent.headers["x-request-rrn"]
    refute_includes sent.body, "4169741330151979"
    refute_includes sent.body, "JOHN DOE"
    body = sent.json
    payment_data = body.delete("paymentData")
    assert_equal({ "amount" => 1.0, "operation" => "PURCHASE", "currency" => "AZN", "description" => "Order #1",
                   "callbackUrl" => "https://shop.az/cb" }, body)
    assert_equal ["DIRECT", true], [payment_data["paymentWay"], payment_data["cardSave"]]
    assert_equal '{"pan":"4169741330151979","cardHolder":"JOHN DOE","expiryYear":"2027","expiryMonth":"11","cvv":"123"}',
                 CardKeys.decrypt(sent.headers["x-secret-key"], payment_data["encryptedMessage"])
    assert_equal ["ORD-1", true, true, "https://acs.bank/3ds", "CREATED"],
                 [response.order_id, response.three_ds, response.redirect, response.redirect_url, response.transaction_response.status]
  end

  def test_direct_pay_requires_card
    error = assert_raises(ArgumentError) do
      @server.client.payments.direct_pay(amount: 1, description: "x", card: { pan: "4169741330151979" })
    end

    assert_equal "card must be a Payriff::Card", error.message
    assert_empty @server.requests
  end

  def test_auto_pay_sends_explicit_currency_and_one_click_flag
    @server.ok("POST", "/api/v3/autoPay", {
      "orderId" => "ORD-2", "amount" => 3.0, "paymentStatus" => "APPROVED", "auto" => true,
      "transactionResponseDto" => { "threeDS" => false }
    })

    response = @server.client.payments.auto_pay(card_uuid: "card-uuid-1", amount: 3, description: "Subscription",
                                                one_click_payment: true, request_rrn: "rrn-2")

    assert_equal "rrn-2", @server.last.headers["x-request-rrn"]
    assert_equal({ "cardUuid" => "card-uuid-1", "amount" => 3.0, "operation" => "PURCHASE", "currency" => "AZN",
                   "description" => "Subscription", "isOneCLickPayment" => true }, @server.last.json)
    assert_equal ["APPROVED", true, false], [response.payment_status, response.auto, response.transaction_response_dto.three_ds]
  end
end

class CardsTest < PayriffTest
  def test_save_get_list_delete
    @server.ok("POST", "/api/v3/cards/save", { "cardSaveId" => "cs-1", "status" => "CREATED", "amount" => 0.1 })
    @server.ok("GET", "/api/v3/cards/save/cs-1", { "cardSaveId" => "cs-1", "status" => "VERIFIED", "cardUuid" => "card-1" })
    @server.ok("GET", "/api/v3/cards/save?customerRef=cust%201", [{ "cardUuid" => "card-1" }, { "cardUuid" => "card-2" }])
    @server.ok("DELETE", "/api/v3/cards/card-1", true)
    client = @server.client

    saved = client.cards.save(customer_ref: "cust-1", callback_url: "https://shop.az/cards/cb", language: "AZ", idempotency_key: "idem-1")
    assert_equal ["cs-1", "CREATED"], [saved.card_save_id, saved.status]
    assert_equal "idem-1", @server.last.headers["x-idempotency-key"]
    assert_equal({ "customerRef" => "cust-1", "callbackUrl" => "https://shop.az/cards/cb", "language" => "AZ" }, @server.last.json)

    assert_equal "card-1", client.cards.get_save("cs-1").card_uuid
    assert_equal %w[card-1 card-2], client.cards.list("cust 1").map(&:card_uuid)
    assert_nil client.cards.delete("card-1")
    assert_equal "DELETE", @server.last.method

    error = assert_raises(ArgumentError) { client.cards.save(customer_ref: "c", callback_url: nil) }
    assert_equal "callback_url is required", error.message
  end

  def test_list_returns_empty_array_for_null_payload
    @server.ok("GET", "/api/v3/cards/save", nil)

    assert_equal [], @server.client.cards.list("cust-1")
  end
end

class TransactionsTest < PayriffTest
  def test_list_sends_filter_and_parses_page
    @server.ok("GET", "/api/v3/transactions?status=APPROVED&from=01.09.2026&to=30.09.2026&page=1&offset=20", {
      "content" => [{ "id" => 5, "orderId" => "ORD-1", "amount" => 10.0, "paymentStatus" => "APPROVED",
                      "card_brand" => "VISA", "payment_way" => "DIRECT", "extra_payment" => 0.5 }],
      "totalElements" => 41, "totalPages" => 3, "number" => 1, "size" => 20, "first" => false, "last" => false
    })

    page = @server.client.transactions.list(status: :approved, from: Date.new(2026, 9, 1), to: "2026-09-30", page: 1, size: 20)

    tx = page.content.first
    assert_equal [41, false], [page.total_elements, page.last]
    assert_equal ["VISA", "DIRECT", 0.5], [tx.card_brand, tx.payment_way, tx.extra_payment]
  end

  def test_defaults_and_page_size_cap
    @server.ok("GET", "/api/v3/transactions", { "content" => [] })
    client = @server.client

    client.transactions.list
    assert_equal "/api/v3/transactions?page=0&offset=10", @server.last.url

    [0, 21, -1, "5"].each do |size|
      assert_equal "size must be 1-20", assert_raises(ArgumentError) { client.transactions.list(size: size) }.message
    end
    error = assert_raises(ArgumentError) { client.transactions.list(from: "01.09.2026") }
    assert_equal "from must be a Date, Time or YYYY-MM-DD string", error.message
  end
end

class PayoutsTest < PayriffTest
  PAYOUT = { transfer_amount: 25, description: "Refund to customer", full_name: "JOHN DOE", fin_code: "1AB2C3D",
             card_pan: "4169741330151979", request_rrn: "po-1" }.freeze

  def test_create_wraps_body_in_merchant_envelope
    @server.ok("POST", "/api/v3/payout", { "_final" => "true", "state" => "SUCCESS", "currentDepositBalance" => 975.0, "walletHistoryId" => 321 })

    result = @server.client.payouts.create(**PAYOUT, idempotency_key: "idem-po-1")

    assert_equal "idem-po-1", @server.last.headers["x-idempotency-key"]
    assert_equal({ "merchant" => "ES1000000",
                   "body" => { "transferAmount" => 25.0, "description" => "Refund to customer", "fullName" => "JOHN DOE",
                               "finCode" => "1AB2C3D", "cardPan" => "4169741330151979", "requestRrn" => "po-1" } }, @server.last.json)
    assert_equal ["true", "SUCCESS", 321, 975.0], [result.final_state, result.state, result.wallet_history_id, result.current_deposit_balance]
  end

  def test_errors_and_validation
    @server.stub("POST", "/api/v3/payout", status: 402, body: { "code" => "01200", "message" => "Insufficient wallet balance" })
    client = @server.client

    assert_raises(Payriff::InsufficientBalanceError) { client.payouts.create(**PAYOUT) }
    error = assert_raises(ArgumentError) { client.payouts.create(**PAYOUT, transfer_amount: "0.99") }
    assert_equal "transfer_amount must be at least 1", error.message
    error = assert_raises(ArgumentError) { client.payouts.check_cardholder("4169") }
    assert_equal "card_pan must be a 16-digit number", error.message
  end

  def test_lookups_and_receipt
    @server.ok("GET", "/api/v3/payout/info/po-1", { "state" => "IN_PROGRESS", "formattedDate" => "01.10.2026 10:00:00" })
    @server.ok("POST", "/api/v3/payout/check-cardholder", "J*** D**")
    @server.ok("GET", "/api/v3/payouts?status=SUCCESS&page=0&offset=10", { "content" => [{ "requestRrn" => "po-1", "state" => "SUCCESS" }] })
    @server.stub("GET", "/api/v3/payout/receipt/po-1", headers: { "Content-Type" => "application/pdf" }, body: "%PDF-")
    client = @server.client

    assert_equal "IN_PROGRESS", client.payouts.get_by_request_rrn("po-1").state
    assert_equal "J*** D**", client.payouts.check_cardholder("4169 7413 3015 1979")
    assert_equal({ "cardPan" => "4169741330151979" }, @server.last.json)
    assert_equal ["po-1"], client.payouts.list(status: "SUCCESS").content.map(&:request_rrn)
    assert_equal "%PDF-".b, client.payouts.download_receipt("po-1")
  end
end

class InvoicesTest < PayriffTest
  def test_create_and_get
    @server.ok("POST", "/api/v2/invoices", { "invoiceUuid" => "inv-uuid-1", "invoiceStatus" => "PENDING", "approveURL" => "https://shop.az/ok" })
    @server.ok("POST", "/api/v2/get-invoice", { "invoiceUuid" => "inv-uuid-1", "invoiceStatus" => "COMPLETE", "paymentDay" => "2026-10-02" })
    client = @server.client

    invoice = client.invoices.create(amount: 15, language: "AZ", full_name: "JOHN DOE", phone_number: "+994501234567",
                                     description: "Consultation", expire_date: Time.new(2026, 10, 8, 23, 59, 0),
                                     approve_url: "https://shop.az/ok", send_sms: false, metadata: { "bookingRef" => "B-77" })

    assert_equal({ "merchant" => "ES1000000",
                   "body" => { "amount" => 15.0, "currencyType" => "AZN", "languageType" => "AZ", "fullName" => "JOHN DOE",
                               "phoneNumber" => "+994501234567", "description" => "Consultation",
                               "expireDate" => "2026-10-08T23:59:00", "approveURL" => "https://shop.az/ok", "sendSms" => false,
                               "metadata" => { "bookingRef" => "B-77" } } }, @server.last.json)
    assert_equal ["inv-uuid-1", "PENDING", "https://shop.az/ok"], [invoice.invoice_uuid, invoice.invoice_status, invoice.approve_url]

    details = client.invoices.get("inv-uuid-1")
    assert_equal({ "merchant" => "ES1000000", "body" => { "uuid" => "inv-uuid-1" } }, @server.last.json)
    assert_equal ["COMPLETE", "2026-10-02"], [details.invoice_status, details.payment_day]
  end

  def test_amount_required_unless_dynamic
    @server.ok("POST", "/api/v2/invoices", { "invoiceUuid" => "inv-2" })

    assert_equal "amount is required", assert_raises(ArgumentError) { @server.client.invoices.create }.message
    @server.client.invoices.create(amount_dynamic: true)
    assert_equal({ "amountDynamic" => true, "currencyType" => "AZN" }, @server.last.json["body"])
  end
end

class WebhookTest < Minitest::Test
  CALLBACK = '{"payload":{"orderId":"ORD-1","invoiceUuid":"inv-1","amount":10.5,"currencyType":"AZN",' \
             '"paymentStatus":"APPROVED","operationType":"PURCHASE","auto":false,"createdDate":"2026-10-01T14:05:09.123",' \
             '"transactions":[{"status":"APPROVED"}]},"code":"00000","message":"Operation performed successfully",' \
             '"route":"/dashboard","responseId":"http-nio-1"}'

  [CALLBACK, JSON.parse(CALLBACK), JSON.parse(CALLBACK, symbolize_names: true)].each_with_index do |body, i|
    define_method("test_parses_callback_#{i}") do
      order = Payriff.parse_order_callback(body)

      assert_equal ["ORD-1", "APPROVED", "inv-1", 1], [order.order_id, order.payment_status, order.invoice_uuid, order.transactions.size]
    end
  end

  ["", "not json", "{}", '{"payload":null}', '{"payload":{"amount":1}}', "[]", '{"payload":[]}'].each_with_index do |body, i|
    define_method("test_rejects_non_callback_#{i}") do
      error = assert_raises(ArgumentError) { Payriff.parse_order_callback(body) }
      assert_equal "Not a Payriff order callback", error.message
    end
  end
end
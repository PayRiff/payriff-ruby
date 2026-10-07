# Payriff Ruby SDK

Ruby client for the Payriff merchant API: orders, direct (host-to-host) card payments, saved cards,
transactions, payouts and invoices.

- Ruby 3.1 or newer
- No runtime dependencies (standard library `net/http`, `json` and `openssl` only)
- Talks to `https://api.payriff.com`

## Installation

```ruby
# Gemfile
gem "payriff", github: "PayRiff/payriff-ruby", tag: "v0.1.1"
```

Then run `bundle install`.

> RubyGems publishing is coming. After that, the Gemfile line becomes `gem "payriff"`.

## Quick start

```ruby
require "payriff"

payriff = Payriff::Client.new(app_key: ENV.fetch("PAYRIFF_APP_KEY"))

order = payriff.orders.create(
  amount: "10.00",
  description: "Order #1001",
  callback_url: "https://shop.example/payriff/callback",
  request_rrn: "order-1001"
)

# Send the customer to the hosted payment page
redirect_to order.payment_url, allow_other_host: true
```

Responses are `Payriff::PayriffObject`s: read fields with snake_case methods (`order.payment_url`)
or `order[:payment_url]`, and convert with `to_h`. Fields Payriff did not send read as `nil`.

Create one `Payriff::Client` and reuse it.

## Configuration

| Argument | Required | Default | Notes |
|---|---|---|---|
| `app_key:` | yes | — | Application key from the Payriff dashboard. |
| `merchant_id:` | for payouts and invoices | — | Merchant ID (e.g. `ES1000000`). |
| `timeout:` | no | `60` | Read/write timeout in seconds. Bank operations can take tens of seconds. |
| `open_timeout:` | no | `10` | Connection timeout in seconds. |
| `card_encryption_key:` | no | built-in Payriff key | Only if Payriff rotates the card-encryption key. Base64 or PEM. |

Keep the app key in an environment variable or secret store. Never commit it.

## Orders

```ruby
created = payriff.orders.create(
  amount: "25.00",
  currency: "AZN",            # default AZN
  operation: "PRE_AUTH",      # default PURCHASE
  language: "AZ",
  description: "Booking #77",
  callback_url: "https://shop.example/payriff/callback",
  metadata: { "bookingId" => "77" }
)

info = payriff.orders.get(created.order_id)
by_ref = payriff.orders.get_by_request_rrn("order-1001")   # the request_rrn you sent on create

payriff.orders.complete(created.order_id, amount: "25.00")
payriff.orders.refund(created.order_id, amount: "5.00", refund_reason: "Partial return")
payriff.orders.expire(created.order_id)                    # cancel an unpaid order

receipt_pdf = payriff.orders.download_receipt(created.order_id)
```

`payment_status` is a string such as `"APPROVED"`, `"DECLINED"`, `"PREAUTH_APPROVED"` or `"REFUNDED"`.
Enum arguments also accept symbols (`language: :az`).

Amounts can be passed as numeric strings (`"10.50"`), integers, floats or `BigDecimal`s.

## Direct payments (host-to-host)

You collect the card details yourself, and the SDK encrypts them before sending
(AES-256-GCM + RSA-OAEP). Raw card data never leaves your server in clear text, but your
systems still handle card data, so PCI DSS requirements apply to you.

```ruby
result = payriff.payments.direct_pay(
  amount: "1.00",
  description: "Order #1002",
  callback_url: "https://shop.example/payriff/callback",
  request_rrn: "order-1002",
  card: Payriff::Card.new(
    pan: "4169 7413 3015 1979",
    card_holder: "JOHN DOE",
    expiry_month: "11",
    expiry_year: "27",
    cvv: "123"
  )
)

if result.redirect
  # 3-D Secure: send the customer's browser to result.redirect_url.
  # The final status arrives via your callback or payriff.orders.get(result.order_id).
end
```

`Payriff::Card` strips spaces and dashes, pads the month (`1` → `01`), expands a 2-digit year
(`27` → `2027`) and rejects malformed values before any network call. It is frozen, prints and logs
with a masked number and no CVV, and cannot be serialized with `Marshal`.

### Charging a saved card

```ruby
charge = payriff.payments.auto_pay(
  card_uuid: saved_card_uuid,
  amount: "9.99",
  description: "Monthly subscription",
  request_rrn: "sub-2026-10"
)
```

## Saved cards

```ruby
session = payriff.cards.save(
  customer_ref: "customer-42",
  callback_url: "https://shop.example/payriff/card-saved",
  idempotency_key: SecureRandom.uuid
)
# Redirect the customer to session.payment_url to verify the card.

details = payriff.cards.get_save(session.card_save_id)
if details.status == "VERIFIED"
  card_uuid = details.card_uuid   # store it; use with auto_pay
end

cards = payriff.cards.list("customer-42")
payriff.cards.delete(cards.first.card_uuid)
```

## Transactions

```ruby
page = payriff.transactions.list(
  status: "APPROVED",
  from: Date.new(2026, 9, 1),    # Date, Time or "YYYY-MM-DD"
  to: "2026-09-30",
  page: 0,
  size: 20                       # server maximum is 20
)

page.content.each { |tx| puts "#{tx.order_id} #{tx.amount}" }
```

## Payouts

Payouts require `merchant_id` on the client.

```ruby
payriff = Payriff::Client.new(app_key: ENV.fetch("PAYRIFF_APP_KEY"), merchant_id: ENV.fetch("PAYRIFF_MERCHANT_ID"))

masked_name = payriff.payouts.check_cardholder("4169741330151979")   # e.g. "J*** D**"

payout = payriff.payouts.create(
  transfer_amount: "50.00",      # minimum 1
  description: "Refund for order #1001",
  full_name: "JOHN DOE",
  fin_code: "1AB2C3D",
  card_pan: "4169741330151979",
  request_rrn: "payout-1001",
  idempotency_key: "payout-1001"
)

status = payriff.payouts.get_by_request_rrn("payout-1001")
history = payriff.payouts.list(status: "SUCCESS")
receipt = payriff.payouts.download_receipt("payout-1001")
```

## Invoices

Invoices require `merchant_id` on the client.

```ruby
invoice = payriff.invoices.create(
  amount: "15.00",
  full_name: "JOHN DOE",
  phone_number: "+994501234567",
  description: "Consultation",
  expire_date: Time.now + 7 * 24 * 3600,
  send_sms: true
)

link = invoice.payment_url   # share with the customer
details = payriff.invoices.get(invoice.invoice_uuid)
```

## Callbacks

When an order changes state, Payriff POSTs JSON to the `callback_url` you set on the order.

```ruby
class PayriffCallbacksController < ApplicationController
  skip_forgery_protection

  def create
    notified = Payriff.parse_order_callback(request.raw_post)   # also accepts a parsed Hash

    # Callbacks are not signed: confirm the state with Payriff before fulfilling.
    confirmed = PAYRIFF.orders.get(notified.order_id)
    if confirmed.payment_status == "APPROVED"
      # fulfil the order (make this idempotent: the same callback can arrive more than once)
    end
    head :ok
  end
end
```

## Errors

Every SDK error extends `Payriff::Error`, which provides `http_status`, `code` (Payriff result code)
and `response_id` (quote it when contacting support).

| Exception | When |
|---|---|
| `Payriff::AuthenticationError` | App key rejected (`14010`, `14013`, `14014`, `14015`) |
| `Payriff::ValidationError` | Invalid request (`15400` or HTTP 400) |
| `Payriff::RequestRejectedError` | Business refusal (`01000`), e.g. application under review |
| `Payriff::InsufficientBalanceError` | Not enough wallet balance for a payout (`01200`) |
| `Payriff::PayoutLimitError` | Payout limit reached (`01300`, `01400`, `01500`) |
| `Payriff::ApiError` | Any other failure reported by Payriff |
| `Payriff::ConnectionError` | No response: network error or timeout |

Payriff can report a failure with HTTP 200. The SDK checks the result code in the body, so you
only need to rescue exceptions. Invalid arguments raise `ArgumentError` before any request is sent.

```ruby
begin
  payriff.orders.refund(order_id)
rescue Payriff::ValidationError => e
  Rails.logger.warn("Refund rejected: #{e.message} (#{e.code})")
rescue Payriff::ConnectionError
  # Outcome unknown: check payriff.orders.get(order_id) before retrying
rescue Payriff::Error => e
  Rails.logger.error("Payriff error #{e.code} response_id=#{e.response_id}")
end
```

### Retries

The SDK never retries on its own, because payment calls are not safe to repeat blindly. After a
`Payriff::ConnectionError`, look the operation up first (`orders.get_by_request_rrn`,
`payouts.get_by_request_rrn`) and retry only if it does not exist. Set `request_rrn` /
`idempotency_key` on every request so that this lookup is possible.

## Development

```bash
bundle install
bundle exec rake test
```

## License

MIT
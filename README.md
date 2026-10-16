# Payriff Ruby SDK

Ruby client for the Payriff merchant API: orders, saved-card payments, saved cards,
transactions, payouts and invoices.

- Ruby 3.1 or newer
- No runtime dependencies (standard library `net/http` and `json` only)
- Talks to `https://api.payriff.com` (Azerbaijan) or `https://api.gccpay.sa` (Saudi Arabia)

## Installation

```ruby
# Gemfile
gem "payriff"
```

Then run `bundle install`, or install it directly with `gem install payriff`.

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
| `region:` | no | `:azerbaijan` | API region: `:azerbaijan` or `:saudi`. Sets the base URL and the default currency. |
| `base_url:` | no | from `region:` | Override the API URL, e.g. for testing. The currency still comes from `region:`. |

Keep the app key in an environment variable or secret store. Never commit it.

### Saudi Arabia

```ruby
payriff = Payriff::Client.new(app_key: ENV.fetch("PAYRIFF_APP_KEY"), region: :saudi)
```

| Region | API | Default currency |
|---|---|---|
| `:azerbaijan` | `https://api.payriff.com` | `AZN` |
| `:saudi` | `https://api.gccpay.sa` | `SAR` |

Use the app key from the dashboard of the same region (`dashboard.gccpay.sa` for Saudi Arabia).
A `currency:` passed on a request always wins over the region default.

## Orders

```ruby
created = payriff.orders.create(
  amount: "25.00",
  currency: "AZN",            # default: the region currency
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

## Charging a saved card

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
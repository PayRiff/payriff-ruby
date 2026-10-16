# Changelog

## 0.2.0 (unreleased)

- Added: Saudi Arabia support via `Payriff::Client.new(..., region: :saudi)`. It uses
  `https://api.gccpay.sa` and defaults the currency to `SAR`. Azerbaijan (`AZN`) stays the default.
- Removed: direct (host-to-host) card payments: `payments.direct_pay`, `Payriff::Card` and the
  `card_encryption_key:` option. Use the hosted payment page (`orders.create`) instead.
- Removed `Payriff::Client::PRODUCTION_URL`; see `Payriff::Client::REGIONS`.

## 0.1.2 (2026-10-15)

- First RubyGems release: install with `gem "payriff"`.
- Test suite runs under Bundler on Ruby 4.0 (`logger` is no longer a default gem).

## 0.1.1 (2026-10-07)

- Fix `cannot load such file -- base64` under Bundler on Ruby 3.4+ (base64 is no longer a default gem).

## 0.1.0 (2026-10-07)

- Initial release: orders, direct and saved-card payments, saved cards, transactions, payouts,
  v2 invoices, order callback parsing.
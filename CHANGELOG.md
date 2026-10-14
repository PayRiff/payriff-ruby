# Changelog

## 0.1.2 (2026-10-15)

- First RubyGems release: install with `gem "payriff"`.
- Test suite runs under Bundler on Ruby 4.0 (`logger` is no longer a default gem).

## 0.1.1 (2026-10-07)

- Fix `cannot load such file -- base64` under Bundler on Ruby 3.4+ (base64 is no longer a default gem).

## 0.1.0 (2026-10-07)

- Initial release: orders, direct and saved-card payments, saved cards, transactions, payouts,
  v2 invoices, order callback parsing.
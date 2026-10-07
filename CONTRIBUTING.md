# Contributing

Thank you for helping improve the Payriff Ruby SDK.

## Reporting problems

- **Bugs and feature requests:** open a GitHub issue. Include the SDK version, the Ruby version,
  what you did, what you expected and what happened. Add the `responseId` from the error if you
  have one.
- **Security issues:** do not open an issue. Follow [SECURITY.md](SECURITY.md).
- **Problems with your Payriff account or a specific payment:** contact Payriff support, not this
  repository.

## Pull requests

Payriff maintains SDKs for Java, Node.js, Python, PHP, Go, Ruby and .NET, and they must behave the
same way. Because of that:

1. **Open an issue first** for anything beyond a small fix, so we can agree on the change for all
   SDKs before you write code.
2. Keep the change focused: one fix or feature per pull request.
3. Add or update tests. Every request the SDK sends and every response it parses is covered by
   tests against a local mock server; no test may call the real Payriff API.
4. Do not break the public API without discussing it in an issue first.
5. Never commit secrets, app keys, or real card data, including in tests and examples.

All pull requests must pass CI before they are reviewed. Payriff maintainers review every change
and decide whether and when it is merged and released.

## Development

```bash
bundle install
bundle exec rake test
```

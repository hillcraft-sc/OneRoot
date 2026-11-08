# Contributing to OneRoot

Thanks for your interest. Bug reports, suggestions, and pull requests are welcome.

## Before you start

- **Bugs and ideas:** open an issue using the templates. Include your OS version, OneRoot version, and steps to reproduce.
- **Security problems:** do **not** open a public issue. See [SECURITY.md](SECURITY.md).
- **Larger changes:** open an issue first so we can agree on the approach. OneRoot has a deliberate UX direction (`docs/UX-DIRECTION.md`) and architecture rules (`CLAUDE.md`, `SPEC.md`), and a PR that fights them is likely to be declined.
- Be kind: see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Pull requests

- One coherent change per PR, small enough to review.
- Build and run the tests (`swift test`, and the Xcode test target for the Mac app). If you touch the shared core, also run `Scripts/test-linux.sh`.
- Add or update tests for service and view-model logic.
- Never use real user data, home folders, or mounted drives in tests.
- File safety comes first: no silent moves, renames, or deletes, and no swallowed errors.
- No new third-party dependency in the Mac app without prior discussion. Linux-only dependencies are discussed case by case.
- Update README.md / docs when behavior changes.

## Licensing and the DCO

OneRoot is licensed under the [GNU GPL v3.0 only](LICENSE). By contributing you agree that your contribution is licensed under the same terms. You keep your copyright.

We use the [Developer Certificate of Origin](https://developercertificate.org/) (DCO). Sign off every commit:

```
git commit -s
```

This adds `Signed-off-by: Your Name <you@example.com>`, certifying that you wrote the change or have the right to submit it under the project's license. Use your real name. PRs with unsigned commits can't be merged (`git commit --amend -s`, or `git rebase --signoff main`, fixes that).

## Names and logos

The "OneRoot" name and the app icon are **not** licensed under the GPL. See [TRADEMARKS.md](TRADEMARKS.md). Contributions to the icon or branding assets are welcome as suggestions, but they remain part of the reserved assets.

# vallow.nvim

Neovim plugin (Lua, Neovim 0.10+) that runs the `fallow` CLI on a JS/TS
project and shows its JSON findings in a panel, as diagnostics, and in
pickers and file explorers.

## Never

- Run stylua on `tests/run.lua`. `make lint` covers `lua/` only, and
  stylua rewrites unrelated lines in the harness. Format the `lua/` files
  you touch.
- Run `fallow fix` without `--dry-run` inside `tests/`. It rewrites the
  fixture.

## Always

- Pass the suite on two fallow versions: the oldest one you have
  (`install.lua` `MIN_VERSION` is the floor) and the latest release. The
  harness runs whatever `fallow` is first on `PATH`:
  `PATH=/tmp/fallow-X.Y/node_modules/.bin:$PATH make test`, after
  `npm i --prefix /tmp/fallow-X.Y fallow@X.Y.Z`.
- Follow the Conventions section of `ROADMAP.md` for every feature.

## Commands

- `make test` runs `tests/run.lua` headless from `tests/fixture`. The last
  line reads `all tests passed` or `N test(s) failed`.
- `make lint` runs `stylua --check lua`.
- There is no CI. Both commands run locally.

## Tests

- Add a step as one numbered `-- N.` block directly before
  `local done = false`, numbered after the highest existing step.
- Assert on fallow output loosely. Docs hosts, notice counts and finding
  counts change between fallow releases. The fixture also yields one
  `skipped-source-dotdir` notice per hidden directory in the checkout.
- For JSON shapes the fixtures never produce, feed a hand-built table to
  `require("vallow.runner")._normalize(raw, root)`.
- `tests/fixture-health` holds the clone and complexity cases.

## fallow JSON

- `docs/FALLOW_API.md` describes the output vallow reads. The authority is
  `output-contract.d.ts` in the installed fallow npm package.
- `.gitignore` excludes `docs/`. `FALLOW_API.md` is tracked, so edits to it
  stage normally; a new file there needs `git add -f`.
- Every field fallow adds or renames goes through `runner.lua`
  `_normalize`, which turns the combined, separate and watch outputs into
  one `results.findings` shape. Read unknown or missing fields as nil.

## Flow

`runner.lua` runs fallow and normalizes. `panel/init.lua` `_on_results`
then feeds `diagnostics.lua`, `integrations/`, `manifest.lua` and the
`User VallowResults` event. `panel/render.lua` draws the panel from the
same results.

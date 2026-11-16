# Peak test upload

Uploads JUnit test results to [Peak](https://peak.inc) from GitHub Actions. With `permissions: id-token: write`, it
uses the job's own OIDC token, so there is no secret to create.

```yaml
jobs:
  test:
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - run: pytest -o junit_family=xunit1 --junitxml=junit.xml
      - uses: PeakInc/test-upload@v1
        if: ${{ !cancelled() }}
        with:
          framework: pytest
          files: junit.xml
```

The repository must be connected to Peak. The token can only upload this job's results, to the workspace the repository
is connected to. Fork pull requests get no OIDC token, so they upload nothing.

## Inputs

| Input | |
|---|---|
| `files` | JUnit XML files or patterns (`junit.xml`, `reports/**/*.xml`), separated by spaces or new lines |
| `framework` | `pytest`, `unittest`, `go`, `node`, `jest`, `vitest`, `playwright`, `bun` or `junit`: how to read file and line |

A failed upload only warns; it never fails your job. Where OIDC can't be used (a repository connected to two Peak
workspaces, or an organization that blocks `id-token`), set `PEAK_TOKEN` in the step's `env` to a Peak API token with
Upload test results.

## Reporter settings that add file and line

| Framework | Setting |
|---|---|
| pytest | `-o junit_family=xunit1 --junitxml=junit.xml` |
| unittest | `xmlrunner` (unittest-xml-reporting) |
| Go | `gotestsum --junitfile junit.xml` (the CLI adds file and line from the checkout) |
| bun | `bun test --reporter=junit --reporter-outfile=junit.xml` |
| Vitest | `vitest run --reporter=junit --outputFile=junit.xml` (file only) |
| Playwright | `PLAYWRIGHT_JUNIT_OUTPUT_NAME=junit.xml playwright test --reporter=junit` (file only) |
| Node | `node --test --test-reporter=junit --test-reporter-destination=junit.xml` (file only) |
| Jest | `jest-junit` with `JEST_JUNIT_ADD_FILE_ATTRIBUTE=true` (file only) |

Each release of this action pins the `peak` CLI it downloads from
[PeakInc/homebrew-tap releases](https://github.com/PeakInc/homebrew-tap/releases) and checks it against the release's
`SHA256SUMS`. Linux and macOS runners, x64 and arm64.

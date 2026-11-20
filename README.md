# Peak test upload

Uploads test results, coverage, or both to [Peak](https://peak.inc) from GitHub Actions. It uses the job's OIDC token,
so there is no secret: give the job `permissions: id-token: write`.

`files` and `coverage` are both optional: set either one, or both. A failed upload only warns; it never fails the job.
The repository must be connected to Peak.

**Test results and coverage**

```yaml
jobs:
  test:
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # for patch coverage
      - run: pytest -o junit_family=xunit1 --junitxml=junit.xml --cov --cov-report=xml
      - uses: PeakInc/test-upload@v1
        if: ${{ !cancelled() }}
        with:
          framework: pytest # optional
          files: junit.xml  # optional
          coverage: coverage.xml # optional
```

**Test results only**

```yaml
      - uses: PeakInc/test-upload@v1
        if: ${{ !cancelled() }}
        with:
          framework: pytest
          files: junit.xml
```

**Coverage only**

```yaml
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # for patch coverage
      # … your tests …
      - uses: PeakInc/test-upload@v1
        if: ${{ !cancelled() }}
        with:
          coverage: coverage/lcov.info
```

## Inputs

| Input | Required | |
|---|---|---|
| `files` | Optional (set `files`, `coverage` or both) | JUnit XML files or patterns (`junit.xml`, `reports/**/*.xml`), separated by spaces or new lines |
| `coverage` | Optional (set `files`, `coverage` or both) | Coverage reports or patterns: lcov, Cobertura, JaCoCo, Clover, Go coverprofile, SimpleCov or coverage.py JSON |
| `framework` | Optional | `pytest`, `unittest`, `go`, `node`, `jest`, `vitest`, `playwright`, `bun` or `junit`. Adds each test's file and line for code links; results upload without it |

`fetch-depth: 0` in the coverage examples gives the checkout the base commit, which patch coverage (the share of a pull
request's changed lines that ran) needs. Without it, coverage still uploads and only patch coverage is skipped.

## Reporter settings that add file and line

Any JUnit XML uploads, from any test runner. For the frameworks below, setting `framework` also lets Peak link each
test to its file and/or line on GitHub. Without it, or for any other runner (use `junit`), results upload the same, just
without those links.

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

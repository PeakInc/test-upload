# Peak test upload

Uploads JUnit test results and coverage reports to [Peak](https://peak.inc) from GitHub Actions. Uses OIDC: give the
job `permissions: id-token: write`.

```yaml
jobs:
  test:
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # the base commit, for patch coverage
      - run: pytest -o junit_family=xunit1 --junitxml=junit.xml --cov --cov-report=xml
      - uses: PeakInc/test-upload@v1
        if: ${{ !cancelled() }}
        with:
          framework: pytest
          files: junit.xml
          coverage: coverage.xml
```

Coverage only:

```yaml
      - uses: PeakInc/test-upload@v1
        if: ${{ !cancelled() }}
        with:
          coverage: coverage/lcov.info
```

The repository must be connected to Peak. A failed upload only warns; it never fails the job.

## Inputs

| Input | |
|---|---|
| `files` | JUnit XML files or patterns (`junit.xml`, `reports/**/*.xml`), separated by spaces or new lines |
| `framework` | `pytest`, `unittest`, `go`, `node`, `jest`, `vitest`, `playwright`, `bun` or `junit`: how to read file and line |
| `coverage` | Coverage reports or patterns: lcov, Cobertura, JaCoCo, Clover, Go coverprofile, SimpleCov or coverage.py JSON |

Set `files`, `coverage` or both. Coverage also sends the commit's changed lines (file names and line numbers only) for
patch coverage; when the checkout lacks the base commit, patch coverage is skipped.

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

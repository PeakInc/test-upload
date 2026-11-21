# Peak test upload

Uploads test results, coverage, or both to [Peak](https://peak.inc) from GitHub Actions, and can run the tests too. It
uses the job's OIDC token, so there is no secret: give the job `permissions: id-token: write`.

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

`fetch-depth: 0` in the coverage examples gives the checkout the base commit, which patch coverage (the share of a pull
request's changed lines that ran) needs. Without it, coverage still uploads and only patch coverage is skipped.

## Run the tests too

With `run`, the action runs your test command and uploads its report, even when tests fail. The step fails when the
tests do. For pytest and unittest, Peak can shard the run by its timings, run likely failures first, and rerun
known-flaky tests once:

```yaml
jobs:
  test:
    strategy:
      matrix:
        shard: [1, 2, 3, 4]
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      # install dependencies as usual
      - uses: PeakInc/test-upload@v1
        with:
          run: pytest -o junit_family=xunit1 --junitxml=junit.xml
          shard: ${{ matrix.shard }}/4 # optional
          failed-first: true           # optional
          retry-flaky: true            # optional
          framework: pytest
          files: junit.xml
```

`run` takes one test command. Put setup in a step above, `cd` in `working-directory`, and variables in the step's
`env`. A multi-line script runs as written, without shard, failed-first or retry-flaky.
See [Run tests](https://docs.peak.inc/test-analytics#run-tests).

## Inputs

| Input | |
|---|---|
| `files` | Optional (set `files`, `coverage` or both). JUnit XML files or patterns (`junit.xml`, `reports/**/*.xml`), separated by spaces or new lines |
| `coverage` | Optional (set `files`, `coverage` or both). Coverage reports or patterns: lcov, Cobertura, JaCoCo, Clover, Go coverprofile, SimpleCov or coverage.py JSON |
| `framework` | Optional. `pytest`, `unittest`, `go`, `node`, `jest`, `vitest`, `playwright`, `bun` or `junit`. Adds each test's file and line for code links; results upload without it |
| `run` | Optional. The test command to run before uploading |
| `working-directory` | Optional. Where to run `run` and find `files` and `coverage` |
| `shard` | Optional, with `run`: this shard as `I/N` |
| `failed-first` | Optional, with `run`: changed and recently failing test files first |
| `retry-flaky` | Optional, with `run`: rerun a failed test once when Peak lists it as flaky |

The action also puts `peak` on `PATH` for later steps.

## Frameworks

Any JUnit XML uploads, from any test runner. With `framework` and the reporter setting below, Peak also links each test
to its file (and line) on GitHub. For any other runner, use `junit`: results upload the same, without the links.

| Framework | Reporter setting | Links | `shard` | `failed-first` | `retry-flaky` |
|---|---|---|---|---|---|
| pytest | `-o junit_family=xunit1 --junitxml=junit.xml` | File and line | Yes | Yes | Yes |
| unittest | `xmlrunner` (unittest-xml-reporting) | File and line | Yes | Yes | Yes |
| Go | `gotestsum --junitfile junit.xml` | File and line | No | No | No |
| bun | `bun test --reporter=junit --reporter-outfile=junit.xml` | File and line | No | No | No |
| Vitest | `vitest run --reporter=junit --outputFile=junit.xml` | File | No | No | No |
| Playwright | `PLAYWRIGHT_JUNIT_OUTPUT_NAME=junit.xml playwright test --reporter=junit` | File | No | No | No |
| Node | `node --test --test-reporter=junit --test-reporter-destination=junit.xml` | File | No | No | No |
| Jest | `jest-junit` with `JEST_JUNIT_ADD_FILE_ATTRIBUTE=true` | File | No | No | No |

`shard` and `failed-first` work by whole test file. Frameworks without them run as written: every shard runs every
test, and the report still uploads.

Each release of this action pins the `peak` CLI it downloads from
[PeakInc/homebrew-tap releases](https://github.com/PeakInc/homebrew-tap/releases) and checks it against the release's
`SHA256SUMS`. Linux and macOS runners, x64 and arm64.

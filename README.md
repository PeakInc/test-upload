# Peak test upload

Uploads JUnit test results to [Peak](https://peak.inc) from GitHub Actions, and can run the tests too. Uses OIDC: give
the job `permissions: id-token: write`. The repository must be connected to Peak.

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
| `files` | JUnit XML files or patterns (`junit.xml`, `reports/**/*.xml`), separated by spaces or new lines |
| `framework` | `pytest`, `unittest`, `go`, `node`, `jest`, `vitest`, `playwright`, `bun` or `junit`: how to read file and line |
| `run` | Optional. The test command to run before uploading |
| `working-directory` | Optional. Where to run `run` and find `files` |
| `shard` | Optional, with `run`: this shard as `I/N` |
| `failed-first` | Optional, with `run`: changed and recently failing test files first |
| `retry-flaky` | Optional, with `run`: rerun a failed test once when Peak lists it as flaky |

The action also puts `peak` on `PATH` for later steps.

## Frameworks

Any JUnit XML uploads. With `framework` and the reporter setting below, Peak also links each test to its file (and line)
on GitHub.

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

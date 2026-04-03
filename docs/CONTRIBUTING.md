# How to Contribute

Chimera (STIG-Partitioned Enterprise Linux) produces hardened AMIs for AWS using
a Docker-based build system driven by Packer and the
[amigen8](https://github.com/MetroStar/amigen8) /
[amigen9](https://github.com/MetroStar/amigen9) tool-sets. The project
currently supports:

* EL8 (RHEL 8, Oracle Linux 8)
* EL9 (RHEL 9, Oracle Linux 9)
* Amazon Linux 2023
* Windows Server 2019 / 2022 (STIG-hardened)

Contributions that improve the build system, add OS support, fix bugs, or
enhance documentation are welcome. Please open an
[issue](https://github.com/MetroStar/chimera/issues/new) to discuss larger
changes before investing significant effort.

## Development Setup

1. Clone the repository and create a feature branch:

    ```bash
    git clone https://github.com/MetroStar/chimera.git
    cd chimera && git checkout -b <feature-branch-name>
    ```

2. Build the Docker builder image (requires Docker):

    ```bash
    make docker/build
    ```

3. Run a local AMI build (requires AWS credentials):

    ```bash
    make build
    ```

See the top-level [README](../README.md) for full build prerequisites and
variable references.

## Testing

When submitting a PR the following checks run automatically:

* **GitHub Actions** — the `build.yml` workflow provisions infrastructure via
  OpenTofu (`infra` job) and then runs Packer inside the Docker builder
  container (`build` job). See [`.github/build.md`](../.github/build.md) for
  details.
* **Shell linting** — basic lints are performed against shell scripts.
* **Packer validation** — Packer templates are validated for syntax errors.

For air-gapped / GovCloud builds an equivalent GitLab CI pipeline is available
(see [`.gitlab/README.md`](../.gitlab/README.md)).

## Submitting Changes

Please send a GitHub Pull Request with a clear description of the changes.
Reference any related issues in the PR body.

Commit messages should be clear and concise. One-line messages are fine for
small changes; larger changes should follow this pattern:

    $ git commit -m "A brief summary of the commit
    >
    > A paragraph describing what changed and its impact."

If the PR touches infrastructure or build logic, please also update the
relevant documentation under `docs/`.

## Coding Conventions

* **Shell** — use `bash` with `set -euo pipefail`. Follow the style of
  existing scripts in `build/` and the amigenN repositories.
* **Packer** — use HCL2 format. Keep variables documented.
* **OpenTofu / HCL** — follow the conventions in `infra/`.
* When in doubt, match the style of surrounding code and be consistent.

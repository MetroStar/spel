# Chimera

Chimera is a project that helps create and
publish images that are partitioned according to the
[DISA STIG][0]. The resulting images also use LVM to simplify volume management.
The images are configured with help from the scripts and packages in the
[`amigen8`][40] and [`amigen9`][47] projects[^1].

Notes on Lifecycle:

1.  Images are released on a monthly cadence. This cadence ensures that, if a
    user launches a brand new instance from the most-recently published AMI,
    that there will be less than a month's worth of system-patches to apply as
    part of the system-owner's system-provisioning processes.
1.  "Free" Enterprise Linux distributions are configured to use the public
    repositories offered by the distribution-owner. If running EC2s inside of a
    VPC with no access to the internet at large, it will not be possible to
    install additional RPMs or patch systems without the use of either a proxy
    or standing up a private yum mirror. Note: RHEL images in AWS GovCloud (including
    Offline) have access to RHUI repositories within the isolated network
1.  Red Hat images are configured to use a given cloud service provider's (CSP) 
    [Red Hat Update Infrastructure](https://access.redhat.com/products/red-hat-update-infrastructure)
    (a.k.a., "RHUI") repositories. These repositories are managed by Red 
    Hat engineers and provide local RPM update-service within each 
    CSP-partner's networks. Unlike RPM-access via RHN or Satellite, RHUI access 
    is tied to and paid for via your CSP's billing-mechanisms. RHUI access also 
    entitles cloud-VMs' owners to limited operating system support through the 
    respective CSP's support channels.
1.  AWS Specific notes:
    * Access to the RHUI repositories is gated, in part, by an attribute
      attached to EC2s. This attribute is inherited from their corresponding
      AMIs. To view this attribute external to the EC2, execute:

        ~~~
        aws ec2 describe-instances --query 'Reservations[].Instances[].UsageOperation' --instance-ids
        ~~~

      This _should_ return a value of `RunInstances:0010`. If the value is just
      `RunInstances` the necessary attribute is missing from the EC2.

      The attribute may also be viewed internal to the EC2 by executing:

        ~~~
        TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
          -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
        curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
          http://169.254.169.254/latest/dynamic/instance-identity/document | \
        grep "billingProducts"
        ~~~

      This _should_ return a value of `"billingProducts" : [ "bp-6fa54006" ]`.
      If not, the necessary attribute is missing from the EC2.

      In either case, lack of the requisite attribute will mean that attempts to
      install or update RPMs from RHUI will fail.
    * If patch-updates should come from RHN, Satellite or other private
      repository, do not use the AMIs published by the maintainers of this
      project. Because the previously-mentioned EC2-attribute is attached to
      such AMIs, you will be billed for the RHUI access even if you never use
      it. Feel free to use this project's code to generate your own,
      unencumbered AMIs.
    * Further information about AWS polices for Red Hat EC2s may be found in
      AWS's [RHEL FAQ](https://aws.amazon.com/partners/redhat/faqs/)

## Why Chimera

VMs' root filesystems are generally not live-repartitionable once launced from
their images. As a result, if a STIG-scan is performed against most of the
community-published images for Red Hat and related distros (CentOS/CentOS
Stream, [Oracle Linux][41], [Rocky][42], [Alma][43] or [Liberty][44]), those
scans will note failures for each of the various "`${DIRECTORY}` is on its own
filesystem" tests. The images produced through this project are designed to
ensure that these particular scan-failures do not occur.

## We have a FAQ now!

We've added an [FAQ](docs/FAQ.md) to the project. Hopefully, your questions are
answered there. If they aren't, please feel free to submit an issue requesting
an appropriate FAQ entry.

## Default Username

The default username for all Chimera images is `maintuser`.

If you wish to change the default username at launch, you can do so via
`cloud-init` with userdata[^3] something like the following. Change `<USERNAME>` to
your desired value.

```yaml
#cloud-config
system_info:
  default_user:
    name: <USERNAME>
    gecos: chimera default user
    lock_passwd: true
```


## Default User Security-Constraints

Due to updates to the STIGs &ndash; currently just for EL7, but it is assumed
that similar changes for EL8 and later distros will be added to future
STIG-releases &ndash; the default-user's account _may_ have additional SELinux
rules applied to it. These rules will typically manifest in processes that
start as the default-user (i.e., processes run as the `root` user _after_
privilege-escalation via the `sudo` subsystem) receiving `permission denied`
errors when attempting to access "sensitive" files.  These "sensitive" files
are any that have the `shadow_t` SELinux context-label applied to them. By
default, these will only include:

- /etc/security/opasswd
- /etc/shadow
- /etc/gshadow

A definitive list may be gathered by executing the command:

```
find / -context "*shadow_t*"`
```

If your workflows absolutely _require_ the ability to access these files after
a role-transition from the default-user account to `root`, it will be necessary
to update the userData payload's `cloud-config` content to include a block
similar to:

```yaml
#cloud-config
system_info:
  default_user:
    name: <USERNAME>
    gecos: chimera default user
    lock_passwd: true
    selinux_user: unconfined_u
    sudo: ["ALL=(root) NOPASSWD:ALL"]
```

However, doing so will result in security scan-failures when the scanning-tool
tries to ensure that all locally-managed, interactive users are
properly-constrained users and, where appropriate, have SELinux
privilege-transition rules defined.

## Prerequisites

[`Packer`][2] by [Hashicorp][1] is used to manage the process of building
images.

### CI/CD Deployment Modes

The Chimera build system uses a **Docker-based approach** where all dependencies are baked into a portable container image. This provides consistent, reproducible builds across different environments.

#### Docker-Based Build System

The build system consists of:

1. **Docker Image**: `chimera-builder:YYYYMMDD` (~305 MB gzipped, ~834 MB uncompressed)
   - Based on Rocky Linux 9 (Iron Bank)
   - Includes: Packer, Ansible, AWS CLI, all plugins, roles, and collections
   - Portable: Can be transferred to air-gapped environments

2. **GitHub Actions Workflows**:
   - `offline-prepare.yml`: Builds Docker image, exports as tarball artifact
   - `build.yml`: Downloads artifact, runs builds inside container

3. **GitLab CI** (for air-gapped environments):
   - Import Docker tarball, run builds in container
   - No internet access required during builds

#### Deployment Environments

| Environment | Workflow | Credentials | Use Case |
|-------------|----------|-------------|----------|
| GitHub Actions | `offline-prepare.yml` → `build.yml` | OIDC role assumption | Online builds for Commercial AWS |
| GitLab CI | `.gitlab-ci.yml` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Air-gapped GovCloud builds |
| Local | Docker + `make` | Standard AWS env vars or profiles | Development and testing |

#### Prerequisites

Before running CI/CD builds, ensure:

1. **IAM Role Session Duration**: Must be ≥ 21600 seconds (6 hours) for long builds
2. **GitHub OIDC Provider**: Configure AWS to trust GitHub Actions OIDC tokens (GitHub Actions only)
3. **IAM Role**: Create a role with Packer and OpenTofu permissions

See [`docs/CI-CD-Setup.md`](docs/CI-CD-Setup.md) for detailed setup instructions.

### Local Build Prerequisites

1.  [Download][3] and extract `packer` for your platform. Add it to your PATH,
    if you like. On Linux, watch out for other `packer` executables with the
    same name (if building from an Enterprise Linux distro, `/sbin/packer` may
    be present due to the `cracklib-dicts` RPM).

2.  If building AMIs for Amazon Web Services, ensure your [AWS credentials are
    configured][4]. You do not really need the `aws` cli utility, but it is a
    convenient way to configure the credential file. You can also export the
    [environment variables][5]. Or, if running `packer` in an EC2 instance, an
    [instance role][6] with the requisite permissions will also work. See the
    [`packer` docs][7] for details on the necessary permissions.

    _NOTE_: No packer templates in this project will contain variables for AWS
    credentials; this is intentional, to avoid mistakes where credentials get
    committed to the repository. Instead, `packer` knows to read the
    credentials from the credential file or from the environment variables, or
    to retrieve them from the instance role. See the [docs][7].

## Usage

_NOTE_: In all steps below, the examples use syntax that works on Linux. If you
are running `packer` from a Windows system, simply use the appropriate syntax
for the _relative path_ to the packer template. Most important, for Windows,
use `.\` preceding the path to the template. E.g.
`.\chimera\minimal-linux.json`.

1.  Clone the repository:

    ```bash
    git clone https://github.com/MetroStar/chimera && cd chimera
    ```

2.  Validate the template (Optional):

    ```bash
    packer validate chimera/minimal.pkr.hcl
    ```

    The project-included Packer HCL files have been pre-validated. If you
    encounter validation-errors with the included HCL files, it means that
    you're using a newer Packer version than the project has been tested
    against. Please open an [issue][46] to report the problem, ensuring to
    include the Packer version you were using when you encountered the problem.

3.  Begin the build. This requires at least two variables,
    `chimera_identifier` and `chimera_version`. See the section [Packer Variables](#minimal-linux-packer-variables)
    for more details.

    ```bash
    packer build \
        -var 'chimera_identifier=unique-project-id' \
        -var 'chimera_version=dev001' \
        chimera/minimal.pkr.hcl
    ```

    _NOTE_: This will build images for _all_ the [builders defined in the
    template](#minimal-linux-packer-builders). Use `packer build --help` to
    see how to restrict the build to to a subset of the builders using the `-only`
    or `-except` arguments.

## Minimal Linux Packer Template

The Minimal Linux template builds STIG-partitioned images with a set of
packages that correspond to the "Minimal" install option in Anaconda. Further,
the AWS images include a handful of additional packages that are intended to
increase functionality in EC2 and make the images more comparable with Amazon
Linux.

-   _Template Path_: `chimera/minimal.pkr.hcl`

For all inputs to the template, see [chimera/README.md](chimera/README.md)

### Minimal Linux Packer Builders

The Minimal Linux `packer` template includes the following builders:

| Builder Name                                     | Description                                                      |
|--------------------------------------------------|------------------------------------------------------------------|
| `amazon-ebssurrogate.minimal-alma-9-hvm`         | amazon-ebs builder for a minimal Alma Linux 9 HVM AMI            |
| `amazon-ebssurrogate.minimal-amzn-2023-hvm`      | amazon-ebs builder for a minimal Amazon Linux 2023 HVM AMI       |
| `amazon-ebssurrogate.minimal-ol-9-hvm`           | amazon-ebs builder for a minimal Oracle Linux 9 HVM AMI          |
| `amazon-ebssurrogate.minimal-rhel-9-hvm`         | amazon-ebs builder for a minimal RHEL 9 HVM AMI                  |
| `amazon-ebssurrogate.minimal-rl-9-hvm`           | amazon-ebs builder for a minimal Rocky Linux 9 HVM AMI           |
| `amazon-ebssurrogate.minimal-ol-8-hvm`           | amazon-ebs builder for a minimal Oracle Linux 8 HVM AMI          |
| `amazon-ebssurrogate.minimal-rhel-8-hvm`         | amazon-ebs builder for a minimal RHEL 8 HVM AMI                  |

### Minimal Linux Packer Post-Provisioners

The Minimal Linux `packer` template includes the following post-provisioners:

-   `manifest`: The manifest post-provisioner records build artifacts.

## Building for the AWS US GovCloud Region

To build images for the AWS US GovCloud regions, `us-gov-west-1` or `us-gov-east-1`,
it is necessary to pass several variables that are specific to the region. The
AMI filters below have been tested and/or created in `us-gov-west-1` to work with the
_chimera_ template(s).

```bash
packer build \
    -var 'chimera_identifier=unique-project-id' \
    -var 'chimera_version=dev001' \
    -var 'aws_region=us-gov-west-1' \
    chimera/minimal.pkr.hcl
```

## Testing With amigen

The Chimera automation leverages the amigen8 and amigen9 projects as a
build-helpers for creation of EL8 and EL9 Amazon Machine Images,
respectively.  Due to the closely-coupled nature of the
two projects, it's recommended that any changes made to amigen8 or amigen9 be
tested with Chimera prior to merging changes to either project's master branch.

To facilitate this testing, the following runtime-variables were added to Chimera:

- `amigen8_source_branch`
- `amigen8_source_url`
- `amigen9_source_branch`
- `amigen9_source_url`

Using these runtime-variables allows one to point Chimera to
a fork/branch of amigen8 or amigen9 during a integration-test build. To test,
update your `packer` invocation by adding elements like:

```bash
packer build \
    -var 'amigen8_source_url=https://github.com/<FORK_USER>/amigen8.git' \
    -var 'amigen8_source_branch=IssueNN' \
    ...
    minimal.pkr.hcl
```

Similarly, these variables may be specified as environment variables by using [`PKR_VAR_<var_name>`][45]
declarations[^4] (e.g., `PKR_VAR_amigen8_source_branch`). To do so, change the
above example to:

```bash
export PKR_VAR_amigen8_source_branch="=https://github.com/<FORK_USER>/amigen8.git"
export PKR_VAR_amigen8_source_branch="IssueNN"

packer build \
    [...options elided...]
    minimal.pkr.hcl
```



[0]: http://iase.disa.mil/stigs/os/unix-linux/Pages/red-hat.aspx
[1]: https://www.hashicorp.com/
[2]: https://www.packer.io/
[3]: https://www.packer.io/downloads.html
[4]: http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html
[5]: http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html#cli-environment
[6]: http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html
[7]: https://www.packer.io/docs/builders/amazon.html
[10]: https://fedoraproject.org/wiki/EPEL
[11]: https://www.packer.io/docs/builders/amazon-ebs.html
[40]: https://github.com/MetroStar/amigen8
[41]: https://www.oracle.com/linux/
[42]: https://rockylinux.org/
[43]: https://almalinux.org/
[44]: https://www.suse.com/products/suse-liberty-linux/
[45]: https://developer.hashicorp.com/packer/guides/hcl/variables#from-environment-variables
[46]: https://github.com/MetroStar/chimera/issues/new
[47]: https://github.com/MetroStar/amigen9

[^1]: Because Chimera is primarily an execution-wrapper for the amigen projects, the "read the source" method for determining why things have changed from one spel-release to the next may require reviewing those projects' repositories
[^2]: The default-user is a local user (i.e., managed in `/etc/passwd`/`/etc/shadow`/`/etc/group`) that is dynamically-created at initial system-boot &ndash; using either the default-information in the `/etc/cloud/cloud.cfg` file or as overridden in a userData payload's `#cloud-config` content. Typically this user's `${HOME}/.ssh/authorized_keys` file is prepopulated with a provisioner's public SSH key.
[^3]: Overriding attributes of the default-user _must_ be done within a `#cloud-config` directive-block. If your userData is currently bare BASH (etc.), it will be necessary to format your userData payload as mixed, multi-part MIME.
[^4]: Use of the `PKR_VAR_` method is recommended for setting up CI/CD frameworks for producing AMIs and other supported VM-templates

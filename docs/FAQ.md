### Q: What OSes are currently supported?

A: The following OSes are currently supported via spel:

**Linux:**
- RHEL 8
- Oracle Linux 8
- RHEL 9
- Oracle Linux 9
- CentOS Stream 9
- Amazon Linux 2023

**Windows:**
- Windows Server 2016
- Windows Server 2019
- Windows Server 2022

Other ELx derivatives (Rocky, Alma) may work but have not been specifically tested.

**Deprecated (end-of-life):**
- RHEL 7 / CentOS 7 (EOL June 2024)
- CentOS 8 Stream (EOL September 2024)

### Q: Is RHEL or CentOS 8 Supported

A: Yes. Three EL8 distros are supported:

- Red Hat Enterprise Linux (RHEL) 8
- Oracle Linux (OL) 8

CentOS 8 Stream reached end-of-life in September 2024 and is no longer actively supported.

EL9 is also fully supported:

- Red Hat Enterprise Linux (RHEL) 9
- Oracle Linux (OL) 9
- CentOS Stream 9

Note: Initial functionality for any given ELx build orchestrated by spel starts with an amigen project. EL8 functionality is tracked in [amigen8](https://github.com/MetroStar/amigen8) and EL9 in [amigen9](https://github.com/MetroStar/amigen9).

### Q: What happened to support for EL6?

A: Red Hat Enterprise Linux 6 is in the last stages of the standard support-lifecycle's de-support phase. This support-lifecycle reaches its conclusion on November 30, 2020. Down-stream projects' &mdash; such as CentOS 6 &mdash; will conclude _their_ support-lifecycle in a similar time-frame. Further, our primary customer-base had begun the process of moving their solution-stacks to later ELx releases in October of 2018. Therefore, due to the pending demise of both EL6 and our primary customers' need for updated EL6 AMIs, we chose to cease publishing new EL6 images or testing spel functionality against el6 with the October 16<sup>th</sup>, 2018 AMI.

While it's possible that this automation can continue to be used to create new EL6 AMIs, we will not be continuing to test that functionality or publishing new EL6 AMIs

### Q: Are the images STIG-hardened?

A: The images include foundational STIG hardening that must be in place "from birth":

-   The images' root device is pre-partitioned to allow the various
    "`${DIRECTORY}` must be on its own filesystem" scan-tests to pass
-   SELinux is activated with user-confinement for the default user
-   FIPS mode is enabled (EL8/EL9)
-   EFI/SecureBoot support is included

For post-deployment STIG enforcement, the project includes SSM State Manager
associations (deployed via the `infra/` Terraform module) that automatically
apply STIG hardening on a schedule:

-   **EL8/EL9**: Ansible Lockdown roles (RHEL8-STIG, RHEL9-STIG)
-   **AL2023**: Native AWS STIG enforcement script
-   **Windows**: Custom wrapper around AWS-managed `AWSEC2-ConfigureSTIG` (also restores the built-in admin rename SID-500 → `maintuser`)

See the [SSM module README](../infra/modules/ssm/README.md) for details on
STIG enforcement associations.

### Q: Why aren't the images fully STIG-hardened at build time?

A. Full STIG hardening at build time would be impractical because:

-   Images are published in the following repositories
    -   Amazon Machine Image in AWS commercial region us-east-1
    -   Amazon Machine Image in AWS commercial region us-east-2
    -   Amazon Machine Image in AWS commercial region us-west-1
    -   Amazon Machine Image in AWS commercial region us-west-2
    -   Amazon Machine Image in AWS GovCloud region us-gov-west-1
    -   VirtualBox image in [Vagrant Cloud](https://vagrantcloud.com/)
    -   VMware image in Vagrant Cloud<sup>1</sup>
-   Proliferations for each of the above repositories exist for
    -   Red Hat 7<sup>2</sup>
    -   CentOS 7<sup>2</sup>
-   Images are produced monthly. This means maintaining 28 images per month for
    a minimum time-span of six to twelve months.

Additionally, the STIG contents contain multiple scanning/hardening profiles.
To support each profile would require a unique, pre-hardened image for each
"off the shelf" profile. This does not account for custom scanning/hardening
profiles. Supporting _all_ of the "off the shelf" profiles via pre-hardened
images would require generating 100+ images per month. Not practical on a
monthly basis; even less practical when extended across the six- to twelve-month
lifespan of images in multiple deployment domains (i.e., AWS, Vagrant Cloud...
and eventually Azure and possibly others).

Because of the above, we opted to keep AMIs as minimally-hardened as possible -
instead choosing to apply hardenings at launch-time using other frameworks.

### Q: So... Why would I use these images, then?

In general, once an image is launched as a VM, it requires considerable
gymnastics to re-layout the storage to meet STIG requirements. Those gymnastics
can vary from simply annoyingly labor-intensive to effectively "not possible".
This set of images solves that problem.

Similarly - relevant to EL7 images - attempting to enable FIPS at launch-time
requires sorting out how to automate launch-time provisioning processes across
multiple boots. While possible, it introduces gymnastics many would-be-users
don't want to have to sort out. This set of images avoids that problem.

### Q: Alright... Any suggestions for launching a hardened VM?

A. Many of our images' users leverage in-house build-workflows to handle
initial provisioning of image-sourced instances. They use things like Chef,
Puppet, Ansible, etc. Users that have no such in-house build-workflows, we
typically recommend our launch-driver,
[Watchmaker](https://github.com/MetroStar/watchmaker.git).

### Q. Watchmaker looks promising: how do I use it?

A. This FAQ is for using spel. That said Watchmaker includes a full
[documentation set](https://watchmaker.readthedocs.io) that should help you
with its use.


### Q. My application won't work under FIPS: now what?

A. If you're using EL7 or EL8 images, things can become a bit challenging if
the application you wish to host on a spel image is not FIPS-compatible. Our
images are FIPS-enabled because the STIGs say they need to be. As such, our
users ultimately need to figure out how to get their app to work under FIPS or
get an exception from their security team (sorta like firewalld and SELinux -
also baked in to the EL7 images).  These images are meant as a 90% solution. If
you're one of the unlucky 10% whose app won't work under FIPS in EL7, the best
we can suggest is to let your provisioning framework handle the problem for you.

### Q. But I'm following your suggestion to use Watchmaker: can that help me with toggling FIPS mode?

A. Yes. See watchmaker's [documentation](https://watchmaker.readthedocs.io/en/stable/faq.html)
for guidance.

### Q. The root volume-group and its partitions seem too small for my use-case: is there any way I can un-handcuff myself from the current partitioning-scheme?

A. Yes. The methods for doing so are dependent on EL version and deployment-contexts. As of this writing, we have documented how to deploy a VM using a root device that is larger than the templated default:

* [spel for EL7 on AWS](LargerThanDefaultRootEBS_EL7.md)
* spel for EL8 on AWS: see the previously-linked EL7 document &ndash; the methods are the same

Procedures for other deployment-contexts are not core to this project. Therefore, they have not been documented. Please feel free to experiment and [contribute](CONTRIBUTING.md)!

It is generally expected that if users need to grow an _existing_ instance's root volume group that they reprovision and follow the above linked-to documents. If reprovisioning is not practical, the next best option is to add a secondary drive to the VM and expand the root volume group onto the secondary drive.

### Q. My SSH keys don't work on the EL8 spel-images (but do on the EL7 spel-images)

A. The version of OpenSSH server on EL8, combined with associated security-settings, is a bit pickier about SSH keys used for authentication (key-based logins). Previous EL versions only requred the use of RSAv2 keys of at least 2048-bits' length. The EL8 OpenSSH server adds the further requirement that authentication-keys' signatures be some variety of SHA2. See the [OpenSSH and FIPS on EL8](OpenSSHandFIPS_EL8.md) document for more information.


##### Footnotes:
------

<sup>1</sup>: The VMware image-maker is currently broken. It's on our task-list
to address. However, [community contributions](CONTRIBUTING.md) are always
welcome! :smile:

<sup>2</sup>: Currently (see [issue #87](https://github.com/MetroStar/spel/issues/87)),
there are no VirtualBox builders for EL7. However,
[community contributions](../.github/CONTRIBUTING.md) are always welcome! :smile:

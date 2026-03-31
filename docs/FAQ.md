### Q: What OSes are currently supported?

A: The following OSes are currently supported via chimera:

**Linux:**
- RHEL 8
- Oracle Linux 8
- RHEL 9
- Oracle Linux 9
- CentOS Stream 9
- Amazon Linux 2023

**Windows:**
- Windows Server 2019
- Windows Server 2022

Other ELx derivatives (Rocky, Alma) may work but have not been specifically tested.

### Q: Is RHEL or CentOS 8 Supported

A: Yes. Two EL8 distros are supported:

- Red Hat Enterprise Linux (RHEL) 8
- Oracle Linux (OL) 8

EL9 is also fully supported:

- Red Hat Enterprise Linux (RHEL) 9
- Oracle Linux (OL) 9
- CentOS Stream 9

Note: Initial functionality for any given ELx build orchestrated by chimera starts with an amigen project. EL8 functionality is tracked in [amigen8](https://github.com/MetroStar/amigen8) and EL9 in [amigen9](https://github.com/MetroStar/amigen9).

### Q: Are the images STIG-hardened?

A: The images include foundational STIG hardening that must be in place "from birth":

-   The images' root device is pre-partitioned to allow the various
    "`${DIRECTORY}` must be on its own filesystem" scan-tests to pass
-   SELinux is activated with user-confinement for the default user
-   FIPS mode is enabled (EL8/EL9)
-   EFI/SecureBoot support is included

For post-deployment STIG enforcement, the project includes SSM State Manager
associations (deployed via the `infra/` OpenTofu module) that automatically
apply STIG hardening on a schedule:

-   **EL8/EL9**: Ansible Lockdown roles (RHEL8-STIG, RHEL9-STIG)
-   **AL2023**: Native AWS STIG enforcement script
-   **Windows**: Custom wrapper around AWS-managed `AWSEC2-ConfigureSTIG` (also restores the built-in admin rename SID-500 → `maintuser`)

See the [SSM module README](../infra/modules/ssm/README.md) for details on
STIG enforcement associations.

### Q: Why aren't the images fully STIG-hardened at build time?

A. Full STIG hardening at build time would be impractical because:

-   Images are published across multiple AWS commercial and GovCloud regions
    for each supported OS (EL8, EL9, AL2023, Windows)
-   Images are produced monthly, with each release maintained for six to twelve
    months across all regions

Additionally, the STIG contents contain multiple scanning/hardening profiles.
To support each profile would require a unique, pre-hardened image for each
"off the shelf" profile. This does not account for custom scanning/hardening
profiles. Supporting _all_ of the "off the shelf" profiles via pre-hardened
images would require generating 100+ images per month. Not practical on a
monthly basis; even less practical when extended across the six- to twelve-month
lifespan of images in multiple deployment domains.

Because of the above, we opted to keep AMIs as minimally-hardened as possible -
instead choosing to apply hardenings at launch-time using other frameworks.

### Q: So... Why would I use these images, then?

In general, once an image is launched as a VM, it requires considerable
gymnastics to re-layout the storage to meet STIG requirements. Those gymnastics
can vary from simply annoyingly labor-intensive to effectively "not possible".
This set of images solves that problem.

Similarly, attempting to enable FIPS at launch-time requires sorting out how
to automate launch-time provisioning processes across multiple boots. While
possible, it introduces gymnastics many would-be-users don't want to have to
sort out. This set of images avoids that problem.

### Q: Alright... Any suggestions for launching a hardened VM?

A. Many of our images' users leverage in-house build-workflows to handle
initial provisioning of image-sourced instances. They use things like Chef,
Puppet, Ansible, etc. Users that have no such in-house build-workflows, we
typically recommend our launch-driver,
[Watchmaker](https://github.com/MetroStar/watchmaker.git).

### Q. Watchmaker looks promising: how do I use it?

A. This FAQ is for using chimera. That said Watchmaker includes a full
[documentation set](https://watchmaker.readthedocs.io) that should help you
with its use.


### Q. My application won't work under FIPS: now what?

A. If your application is not FIPS-compatible, things can become a bit
challenging. Our images are FIPS-enabled because the STIGs say they need to be.
As such, users ultimately need to figure out how to get their app to work under
FIPS or get an exception from their security team (similar to firewalld and
SELinux, which are also baked in). These images are meant as a 90% solution. If
you're one of the unlucky 10% whose app won't work under FIPS, the best we can
suggest is to let your provisioning framework handle the problem for you.

### Q. But I'm following your suggestion to use Watchmaker: can that help me with toggling FIPS mode?

A. Yes. See watchmaker's [documentation](https://watchmaker.readthedocs.io/en/stable/faq.html)
for guidance.

### Q. The root volume-group and its partitions seem too small for my use-case: is there any way I can un-handcuff myself from the current partitioning-scheme?

A. Yes. For EL8 and EL9 on AWS, you can specify a larger root EBS volume at
launch time. The LVM-based partitioning scheme will automatically use the
additional space. See the [Storage Optimization](Storage-Optimization.md) guide
for details.

If you need to grow an _existing_ instance's root volume group,
reprovisioning with a larger root volume is the cleanest approach. If
reprovisioning is not practical, add a secondary drive and expand the root
volume group onto it.

### Q. My SSH keys don't work on the EL8 chimera-images

A. The version of OpenSSH server on EL8, combined with associated
security-settings, is pickier about SSH keys used for authentication. RSAv2
keys must be at least 2048 bits and use SHA2-based signatures. See the
[OpenSSH and FIPS on EL8](OpenSSHandFIPS_EL8.md) document for more information.

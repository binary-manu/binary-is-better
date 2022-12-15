---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan spelllang=en:
title: Setup Secure Boot on Arch Linux
category: Linux

arch_ansible_zip: https://github.com/binary-manu/arch-ansible/archive/refs/heads/master.zip
uefi_keys_diagram: "[![](https://mermaid.ink/img/pako:eNqVkb9ugzAQxl_ldHN4AYYOhEyoUqUuSHEHC1_ACvYh2wxRyLv3wCJKhwz1dP7u99n3544dG8IS-6CnAZQHOV8NFEXxsUTb-7g0pybLErzqdTWf6wrmyehEP2-QdmXav5AYM2R9THocyYD1iYXe8-07oN2JLQ9Lxz5poSANBIOOA3CA9W_re7jSDfiyVMdzxZygYzexJ5-eZbT_emV14QEdBaetkZHdV0WhmBwpLCU0OlwVKv8QLrd8MjZxwDKFmQ6o58TfN9_t98zUVsv0HZYXPUZRafN85r1s63n8Atg1ipA?type=png)](https://mermaid.live/edit#pako:eNqVkb9ugzAQxl_ldHN4AYYOhEyoUqUuSHEHC1_ACvYh2wxRyLv3wCJKhwz1dP7u99n3544dG8IS-6CnAZQHOV8NFEXxsUTb-7g0pybLErzqdTWf6wrmyehEP2-QdmXav5AYM2R9THocyYD1iYXe8-07oN2JLQ9Lxz5poSANBIOOA3CA9W_re7jSDfiyVMdzxZygYzexJ5-eZbT_emV14QEdBaetkZHdV0WhmBwpLCU0OlwVKv8QLrd8MjZxwDKFmQ6o58TfN9_t98zUVsv0HZYXPUZRafN85r1s63n8Atg1ipA)"
---

This article explains how to setup UEFI Secure Boot on Arch Linux, so
that the firmware can verify all components that sit between itself and
the kernel. This is useful if you need to dual-boot a PC that came with
Windows preinstalled and with Secure Boot enabled and you don't want to
keep it disabled after installing Arch.

To keep things simple, we'll use a VirtualBox machine running Arch as
our target system. This way, we do not have to worry about damaging a
working system by modifying the keys pre-enrolled in the firmware.

Only Secure Boot itself is covered: full disk encryption will be covered
in a separate article.

## Prerequisites

To prepare our Arch machine, we'll use [arch-ansible][arch-ansible], a
playbook designed to provision Arch VMs in minutes. There is already a
preset that builds a VirtualBox VM in UEFI mode.

This guide assumes the host is a Linux system, but it should work on
Windows hosts as well, although you'll have to adapt the commands run on
the host or perform equivalent operations from the GUI.

Before starting, you'll need to install the following tools:

* [VirtualBox 7 or higher][virtualbox]
* [HashiCorp Packer][packer]

Note that VirtualBox can't usually run alongside other hypervisors. If
you are currently running another virtualization tools such as QEMU, the
Android Emulator, VMWare Workstation or Hyper-V, you may need to stop
your VMs or disable the hypervisor first, in order to release the
hardware virtualization features of the CPU for VirtualBox to use.

## Prepare the VM

Now that the tools are in place, download [arch-ansible's
source]({{ page.arch_ansible_zip }}). From the host CLI type:

```bash
# We'll keep our configurations, the playbook and the produced
# OVF files here.
mkdir -p ~/arch-secure-boot/
cd ~/arch-secure-boot/
curl -sLo arch-ansible.zip {{ page.arch_ansible_zip }}
unzip -q arch-ansible.zip
cd arch-ansible-master
```

_WARNING: the snippet above always fetches the most recent version of
the playbook. Due to Arch's rolling release nature, older versions may
stop working every now and then. For the same reason, some commands may
have changed slightly over time. If the snippets below do not work as
expected, check manual pages to see if something changed._

Now we are in the root of the playbook. Before running it we must add an
extra configuration file: these extra settings prepare the disk for UEFI
boot by creating an ESP, and also add a user account:

```bash
cat << 'EOF' >> ansible/group_vars/all/50-uefi.yaml

# Use the gpt_singlepart partitioning flow, which creates
# a FAT32 ESP and installs GRUB to it.
disksetup_roles_prefix: "disksetup/gpt_singlepart/"

# Set root's password
users_root_info:
    password: "secboot"

# Create a 'secboot' user with password 'secboot'
users_info:
  secboot:
    password: "secboot"
    is_admin: true
    groups: []

EOF
```

After that, we can start the provisioning using Packer. This will create
a new VirtualBox VM with GUI, so you'll see it on your screen. Inside
the VM, a complete Arch installation goes on. When it's over, the VM
will be exported to OVF format. Don't interact with the VM during the
process, as this may interfere with installation: for example, the
provisioner will simulate keyboard input to the machine, and if you also
type text this will disrupt the process.

The installation can take a while, depending on your Internet
connection.

```bash
cd packer

# Build the machine
packer build -force -only virtualbox-uefi packer-template.json

# Import it into VirtualBox
VBoxManage import --vsys 0 output-virtualbox-uefi/*.ovf
```

Now you'll find the new VM (named `packer-<something>`) in VirtualBox.
Run it and Arch should start. Login with user `secboot` and password
`secboot`, then run `startx` to start XFCE.

## A short explanation of Secure Boot

### UEFI keys

Secure Boot is a feature of UEFI firmwares which increases the security
of the system by booting only components (such as bootloaders and
kernels) which are _trusted_. There are two ways to mark a component as
trusted:

* sign it: the component is signed using the private part of an
  asymmetric key pair (usually RSA2048); the public part then needs to
  be loaded into the firmware database of trusted keys;
* enroll its hash: the digest (usually SHA256) of such component is
  stored into the firmware database of trusted hashes. In UEFI, keys and
  hashes share the same database, which is described below.

Both methods work, but each one have drawbacks: hashes are easier than
keys to work with. However, they change every time a file is modified,
so if a boot component is updated frequently (for example, GRUB gets
updated), the new hash must be enrolled in the firmware, which can be a
hassle.

Signing is more articulated, but since we only enroll the keys, as long
as those keys can be used (i.e. the have not been compromised) there is
no need to update the firmware database.

In this guide, we will go the signing route. Before that, we need to
briefly talk about the key infrastructure in UEFI. More details are
available [in this article][secboot-keys].

Every UEFI Secure Boot implementation starts with the _PK_ (_Platform
Key_).  This is the most important key, as it is used as the root of
trust chains. Secure Boot cannot be enabled unless a PK has been
enrolled and there is usually only one PK. The PK is not directly used
to sign boot components.  Instead, it is used to:

* disable Secure Boot;
* sign KEKs, the next level of keys.

A _KEK_ (_Key Exchange Key_) can be added to the UEFI only if it's
signed with the PK, and it's role is to sign updates to the keys/hashes
database.  There can be many KEKs enrolled at the same time.

The keys and hashes used to validate boot components reside in the _DB_
and _DBX_ databases:

* DB is an allowlist that contains keys and/or hashes. If a component is
  signed with a key stored here, or its hash is stored here, the
  component is allowed to boot;
* DBX is a denylist and works just like DB, with the obvious exception
  that if a key or hash is stored here, components signed with that key
  or matching that hash _will not_ be allowed to boot.

DBX takes precedence over DB when doing checks: a component will be
allowed to boot if it doesn't match DBX but matches DB. If it matches
neither, it will not boot, since it cannot be verified using the
enrolled keys. Updates to DB or DBX are accepted only if signed by a
KEK.

This diagram summarizes signed-by relationships between keys and
databases:

{{ page.uefi_keys_diagram }}

While a user can generate and enroll it own PK, KEKs, and DB keys, doing
so poses some issues. First, some systems, like corporate laptops, come
with Secure Boot on, so there must already be a PK and KEK, plus some
keys or hashes in the DB. Removing them will make the system unbootable
unless they are re-enrolled or the boot components are signed with the
new keys. Second, these keys are sometimes used to sign UEFI drivers and
again, removing them prevents these drivers from loading. This is
especially painful when the driver in question is the GPU one, since it
means you will no longer get video output (see [this post on
Reddit][gpu-brick]).

However, to enroll keys to DB, we need to know the private part of at
least one KEK or enroll a new one. And to enroll a new KEK we need the
private part of the PK.  Which we don't usually have if these came
pre-enrolled and belong to some big vendor.  There are two solutions to
this problem.

The first solution involves the fact that most UEFI management GUIs
allow the enrollment of new keys even if you don't know the PK or a KEK.
However, for the reasons above, I'd prefer not to fiddle with PK/KEK/DB.
So we move to the second solution. Meet _shim_.

### The _shim_ bootloader

[_shim_][shim] is an open source bootloader, designed to work as a
bridge between the default keys that come pre-enrolled in most Windows
PCs and boot components signed by the user.

We said that when Secure Boot is on, only signed components can boot.
And the trusted keys pre-enrolled in the UEFI usually belong to
Microsoft for a Windows PC. Thus, only Microsoft can sign stuff, And
they usually don't. First, they don't sign GNU GPL licensed software for
policy reasons. Second, having to sign builds of fast-moving FOSS
projects for different distros (since every distro ships its own binary
for GRUB and the kernel) would be impractical. However, Microsoft _signs
official pre-built shim binaries_. Thus, shim will usually boot on PCs
that come with Windows preinstalled, even when Secure Boot is enabled.

shim, by itself, does very little. It simply verifies the signature of a
next-stage bootloader (usually GRUB) and loads it. The _very important_
thing to note is that, in addition to the keys/hashes in DB, shim can
also use its own, dedicated database of keys and hashes, called the _MOK
(Machine Owner Key) database_.

MOKs can be enrolled by the user using a combination of command line
utilities from Linux plus a shim helper called _MOKManager_. Altering
the MOK database may make your Linux distro unbootable, but has no
effect on things signed using the other UEFI keys, so there is no risk
of loosing the video card.

The rest of this article will show how to setup shim and MOKManager,
generate our MOK, enroll it and use it to sign GRUB and the kernel.
We'll start with an Arch Linux installation on a UEFI system with Secure
Boot disabled, prepare it for Secure Boot and then enable it.

To avoid generating and enrolling our own set of PK/KEK/DB keys into the
VM UEFI, we'll use a new feature of VirtualBox 7.x, which can
automatically enroll well-known Microsoft keys.

## Setup

### Install shim and other utils

The very first thing to do is installing shim and a bunch of utilities
that will be needed to enrolls MOKs and sign files. You'll need to use
an AUR helper to install shim. The test machine comes with `yay`.

```bash
yay -S shim-signed mokutil sbsigntools efitools
```

Installing this packages will _not_ put shim into the ESP. We'll need to
copy files manually. `pacman -Ql shim-signed` reveals the following:

```
shim-signed /usr/
shim-signed /usr/share/
shim-signed /usr/share/shim-signed/
shim-signed /usr/share/shim-signed/fbia32.efi
shim-signed /usr/share/shim-signed/fbx64.efi
shim-signed /usr/share/shim-signed/mmia32.efi
shim-signed /usr/share/shim-signed/mmx64.efi
shim-signed /usr/share/shim-signed/shimia32.efi
shim-signed /usr/share/shim-signed/shimx64.efi
```

We need to copy the 64-bit versions of shim and MOKManager, which
correspond to `shimx64.efi` and `mmx64.efi`. They will go under
`/boot/efi/EFI/arch`, where `arch` is the folder that GRUB created
during the install. Don't worry about breaking the non-Secure Boot
setup, this folder is duplicated as `/boot/efi/EFI/Boot`, the default
boot path to use when no boot variable is defined in the UEFI.

```bash
# Copy shim and MOKManager
sudo cp /usr/share/shim-signed/{shim,mm}x64.efi /boot/efi/EFI/arch

# Add a new boot entry for shim
sudo efibootmgr -c --loader '\EFI\arch\shimx64.efi' --label ArchLinux
```

Note how `efibootmgr` created a new entry:

```
   BootCurrent: 0001
   Timeout: 0 seconds
👉 BootOrder: 0004,0000,0001,0002,0003
   Boot0000* UiApp	FvVol(7cb8bdc9-f8eb-4f34-aaea-3ee4af6516a1)/FvFile(462caa21-7614-4503-836e-8ab6f4662331)
   Boot0001* UEFI VBOX HARDDISK VBbd970c88-d62b41ba 	PciRoot(0x0)/Pci(0xd,0x0)/Sata(0,65535,0){auto_created_boot_option}
   Boot0002* UEFI PXEv4 (MAC:080027DE02FE)	PciRoot(0x0)/Pci(0x3,0x0)/MAC(080027de02fe,1)/IPv4(0.0.0.00.0.0.0,0,0){auto_created_boot_option}
   Boot0003* EFI Internal Shell	FvVol(7cb8bdc9-f8eb-4f34-aaea-3ee4af6516a1)/FvFile(7c04a583-9e3e-4f1c-ad65-e05268d0b4d1)
👉 Boot0004* ArchLinux	HD(1,GPT,7e16b474-4294-4fe3-8570-0dfec47972a9,0x800,0x100000)/File(\EFI\arch\shimx64.efi
```

The `BootOrder` line  shows in which order boot entries are tried.  shim
is 0004, the first item, so if we rebooted now, shim would be loaded.
Don't do that yet, because shim is only a bridge that calls a next stage
bootloader, but we haven't installed one yet.  We'll use GRUB as our
next-stage bootloader, but before that we need to sign it, and before
signing anything, we must generate and enroll our MOK.

### MOK generation

MOKs are simply X.509 certificates paired with their private keys, and
can be generated using `openssl`. Pay attention to the opening and
closing parentheses in the snippet below, they must be copied too.

```bash
(
  umask 077
  sudo mkdir /etc/secure-boot
  sudo openssl req                       \
    -new                                 \
    -x509                                \
    -nodes                               \
    -newkey rsa:2048                     \
    -keyout /etc/secure-boot/mok.key.pem \
    -out    /etc/secure-boot/mok.crt.pem \
    -subj   "/CN=Manu's MOK/"            \
    -days   9999
  sudo openssl x509                      \
    -in  /etc/secure-boot/mok.crt.pem    \
    -out /etc/secure-boot/mok.crt.der    \
    -outform DER
)
```

We have created a folder `/etc/secure-boot` only accessible to root,
that will store all our Secure Boot related stuff.  Inside it, we have a
PEM private key (RSA 2048) and a self-signed certificate. The private
key is not encrypted: a fact that will make it easier to automatically
sign GRUB and kernels on updates, but also means than anyone who can
read the file can get our MOK. That's why it is critical that the folder
can only be accesses by root.  In addition, we converted the certificate
from PEM to DER form: `mok.crt.*` files store the same exact data in two
different representations. This is because some tools require the
former, while others require the latter.

### Schedule the MOK for enrollment

The `mokutil` tool can be used to inspect, add and remove keys from the
MOK database. Actually, it doesn't really add (or remove) keys, it
schedules them for addition (or removal). The real update will be
performed during the next reboot when shim is loaded.

To schedule our new MOK for addition, type:

```bash
sudo mokutil --import /etc/secure-boot/mok.crt.der
```

You'll be asked for a password twice: type whatever you want. This
password will be asked by MOKManager when enrolling the key later after
reboot. Pay attention to the fact that you may also be asked for your
system password by `sudo` before that.

Note two things:

* `mokutil` requires DER data;
* we are uploading the certificate, not the key file. Only the public
  key is added to the MOK database, and the certificate contains the
  public key as well as other information such as the Common Name of the
  owner.

### Install GRUB

Normally, we would install GRUB using the `grub-install` script. This
installation mode places a small EFI executable on the ESP, while
leaving the rest of GRUB (such as modules) on `/boot`. GRUB can
dynamically load the rest of its modules at runtime.  However, when
running under Secure Boot, loading code from external files is disabled:
everything must reside into the EFI executable on the ESP.

To create such an image, GRUB provides `grub-mkstandalone`. It builds an
EFI image containing all (or a user-supplied list of) GRUB modules, plus
an initial configuration file. This is what we'll sign and deploy.

The initial configuration file can be used to customize the behaviour of
GRUB when it starts. A typical use case is to make it load an external
configuration file located on the ESP. The external file can then be
regenerated using `grub-mkconfig` without altering (and thus re-signing)
the EFI image. Note that, unlike modules, loading external configuration
_is_ allowed.

To create our image, type:

```bash
# Generate the embedded configuration file
sudo dd status=none of=/etc/secure-boot/grub.cfg << 'EOF'
configfile ${cmdpath}/grub.cfg
EOF

# Generate the EFI all-in-one image
sudo grub-mkstandalone                           \
  --compress=xz                                  \
  --format=x86_64-efi                            \
  --modules='part_gpt part_msdos'                \
  --sbat=/usr/share/grub/sbat.csv                \
  --output=/boot/efi/EFI/arch/grubx64.efi        \
  /boot/grub/grub.cfg=/etc/secure-boot/grub.cfg

# Generate full configuration
sudo grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg
```

Let's explain some of the options:

* `compress` requests that the EFI file is compressed to save space.
  Here we used XZ compression, the slowest but most efficient one;
* `format` specifies the format of the output file. `x86_64-efi` means
  we want something suitable for a 64-bit UEFI system;
* `output` is the place where the output file will live. We are going to
  reuse the `arch` entry created by the installer, so GRUB is placed
  there. _Important_: don't change the base name: it _MUST_ be
  `grubx64.efi`. shim will only load a file with this name;
* `modules` lists which modules must be preloaded when GRUB starts: here
  we ask to preload modules that parse legacy and GPT partitioning
  schemes. Without this, GRUB may be unable to detect disk partitions at
  boot;
* `sbat` is the most interesting. _Secure Boot Advanced Targeting_ is a
  feature that embeds generation numbers of boot components inside them
  to make it easier for a bootloader to determine if a boot component is
  vulnerable. Arch's GRUB package comes with its own SBAT definition
  file, which must be embedded into the final EFI image. shim will
  refuse to load stuff without SBAT information. For more details about
  SBAT, see [this page][sbat];
* the last line copies the embedded configuration file into the image,
  making it available as `/boot/grub/grub.cfg`. The GRUB image contains
  an embedded filesystem known as `(ramdisk)` which can be accessed like
  any other volume, for example `(hd0,gpt1)`.

The syntax of files copied into the ramdisk is
`/path/into/image=/path/on/filesystem`. `/boot/grub/grub.cfg` is the default
configuration file loaded by GRUB when it starts, so we must name it as
such. Its contents do nothing more than immediately directing GRUB to
load an external configuration `${cmdpath}/grub.cfg`. The `cmdpath`
variable is a runtime value provided by GRUB that points to the folder
containing the EFI image. It allows referring to files installed
alongside GRUB without having to explicitly state paths and thus makes
configurations reusable. In our case, it will expand to GRUB's notion of
`/boot/efi/EFI/arch`, which may be something like `(hd0,gpt1)/EFI/arch`.

The last thing to do to have a working GRUB is to sign it. For this, we
must use `sbsign`:

```bash
sudo sbsign                               \
  --key    /etc/secure-boot/mok.key.pem   \
  --cert   /etc/secure-boot/mok.crt.pem   \
  --output /boot/efi/EFI/arch/grubx64.efi \
           /boot/efi/EFI/arch/grubx64.efi
```

The PEM MOK key and certificate plus the unsigned GRUB image get in, and
a signed image gets out. Note that you can use the same pathname for
both input and output and that, unlike `mokutil`, the DER certificate is
not used here.

With this step, we have completed your deployment of shim and GRUB,
including configuration files and signatures. Secure Boot is still
disabled, since the machine lacks a PK, as can be proven by issuing:

```bash
sudo efi-readvar
```

The output reports that all key DBs are empty.

### Sign the kernel

Just like GRUB, the kernel must also be signed, while initramfses need
not be signed. Again, `sbsign` comes to the rescue. For simplicity,
we'll sign just one kernel here, in spite of the fact that a real system
may have multiple kernels installed and all of them need to be signed.
We'll handle this issue later, when we'll setup `pacman` hooks to
automatically sign GRUB and the kernels on updates.

```bash
sudo sbsign                               \
  --key    /etc/secure-boot/mok.key.pem   \
  --cert   /etc/secure-boot/mok.crt.pem   \
  --output /boot/vmlinuz-linux            \
           /boot/vmlinuz-linux
```

We'll now reboot the system to trigger MOKManager and add the new MOK to
the database.

### Enroll the MOK via MOKManager

Restart the machine. Now, instead of GRUB, we'll see a blue screen. This
is MOKManager, a UEFI application that takes care of enrolling and
removing MOKs from the system. The following short video shows how to
enroll the keys. A textual description of the steps follow.

<video controls width="100%">
  <source src='{{ "/assets/my/mov/mokmanager.mp4" | relative_url }}'>
</video>

shim noticed that some MOKs are scheduled for addition and launched
MOKManager to handle that. We have 10 seconds to press a key, otherwise
the boot will continue and our scheduled MOK will be forgotten,
requiring us to call `mokutil` again.

We can choose to enroll a MOK from a disk file or from the list of
pending keys. Choose `Enroll MOK` to do the latter, since MOKManager
cannot read `ext4` or other POSIX filesystems.

Is it possible to view the key before enrolling it, to be sure of its
contents.  That confirms the key's identity.

Press a key to go back to menu and now choose `Continue`: MOKManager
will ask for confirmation to enroll. The last step is to enter the
password chosen previously when calling `mokutil`. After, that it asks
for a reboot, which we accept. The MOK is now enrolled, altough Secure
Boot is still disabled.

### Enable Secure Boot in VirtualBox

After shutting down the VM, open its settings and go under `System`. The
lower part of the window shows the Secure Boot settings. First, check
the `Enable Secure Boot` box, then click the `Reset Keys to Default`
button.  Answer `Yes` to the confirmation dialog. Now restart the
machine.

![Enable Secure Boot in VirtualBox][vbox-sb]

On a real machine, the keys would be already there, so the only step
needed would be to switch Secure Boot on.

_WARNING: don't press `Reset Keys to Default` more than once. If you
uncheck and then check `Enable Secure Boot` the button becomes active
again, but it seems that every time it's clicked, VirtualBox appends,
rather than replacing, UEFI keys. This results in a weird state that
makes Secure Boot unusable._

Linux should now boot and prove that we deployed and signed all pieces
correctly. When in Linux, use the following commands to list all keys:

```bash
sudo mokutil --list-enrolled # Shows the MOKs
sudo efi-readvar             # Shows PK/KEK/DB/DBX
```

## Automate signing on updates

Until now, we've signed stuff manually. This is educational, but will
break as soon as the kernel is upgraded: the new kernel won't be signed
and won't boot. Also, we signed just the default kernel, but
realistically we may have a bunch of them installed: LTS, Zen, …

Luckily, `pacman` hooks can be used to automatically run scripts during
the installation of packages. We can setup a couple of them to
automatically sign new kernels and GRUB.

### Sign GRUB

We'll arrange that, when the GRUB package is updates, a hook takes care
of regenerating the standalone image, signing it and copying it in place
of the old one, while preserving the most recent old version, in case
the new image has problems.

This is the hook definition:

```bash
sudo mkdir -p /etc/pacman.d/hooks

sudo dd status=none of=/etc/pacman.d/hooks/99-sign-grub-for-secure-boot.hook << 'EOF'
[Trigger]
Operation = Upgrade
Type      = Package
Target    = grub

[Action]
Description = Sign GRUB with Machine Owner Key for Secure Boot
When        = PostTransaction
Exec        = /etc/secure-boot/sign-grub
Depends     = sbsigntools
EOF
```

The actual code is located in a separate script file for readability:

```bash
sudo dd status=none of=/etc/secure-boot/sign-grub << 'EOF'
#!/bin/sh

set -e

GRUB_ENTRY=/boot/efi/EFI/arch
GRUB_TMP="$GRUB_ENTRY/grubx64.efi.tmp"
GRUB_TARGET="$GRUB_ENTRY/grubx64.efi"
GRUB_BACKUP="$GRUB_ENTRY/grubx64.efi.bkp"
GRUB_CFG="$GRUB_ENTRY/grub.cfg"
GRUB_CFG_TMP="$GRUB_ENTRY/grub.cfg.tmp"
GRUB_CFG_BACKUP="$GRUB_ENTRY/grub.cfg.bkp"
GRUB_SBAT="/usr/share/grub/sbat.csv"

trap '/usr/bin/rm -f "$GRUB_TMP" "$GRUB_CFG_TMP"' QUIT TERM INT EXIT

/usr/bin/grub-mkstandalone                        \
  --compress=xz                                   \
  --format=x86_64-efi                             \
  --modules='part_gpt part_msdos'                 \
  --sbat="$GRUB_SBAT"                             \
  --output="$GRUB_TMP"                            \
  '/boot/grub/grub.cfg=/etc/secure-boot/grub.cfg'

/usr/bin/sbsign                         \
  --key    /etc/secure-boot/mok.key.pem \
  --cert   /etc/secure-boot/mok.crt.pem \
  --output "$GRUB_TMP"                  \
  "$GRUB_TMP"

/usr/bin/grub-mkconfig -o "$GRUB_CFG_TMP"

/usr/bin/cp "$GRUB_TARGET" "$GRUB_BACKUP"
/usr/bin/cp "$GRUB_CFG" "$GRUB_CFG_BACKUP"

/usr/bin/mv "$GRUB_TMP" "$GRUB_TARGET"
/usr/bin/mv "$GRUB_CFG_TMP" "$GRUB_CFG"
EOF

sudo chmod a+x /etc/secure-boot/sign-grub
```

Every time the package named `grub` is updated, the hook script runs. It
generates a new standalone image in a temporary file, so that the real
GRUB loaded by shim is not overwritten until the very end. It then signs
the new image and regenerates the configuration file. The last step
moves both temporary files into their final positions. Since the two
rename operations are not atomic, there is chance that an error between
them could leave GRUB and its configuration out of sync. All files
already reside on the correct volume: the probability should be pretty
low.

To test if it's working, we can reinstall `grub`:

```bash
sudo pacman -S grub --noconfirm
```

If pacman spits no errors, everything went fine. You should also see log
messages produced by the hook.

### Sign kernels

The last step is to also arrange for kernel images to be signed. The
procedure is very similar to what we did for GRUB, but we must handle

```bash
sudo dd status=none of=/etc/pacman.d/hooks/99-sign-kernels-for-secure-boot.hook << 'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type      = Package
Target    = linux
Target    = linux-lts
Target    = linux-zen
Target    = linux-hardened

[Action]
Description = Sign kernels with Machine Owner Key for Secure Boot
When        = PostTransaction
Exec        = /etc/secure-boot/sign-kernels
Depends     = sbsigntools
Depends     = findutils
Depends     = grep
EOF
```

Every `Target` line matches a kernel package. You should add any
additional kernel you are using.

```bash
sudo dd status=none of=/etc/secure-boot/sign-kernels << 'EOF'
#!/bin/sh

set -e

/usr/bin/find /boot/ -maxdepth 1 -name 'vmlinuz-*' -exec /bin/sh -c '
  if ! /usr/bin/sbverify --list {} 2>/dev/null |
      /usr/bin/grep -q "signature certificates"; then
    /usr/bin/sbsign                       \
      --key  /etc/secure-boot/mok.key.pem \
      --cert /etc/secure-boot/mok.crt.pem \
      --output {} {}
  fi
' \;
EOF

sudo chmod a+x /etc/secure-boot/sign-kernels
```

Again, reinstall a kernel to verify it's working:

```bash
sudo pacman -S linux --noconfirm
```

## Closing thoughts

This guide shows how to setup your Arch Linux installation to work under
Secure Boot, using shim, GRUB and your own MOK keys. This solution is
probably the less invasive ones, as the standard UEFI variables and
databases are not touched. This should prove sufficient to run your
distribution alongside Windows.

There is one point we have not covered here: disk encryption. Secure
Boot can make you system more hard to crack, but it's pretty useless if
your partitions are accessible in the clear to anyone who can simply
remove the disk and place it into another machine. Normally, one would
use LUKS together with Secure Boot. Disk encryption will be the topic for
another article.

It is also recommended to lock the UEFI management UI with a password.
Otherwise, an attacker could just enter the firmware and disable Secure
Boot.

## Suggested readings

* [Managing EFI Boot Loaders for Linux by Rod Smith][rodsuefi]
* [ArchWiki: Unified Extensible Firmware Interface/Secure Boot][archwiki-uefi]
* [NSA: Boot Security Modes and Recommendations][nsa-uefi]

[arch-ansible]: https://github.com/binary-manu/arch-ansible
[virtualbox]: https://www.virtualbox.org/
[packer]: https://www.packer.io
[secboot-keys]: https://blog.hansenpartnership.com/the-meaning-of-all-the-uefi-keys/
[gpu-brick]: https://www.reddit.com/r/archlinux/comments/pec41w/secure_boot_selfsigned_keys_nvidia_gpu_bricked/
[shim]: https://github.com/rhboot/shim
[sbat]: https://github.com/rhboot/shim/blob/main/SBAT.md
[vbox-sb]: {{ "/assets/my/img/vbox_sb.png" | relative_url }}
[rodsuefi]: http://www.rodsbooks.com/efi-bootloaders/index.html
[archwiki-uefi]: https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot
[nsa-uefi]: https://media.defense.gov/2019/Jul/16/2002158058/-1/-1/0/CSI-BOOT-SECURITY-MODES-AND-RECOMMENDATIONS.PDF

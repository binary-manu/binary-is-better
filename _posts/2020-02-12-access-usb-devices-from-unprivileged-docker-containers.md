---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan :
title:  Access USB devices from unprivileged Docker containers
categories: Docker
---
# {{ page.title }}

Sometimes, a containerized application may need to access devices from
the host. For example, we might be testing serial console tools inside a
container, and need to pass the device node for our serial port to the
container, for example `/dev/ttyUSB0`.

## Single device or multiple devices

When using Docker, we can request a single device to be made available
within the container by using the `--device` options of the `run`
command. This way that device node, and only that, is passed to the
container and made accessible.

In some cases, passing single device nodes may be unsuitable. A typical
case is allowing a tool to access devices which can appear and disappear
and thus change name. Let's say, in our previous example, that I start
with a serial converter mapped to `/dev/ttyUSB0`, then it gets
unplugged, a different serial device is plugged in and the original
device is reattached. At this point the once-`ttyUSB0` has become
`/dev/ttyUSB1`, which is not available to the container.

A potential solution is to deploy a udev rule that gives the device node
a fixed name, based on some attribute of the device (such as its vendor
id or product id).

There is a case, however, which cannot be easily covered by udev rules:
USB devices. The kernel provides devices nodes for USB peripherals under
`/dev/bus/usb`. Each time a device is removed and attached, a new device
node is created, but its name is always changing.

For example, this is my `/dev/bus/usb` right now:

    /dev/bus/usb
    ├── 001
    │   ├── 001
    │   ├── 002
    │   └── 003
    [skip]
    ├── 005
    │   ├── 001
    │   ├── 002
    │   ├── 003
    │   ├── 004
    │   └── 005
    [skip]

Now, let's take a snapshot of that directory again after I have attached
and reattached my USB mouse dongle:

    /dev/bus/usb
    ├── 001
    │   ├── 001
    │   ├── 002
    │   └── 003
    [skip]
    ├── 005
    │   ├── 001
    │   ├── 002
    │   ├── 003
    │   ├── 005
    │   └── 006
    [skip]

Note that the device `005/004` has been renamed `005/006`. A quick look
at what `lsusb` has to say confirms that it is actually my mouse.

Again, we are in a situation where no single device can be passed. So we
have to resort to something different. If we cannot pass a single device
node, we can pass the entire `/dev/bus/usb` folder to the container.
This is pretty easy to do using bind mounts:

    $ docker run -it --rm -v /dev/bus/usb:/dev/bus/usb \
        ubuntu:bionic ls /dev/bus/usb

    001  002  003  004  005  006  007  008

Let's check that without the bind mount that path does not exist:

    $ docker run -it --rm ubuntu:bionic ls /dev/bus/usb

    ls: cannot access '/dev/bus/usb': No such file or directory

OK, so far so good. Let's check the permissions of one of those devices:

    $ docker run -it --rm -v /dev/bus/usb:/dev/bus/usb \
        ubuntu:bionic ls -lh /dev/bus/usb/005/007

    crw-rw-r-- 1 root root 189, 518 Feb 10 20:02 /dev/bus/usb/005/007

It's root-owned and has read/write permissions for the owner. This is
not so relevant, however, since our container processes are by default
run as `root` (we didn't specify a different user using the `-u` option
for `docker run`) and so they posses the `CAP_DAC_OVERRIDE` capability.

To verify if we can access it, let's try opening the device for reading:

    $ docker run -it --rm -v /dev/bus/usb:/dev/bus/usb ubuntu:bionic \
        dd if=/dev/bus/usb/005/007 bs=1 count=0

    dd: failed to open '/dev/bus/usb/005/007': Operation not permitted

Now, this is weird. The device node shows up inside the container and we
are root. But we cannot open it. Why?

## Control groups (cgroups)

This has to do with one of the technologies that underpin the entire
Linux containers world: _cgroups_. With them, it is possible to define
control policies for resources managed by the kernel, such as CPU time
and memory. [This document][cgroups] can be a good starting point to the
topic for those who care. Basically, they are a way to flexibly define
and enforce usage limits that processes must obey. For example, a
process may not be allowed to use more than a certain amount of system
memory. Every kind of resource that can be affected by cgroups is called
a _resource controller_ or _subsystem_.

Now, among the many resource controllers the kernel provides, there is
the _devices_ controller, which defines how processes can access device
nodes: more about it can be read [here][cgroup-devices]. Each cgroup for
this controller can define rules that either allow or deny access to
specific devices, depending on their type (character or block), their
major and minor numbers, and the operation we want to perform (read,
write, mknod).

By default, unprivileged Docker containers (those not created with the
`--privileged` option) are placed in a cgroup that allows access to just
a few device nodes.

However, there is a way to tell Docker to add additional rules to this
cgroup before launching the container: `--device-cgroup-rule`.
It must be added to the `run` command and is followed by a rule
specification. The full definition of rules can be found in the devices
subsystem documentation, but for now let's get away with the following:

    a|b|c MAJOR_OR_ASTERISK:MINOR_OR_ASTERISK [r][w][m]

Basically, the first field is a letter among `b`, `c` and `a`,  which
defines the device node type: block, character and all. It is followed
by the major and minor numbers separated by a colon; an asterisk can be
used instead of a number to match all majors, all minors or both.
Finally, the last field defines the allowed operations: read, write,
mknod. Any combinations of operations can be specified in a single rule.

To see what Docker allows by default in an unprivileged container, we can
dump the contents of
`/sys/fs/cgroup/devices/docker/$CONT_ID/devices.list`, the whitelist of
allowed devices for the container whose ID is `$CONT_ID`:

    $ CONT_ID=$(docker run -id ubuntu:bionic)
    $ cat "/sys/fs/cgroup/devices/docker/$CONT_ID/devices.list"

    c 1:5 rwm
    c 1:3 rwm
    c 1:9 rwm
    c 1:8 rwm
    c 5:0 rwm
    c 5:1 rwm
    c *:* m
    b *:* m
    c 1:7 rwm
    c 136:* rwm
    c 5:2 rwm
    c 10:200 rwm

    $ docker container rm --force "$CONT_ID"

Back to our previous test, which failed to call `dd`. This device has a
major of 189 and is a character device. Since there is no rule that
explicitly allows access to such device in the previous list, we got an
error. Let's try calling `dd` again, but this time we tell Docker to
allow read and write access to every character device with a major of
189:

    $ docker run -it --rm -v /dev/bus/usb:/dev/bus/usb \
        --device-cgroup-rule 'c 189:* rw' ubuntu:bionic \
        dd if=/dev/bus/usb/005/007 bs=1 count=0

    0+0 records in
    0+0 records out
    0 bytes copied, 3.2911e-05 s, 0.0 kB/s

No error this time! Let's check the new list of rules for the container
cgroup:

    $ CONT_ID=$(docker run -id --device-cgroup-rule 'c 189:* rw' \
        ubuntu:bionic)
    $ cat "/sys/fs/cgroup/devices/docker/$CONT_ID/devices.list"

    c 1:5 rwm
    c 1:3 rwm
    c 1:9 rwm
    c 1:8 rwm
    c 5:0 rwm
    c 5:1 rwm
    c 189:* rw
    c *:* m
    b *:* m
    c 1:7 rwm
    c 136:* rwm
    c 5:2 rwm
    c 10:200 rwm

    $ docker container rm --force "$CONT_ID"

Note that now there is a rule allowing read and write access to all character
devices with a major of 189.

## Recap

If you need to access USB devices from a container:

* bind-mount `/dev/bus/usb` inside the container;
* take note of the type, major and minor of the device(s) you need to
  access;
* pass the corresponding rule to `--device-cgroup-rule`

It should be noted that it is possible to be lazy and just run the
container as privileged. This allows access to all devices without the
need to mess with cgroups. However, it provides a much broader access to
the host than we need in most cases.

If the devices have a dynamic major, using a rule like `c *:* rw` is
still better than using `--privileged`.

[cgroups]: https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v1/cgroups.html
[cgroup-devices]: https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v1/devices.html

---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan :
title: Screen autoresize under VirtualBox Linux guests with mplugd
category: virtualbox
---

# Screen autoresize under VirtualBox Linux guests with `mplugd`

Users of [VirtualBox][virtualbox] know that one of its nicest features
is _automatic guest screen resizing_. Basically, every time you perform
an action that causes the VM window to change its size (i.e. switch it
between fullscreen and windowed mode, or change its size by dragging a
border) the guest will receive an event that will cause it to change the
screen resolution to match the effective window size. This means that,
when fullscreen mode is entered or exited, you don't have to open the
guest's screen settings and change the resolution manually. Proper
useful!

## Guest additions and their problems

This feature works by means of the _guest additions_, extra software
that needs to be installed inside the guest and that provides tighter
integration with the hypervisor.

Since VirtualBox 6.0, it is possible to choose the type of emulated
graphics adapter:

* `VBoxVGA` is a legacy adapter that is recommended for older OSes;
* `VBoxSVGA` is recommended for modern Windows systems;
* `VMSVGA` is recommended for modern Linux systems.

Now, this is the theory. It looks like that any recent Linux system
should go with `VMSVGA`. However, I have encountered a number of issues
with that adapter, including:

* automatic screen resizing not working even when the guest additions
  are installed and exactly matching the version of the running
  hypervisor, if the additions come from prepackaged binaries of my
  distro. I needed to manually install them using the VirtualBox ISO to
  get them working;
* even after fixing the point above, I got poor 2D performance in
  everyday desktop activity, such as very slow window dragging, portions
  of the screen showing as solid black and, more importantly, frequent
  VM crashes.

However, if I ignore the recommendation and keep using the legacy
`VBoxVGA` adapter, things get better, much better. No crashes, black
areas and windows can be dragged at a decent speed. But there is a price
to pay: automatic screen resizing no longer works with Linux guests if
they are not using the `VMSVGA` adapter. So you can basically choose
between an unstable VM with working autoresize or a stable one without
it.

Luckily, we are _not_ forced to use `VMSVGA` to have working
screen resizing.

## Enter `mplugd`

Under a Linux VirtualBox machine with the guest additions installed,
every time we resize the guest window, the system can immediately detect
the new resolution. We can see that by calling `xrandr` after poking
with the window size. The system alone, however, will not take any
action when that happens. It is a VirtualBox additional component,
`VBoxClient`, which listens for window size changes and adapts the
screen to follow. As said above, this only works if using the `VMSVGA`
adapter.

However, since the window size can be read by any system tool, couldn't
we use a different tool to listen for resolution changes in place of
`VBoxClient` and then call `xrandr` to change the screen resolution on
the guest?

The answer is yes, and such a tool already exists: [mplugd][mplugd].  It
a generic event listener based on plugins, which matches events against
rules to execute when a certain thing happen. You can write rules such
as "when event X happens, execute script Y".

Since it already supports X events via a dedicated plugin, it can be put
into immediate use by telling it to adjust the screen resolution when a
screen change event happens.

_Note: `mplugd` is written in Python 2, which has been retired at the
beginning of 2020. Nevertheless, this utility is extremely useful and
still working, so until it is ported to Python 3 or something better
comes out, it is a good way to work around VirtualBox problems._

Let's see how we can install and configure it. The following sections
show how to do it on an [Arch Linux][archlinux] system, but the general
principles hold for any distribution.

## Installation and configuration

Under Arch Linux, `mplugd` is available via the AUR, so you can use your
favourite helper to install it, or do it manually. To handle X events, it
needs `python2-xlib`, which must be installed separately.
`python2-setuptools` are also needed:

    pacman -Syu python2-setuptools
    yay -Su mplugd-git python2-xlib 

Once installed, rule definitions can be placed globally under
`/etc/mplugd/action.d` or locally under `$HOME/.mplugd/action.d`. Since
we want screen resizing to work for every user, we go for the first
location.

    # Edit /etc/mplugd/action.d/vboxresizing.rules
    [rule vboxresizing]
    on_type=OutputChangeNotify
    true_exec=xrandr --output %event_name% --auto

We are asking `mplugd` to invoke `xrandr` every time a video output
changes. The name of the output to be acted upon (i.e. `VGA-1`) is
derived from the event and made available for substitution as
`%event_name%`.

Last, we must ensure that `mplugd` is started every time a user logs
in. Since the package doesn't come with a `systemd` unit, we will put a
global desktop entry for it under `/etc/xdg/autostart/`, so that every
user gets it for free:

    # Edit /etc/xdg/autostart/mplugd.desktop
    [Desktop Entry]
    Name=mplugd
    NoDisplay=True
    Exec=/usr/bin/mplugd

Starting from the next login, the guest screen should automatically
resize, even when using the `VBoxVGA` adapter.

<!-- Links --------------------------------------------------------- -->

[virtualbox]: https://www.virtualbox.org/
[mplugd]: https://github.com/anyc/mplugd
[archlinux]: https://www.archlinux.org/

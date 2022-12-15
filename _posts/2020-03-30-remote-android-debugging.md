---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan :
title: Remote Android debugging
category: android
---

When debugging or testing an Android application, the most common ways
to get access to a running Android environment are to:

* attach a physical device to the local system via a USB cable;
* run the Android Emulator locally, after creating an AVD with the AVD
  Manager.

They are simple and supported out of the box. However, it may not always
be possible to employ them.

Consider this scenario: you need to debug an application on Android 10
in order to test how a recent API change affects your code. You don't
have a physical Android 10 device, so you resort to running the emulator
with the official system image.

However, the emulator is, to all effects, an hypervisor on its own,
creating a VM to run your Android system and taking advantage of
hardware features to speed up execution (i.e. Intel VT-x or AMD SVM,
which provide hardware-assisted virtualization and are required to run
x86 Android images on a PC).  As such, it does not coexist peacefully
with other VM solutions running on your machine at the same time and
trying to use virtualization extensions. If you are already running a VM
on your system using a product like VMWare Workstation or VirtualBox,
they will conflict with the Android emulator (which happens to be qemu
in disguise).

The good news is, you don't need to run the Android emulator on the same
system where you run your development environment. Android debug tools
(and, in particular, `adb`) connect to running emulator instances over a
TCP connection. Normally, `adb` will automatically detect any locally
running emulator and present it as a devices when typing `adb devices
-l`. However, it can also be instructed to connect to a remote machine
where an emulator is listening. After the connection, the remote
emulator will work exactly like a local one.

If you can dedicate a second machine to running the emulator (with no
other hypervisors running at the same time) this can be a good solution
to get around the problem. Let's see how remote debugging can be set up.

## Setting up the machines

For this samples setup, we'll use two machines:

* `dev.local` is where we'll run Android Studio and where the code for
  the app to be debugged or tested resides;
* `emu.local` is where the emulator runs. Both Windows and Linux are
  considered.

To establish the connection between `adb` and the emulator, we will need
an open TCP port on `emu.local`. This can be any port, but in the
following I'll use `45555`. By default, the first (or only) Android
emulator listens on port `5555` for incoming connections, so `45555` is
easy to remember.

Android Studio and the SDK should be installed on both systems, although
they will be used asymmetrically:

* on `dev.local` we'll use Studio to run instrumented tests and do the
  debug, so our code repositories will also reside here;
* on `emu.local` we'll just create and run the AVD for our emulator: no
  code resides here.

It should be noted that the emulator on `emu.local` expects to receive
inputs from the local mouse and keyboard.  So if you need to type a
value or click a button, you need to be in front of `emu.local`.  Of
course, a remote desktop connection would work just as well. It all
depends on the relative positions of the two systems.

### Setting up `emu.local`

Let's prepare the emulator machine first. I assume that you have already
installed Studio and the SDK. So the first step is to create an AVD that
suits your needs. When ready, run it.

Emulators start with debug settings enabled, so they are ready to accept
connections from `adb`.  However, there is a catch: they only listen on
the loopback interface. They assume that connections will be coming from
a local `adb` instance connecting to `localhost`, but this is not the
case. We want the emulator to be accessible from an external network
interface and to expose its services on the port we have chosen in the
previous section, that is, `45555`.

Now, there are essentially two ways to accomplish this:

* we can configure a DNAT rule that redirects all incoming TCP traffic
  targeting port `45555` on any local network interface, sending it to
  `localhost:5555`. This is simple to do under Linux with `iptables` and
  some tweaking with `sysctl` to enable forwarding to the local machine;
* we can alternatively employ a userspace connection forwarder that
  proxies all connections from a certain local host and port combination
  to another.  It will then receive all connections to port `45555` for
  external IP's and forward them to `localhost:5555`.

We'll go with the userspace tool, as I think that messing with
`iptables` for such a scenario is overkill, not to mention that it
requires root privileges.

#### On Linux

If the emulator will be running on a Linux system, we can employ
[socat][socat], a versatile network tool that can be used as a TCP
forwarder, among many other things.

Install it on your system. This will depend on the running distro:

    # On Ubuntu
    sudo apt-get install socat

    # On Fedora (and other Red Hat with dnf)
    sudo dnf install socat

    # On Arch Linux
    sudo pacman -S socat

    # On OpenSUSE
    sudo zypper install socat

Once installed, and provided the emulator is running: we can start
forwarding connection with:

    socat tcp4-listen:45555,reuseaddr,fork tcp4-connect:localhost:5555

This command will accept TCP connections (over IPv4 only) on port
`45555` and forward them to port `5555` on `localhost`, were the
emulator is listening.

Note the `fork` option on the listening port: without it, `socat` would
exit as soon as the first incoming connection is closed. If `adb`
disconnects and then tries to reconnect, it will no longer be able to do
so because `socat` has terminated. This option ensures that `socat` will
keep running in face of multiple reconnections.

By default, `socat` listens on all interfaces, so the emulator is now
reachable from any external IP of the machine.

#### On Windows

On Windows systems, we can use a little nice utility called
[DoorPointer][doorpointer].

It is very simple to use: just download the ZIP archive and extract it
somewhere. It requires no installation. Before starting, DoorPointer
must be told which ports to forward and where, just as we did for
`socat`. Such information reside into a file called `nat.ini` alongside
the executable `DoorPointer.exe`. Edit `nat.ini`, remove the sample
configuration and then add the following line as its only contents:

    45555, localhost, 5555

The format is simple: your specify the port DoorPointer should listen
on, followed by the host the connection is forwarded to, and the target
port. Fields are separated by commas.

Now close the configuration file and launch `DoorPointer.exe`. No fancy
interface will pop up. In fact, the only sign of the tool being active
is an icon in the tray bar: ![DoorPointer Tray
Icon][doorpointer-tray-icon]. Right clicking it will allow you to stop
DoorPointer by choosing `Exit` from the menu.  _For the attentive
reader, I took the screenshot from a Linux system, with DoorPointer
running under Wine :)_

That's it, just remember to start DoorPointer after the emulator is
ready. Just like `socat`, it will listen on all active interfaces.

### On `dev.local`

Setting up `dev.local` is much easier, since Android Studio and the SDK
are all we need to connect to out shiny new remote emulator.

Fire up a terminal (the one embedded in Studio is just fine) and type
the following (assuming that `adb` is in your `PATH`):

    adb connect emu.local:45555

Of course, if your system is not really named `emu.local`, you'll need
to adjust the command as appropriate.

Now, if everything is working fine, `adb` should tell us it connected
successfully. From now on, all commands that could be directed to a
local emulator can be used on the remote one too. You can copy files,
access the shell and see it in devices listings. But more importantly,
Android Studio can run instrumented tests and debug application on the
remote emulator.

## Additional info

### Can't the Android emulator really coexist with other VM's?

On Windows, the Android Emulator is backed by the _Intel Hardware
Accelerated Execution Manager_ (_Intel HAXM_). Starting from a certain
release, HAXM can run concurrently with other hypervisors.

I have tested it with VirtualBox and have been able to run the emulator
concurrently with my Studio environment hosted under VirtualBox.
However, I have experienced inexplicable test suite failures when
running under this configuration, which never happened when using just
one hypervisor at a time per machine. So I do not currently recommend
this method for any serious development.

### Can I run the Android emulator under a VM?

Running a VM inside a VM is called _nested virtualization_, and its
availability depends on the hypervisor you are using and your CPU's
virtualization extensions.  Hyper-V and VMWare Workstation have good
support for this feature on Intel hardware.  VirtualBox added nested
virtualization support for Intel hardware in version 6.1 and for AMD
hardware in version 6.0.

I have been able to run the emulator nested under either Hyper-V or
VMWare Workstation. Under VirtualBox, it starts but then it simply shows
a black screen, probably because of some issues with GPU 3D
acceleration.

<!-- Links --------------------------------------------------------- -->

[socat]: http://www.dest-unreach.org/socat/
[doorpointer]: https://sourceforge.net/projects/doorpointer/
[doorpointer-tray-icon]: {{ "/assets/my/img/doorpointer.png" | relative_url }}

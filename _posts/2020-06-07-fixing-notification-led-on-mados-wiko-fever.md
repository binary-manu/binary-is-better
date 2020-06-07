---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan :
title: Fixing the notification LED not working on the Wiko Fever 4G running madOS 8.1
category: android
---

# {{ page.title }}

I own a Wiko Fever 4G, and Android phone employing the Mediatek MT6753
SoC, which shipped with Android 6.0. Recently, I decided to pimp it by
installing [madOS][mados], a custom ROM based on AOSP 8.1 supporting
specifically that SoC.

The project dates back to 2018 and seems now dormant, but this ROM is
very good and useful to people like me who don't want to throw away a
working phone because the stock system is outdated.

The only problem I had with this ROM, which was also mentioned by a user
in the linked thread and never fixed, is that the LED does not blink
when notifications are displayed. It only lights up when the battery is
charging.

I did my own investigations and found that there is a bug which breaks
LED blinking. That is, you can set any LED to be on or off, but the
moment you ask it to blink it will simply go off.

LED's are controlled by a set of files found under
`/sys/class/leds/$COLOR/`, where `$COLOR` can be `green`, `red` or any
other color your phone supports. My model only has green and red.

Each LED has files like `brightness`, `delay_on`, `delay_off` and
`trigger` which control the LED brightness, if it should blink or
persist an which events should cause it to blink.

Now, to have a LED blink, you should set `delay_off` to the number of
milliseconds the LED should stay off, and `delay_on` to the number of
milliseconds the LED should stay on. Setting both to 500 would cause
half-second blinking.

What actually happens is that, every time one of the `delay_*` files is
written, the other one is reset to 0. This will cause the LED not to
blink, and it will either stay on or off depending on which file is
written last. In my case, the library code controlling the LED's writes
`delay_off` last, which causes the delay be set to _"on for 0ms, then
off for XXXms"_. This clearly means the LED does _not_ have an on
period, so it stays off.

Luckily, the system allows disabling blinking for notifications. One can
go under `Settings -> Apps & Notifications -> Notifications ->
Notification light` then, under the `General` heading, uncheck `Blink
light`.

From this moment on, notifications will trigger a persistent LED. Be
sure to choose the green LED for this, as red is already used for the
battery, so that if a notification arrives when the phone is charging,
you can still spot it.

<!-- Links -->
[mados]: https://forum.xda-developers.com/android/development/rom-official-mados-wiko-fever-clones-t3762800

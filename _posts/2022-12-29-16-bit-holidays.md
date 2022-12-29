---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan spelllang=en:
title: 16-bit holidays!
category: Development
---

What could be better to spice up your winter holidays than some 16 bit
x86 assembly? As an exercise for removing the rust from my assembly-fu,
I wrote a small Base64 decoder purely in 8086 assembly code:

* it decodes a well-encoded message 4 bytes at at time and prints 3
  characters to the screen;
* handles padding `=`s;
* it does not handle faulty encodings;
* should use opcodes from the original 8086 only (unless I got it
  wrong);
* real mode code, meant to be embedded into a Master Boot Record;
* video output is done using the BIOS via `int 10h`.

## How to assemble

You'll need the [Flat Assembler (`fasm`)][fasm] to assemble the program.
With that installed, just run:

```bash
fasm base64.s
```

to get `base64.bin` as output. The file is already formatted to look
like a valid MBR: it's 512 bytes long and ends with `55 AA`, so it can
be run directly using an emulator like `bochs` or `qemu`.

## How to run

Once compiled, the simplest way to try it out is to have `qemu` run it
as if it was a floppy image. It is obviously too small to be a full
floppy, but `qemu` does not complain and we do no try to read additional
sectors:

```bash
qemu-system-x86_64 -fda base64.bin
```

What does it print? Well, why don't you try it for yourself? But if you
are in a hurry, there is a picture of it at the end of the page.

Of course, you can change the message and rebuild.

## The code

```nasm
{% include my/base64.s %}
```

## Sample output

![Output][output]


[fasm]: https://flatassembler.net/
[output]: {{ "/assets/my/img/base64.png" | relative_url }}

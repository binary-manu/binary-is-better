---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan :
title:  "ELF link-time symbol resolution"
categories: ELF
---
# ELF link-time symbol resolution

After having examined the linker [behaviour when using static
libraries][elf-ar-post], it is necessary to understand the symbol
resolution process. This is the process the linker applies at link-time
when it needs to sort out symbol definitions from multiple object files
(relocatable, either extracted from archives or not, and shared
objects). This is the process that allows, for example, for an undefined
symbol reference to be bound to a definition, or that makes defined
symbols take precedence over tentative ones.

Again, [Oracle's Linker Guide][oracle-linker] outlines the process. I
add some tests with GNU `ld` to check out what happens in specific
cases, especially those which involve weak or tentative symbols.

An important thing needs to be mentioned: all files have been compiled
as position independent code. This was done in order to avoid
complexities like copy relocations, which are needed for absolute code.

## Relocatable files only

The basic scenario we are talking about is given by a command like this:

    ld -o a.out first.o second.o

with both `first.o` and `second.o` providing a symbol with the same name
(either undefined, tentative or defined).

At its core, symbol resolution takes two symbols with the same name and
tries to decide what to do with them, therefore resolution does not
apply the first time a symbol is seen. Instead, the symbol is simply
added to the linker's internal symbol table. After that, whenever a
symbol is met, and there is already an homonymous symbol within the
table, resolution is performed between the symbol in the table and the
symbol just seen.

Let me define a symbol that is _not undefined_ by meaning it is either
tentative or defined. This way, the ambiguity of the expression "defined
symbol" which may or may not include tentative symbols, is eliminated.

Referring to the link command above, a symbol will first be seen when
processing `first.o`, so it enters the symbol table without resolution.
Then, when `second.o` is processed, resolution can start.

This is what happens:

* if one symbol is undefined and the other is not undefined, the not
  undefined symbol ends up in the symbol table, irrespective of their
  bindings (i.e. a not undefined weak symbol will override a global
  undefined one). The selected symbol brings in all its attributes,
  including its binding;
* if both symbols are undefined and have different bindings, the global
  reference takes precedence over the weak reference. This is
  reasonable: if at least one reference is global, then we need see a
  definition to satisfy it sooner or later, so we can ignore weak
  references and keep the global ones. If both references have the same
  binding, we can keep the one in the table as the new one does not
  contribute information;
* if both symbols are not undefined:
  * if both symbols are weak, keep the one already in the table;
  * if either symbol is weak and the other is global, the global symbol
    is retained;
  * if both symbols are global:
    * if both are defined, a duplicate symbol error is triggered;
    * if one is defined and the other is tentative, the defined symbol
      is retained;
    * if both are tentative, the symbol with the largest size is
      retained.

## With shared objects

If shared objects enter the mix, our scenario changes a little bit, with
our linking command becoming:

    ld -o a.out first.o libone.so libtwo.so

so that resolution may take places between either:

* a symbol from a relocatable file and a symbol from a DSO;
* two symbols from two different DSO's.

After symbols have been resolved, we know which symbol to use and if the
chosen definition comes from a relocatable file or from a DSO. We must
also keep track of which files referenced which symbols. This is
important, because it impacts how the symbol is integrated within the
final object file:

* if a symbol is only referenced from DSO's and not from any relocatable
  file, there will be no reference to that symbol in the output object
  file. This is reasonable, as there is no direct dependency from the
  output object file to the DSO that provides that symbol;
* if the symbol is provided by a relocatable file, its definition will
  be physically incorporated into the final object file;
* if the symbol is referenced from a relocatable file and provided by a
  DSO, it will _not_ be copied into the final object file (as this would
  make the use of a DSO meaningless). Instead, an undefined symbol
  reference is placed into the output, plus relocations for the dynamic
  linker to resolve at runtime. The binding of the resulting reference
  is the strongest among all references provided by the relocatable
  files: if at least one of them is global, the output reference will be
  global.

Given the above, the resolution process must build 3 sets of symbols:

* definitions, which may be either within relocatable files or DSO's;
* references from relocatable files, which will generate references into
  the output file;
* references from DSO's, which do not contribute to the output file but
  still need to be resolved, otherwise at runtime we can expect the
  dynamic linker to be unable to resolve the reference to some symbol.

Now, let's see how symbols are resolved:

* if one symbol is undefined and the other is not undefined, the not
  undefined one is chosen;
* if both symbols are undefined and have different bindings, the global
  reference takes precedence over the weak reference. If both references
  have the same binding, we can keep the one in the table as the new one
  does not contribute information. As said above, the binding of
  references in DSO's have no impact on the binding of references
  generated in the output file;
* if both symbols are not undefined:
  * if both symbols are weak, the symbol from a relocatable file (or
    from the leftmost DSO) wins;
  * if they have different bindings, the one from the relocatable file
    (or from the leftmost DSO) wins;
  * if both symbols are global:
    * if they are both defined, the symbol from a relocatable file (or
      from the leftmost DSO) wins;
    * if one symbol is tentative file and the other is defined, the
      defined symbol wins if the tentative symbol is from a relocatable
      file; if both symbols come from DSO's, the symbol from the
      leftmost DSO wins;
    * if they are both tentative:
      * if one of them is from a relocatable file, they are merged and
        the resulting symbol is placed into the output file;
      * otherwise no symbol is emitted in the output file and the symbol
        from the leftmost DSO wins.

[elf-ar-post]: {{ site.baseurl }}/{% post_url 2020-01-13-rules-for-object-file-extraction-from-elf-archives %}
[oracle-linker]: https://docs.oracle.com/cd/E19253-01/817-1984/chapter2-93321/index.html

---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan :
title: Linux account and password lifecycle
category: Linux
---

# {{ page.title }}

User account creation and maintenance is a typical routine task for
\*NIX system administrators. Yet, this topic can sometimes be confusing
because account information is scattered across a number of files, and
each file stores multiple information fields whose meaning and relations
to one another may not be so obvious, especially when it comes to the
lifecycle of the account and its related password. Let's have a look at
the most important files that store account information and, in
particular, the meaning of information that impact the lifecycle of
passwords and accounts.

## Account data storage

In order to keep track of users on a system, each user gets its own
_account_. Each account stores a plethora of information that is used by
different tools to authenticate users and appropriately setup the
environment after login.

On Linux, the system stores the following data for each account:

* _username_: the human-readable identifier used to refer to this
  specific user, which is typically typed at login time. For example,
  `johndoe`;
* _password and password-aging data_: each account has a password, which
  may be used for authentication at login time. Depending on how you are
  logging in the password may or may not be required (i.e.  public key
  authentication with SSH does not use it). The password also comes with
  some related data that track its _aging_: the last time it was
  changed, how much time can elapse before a change is enforced and so
  on;
* _user environment information_: the home directory of the user and
  their login shell;
* _user ID's_, their _user ID (UID)_ and primary _group ID (GID)_;
* _user full name_, often called a _comment_;
* _account expiration date_, an specific date after which the account
  can no longer be used. As we will see, this information is independent
  from _password-aging data_, altough they are othen used together in
  security checks;
* _supplementary group memberships_, the list of groups, in addition to
  the primary one identified by the _GID_, to which the user belongs;
* _group passwords_: groups can have a password, which is used by some
  tools to allow gaining temporary membership if you are not a membner
  yet.

As can be guessed from the list, some bits of information are likely to
be much more sensitive than others. For example, username and comment
are likely public information, while the password must be protected from
prying eyes. For these reason, modern systems use two different files to
store them. Also, group information is handled separately to better cope
with its one-to-many nature:

* `/etc/passwd` stores non-sensitive non-group information, such as
  usernames, UID's, comments and the like. While the file is only
  writable by root for administrative purpouses, anyone can read it, in
  order to get basic information about users. For example to get the
  full, real name of user _janedoe_, you would look up this file for the
  username and get the comment field.
* `/etc/shadow` stores sensitive non-group information, which means that
  all password related stuff go there. Unlike `/etc/passwd`, reading
  this file is off-limits for regular users;
* `/etc/group` stores non-sensitive group information, such as group
  names, GID's and membership information. While the file is only
  writable by root for administrative purpouses, anyone can read it, in
  order to discover group memberships for a user;
* `/etc/gshadow` stores sensitive group information: group passwords go
  here.

### /etc/fstab

The structure of `/etc/fstab` is simple: every line corresponds to a
different account and is composed of exactly 7 fields, separated by a
colon (`:`). This is excerpt from my system:

    root:x:0:0:root:/root:/bin/bash
    manu:x:1000:100:Manu:/home/manu:/bin/bash
    [...]

The first line described the account for the super user, the second one
maps to my primary user account. The fields are defined as follows:

1. the _username_;
2. the _password_ (more on this below);
3. the numeric _User ID (UID)_ the system uses to internally track this
   user and its resources (processes, files, ...);
4. the numeric _Group ID (GID)_ of the primary group this user belongs
   to;
5. the _comment field_: provides basic information about the user, such
   as its full name or its office location. It is formatted according to
   the [GECOS][gecos] field definition, which is why it is often called
   the GECOS field;
6. the user's _home directory_;   
7. the user's _login shell_, the program that should be invoked to
   handle commands just after the login completes.

There is one important thing to note: we just asserted that this file is
world-readable and should not contain passwords and other sensitive
information, yet the second field is called _password_… what is going
on?

In early versions of UNIX this file used to also store passwords. Of
course, password were not stored as cleartext, but as salted hashes,
which means that instead of your plain password you would see a longer
and apparently meaningless sequences of letters, digits and other
symbols.  Such a sequence is derived from your password using a one-way
cryptographic function, so that it is very easy to calculate the hash
given the password, but is (theoretically) very hard to recover the
password from the hash. This way, the system would ask for your
cleartext password at login time, calculate the hash, then compare what
it calculated with the contents of the _password_ field. If they
matched, login would be allowed.

Conversely, if a malicious user tried to impersonate you, simply
knmowing the hash of your password is useless, because it cannot be
directly typed at password prompts: the system would treat it as a plain
password and hash it again, producing a different result.

However, as technology progressed, attacks against this scheme have
become more sofisticated and feasible. Therefore, it was decided to
store password in a different file, readable only by the superuser.
Passwords are still stored as hashes, since it offers greater protection
in case the contents are leaked somehow.

When password were moved, the corresponding field was retained in order
to avoid shifting the other fields. Nowadays, it is common to see an `x`
inside it, which simply means that the password should be looked up in
`/etc/shadow`.

### `/etc/shadow`

This file is were sensitive information are stored. Here is an excerpt
(the file comes from a Vagrant machine, so the plaintext passwords for
both `root` and `vagrant` users are `vagrant`, no secret here 🙂):

    root:$1$m.FEVNiS$OYiaRNHMHzS85/wnDHccI.::0:99999:7:::
    vagrant:$1$gPNBpA.5$5pr.KtXhOx6S/Hc69TUZZ.::0:99999:7:::

Each line contains 9 fields:

1. the _username_;
2. the _hashed password_;
3. the _date of the most recent password change_. This field is
   automatically updated every time the password is changed with
   `passwd`;
4. the _minimum password age_, which is the number of days that must
   elapse after a password change before it can be changed again;
5. the _maximum password age_, which is the number of days after which
   the password must be changed. this value is relative to the contents
   of field #2: summing them together gives you get the _password
   expiration date_;
6. the _password warning period_, the number of days immediately
   preceding the _password expiration date_ during which the system will
   remind the user that the password is going to expire;
7. the _password inactivity period_, the number of days immediately
   after the _password expiration date_ during which the password will
   still allow logins, but the system will force a password change
   before giving you the prompt. Failing to change the password will
   abort the login;
8. the _account expiration date_: past this date, the account is
   considered expired and cannot be used for logging in under any
   circumstance, even if your login method would not rely on the accoun
   tpassword, as for SSH public key authentication;
9. this field is unused and usually empty.

It is important to note that, while fields #3 and #8 are _dates_
(absolute time points, like 01/01/2000), fields #4, #5, #6, #7 are
expressed as _day counts_ (i.e.  `7` means seven days) and as such are
relative to some other date.

Fields #3 and #8 are expressed as the number of days elapsed since the
UNIX epoch (midnight of January 1st, 1970 UTC); `0` means the Epoch, `1`
means one day past the Epoch (January 2nd) and so on.

To compute this value for the current system time, we may type:

```sh
echo $(( $(date +%s) / (3600 * 24) ))
```

First, we ask for the current time expressed as seconds elapsed since
the epoch, then divide by the number of seconds in a day (`24 * 3600`).

To view such a date in a more readable form, we can use

```sh
date -I -ud @$(( <date> * 3600 * 24))
```

This converts the days back to seconds and then asks `date` to spit out
the equivalent broken down UTC date in ISO 8601 format. Some system
tools such as `chage` and `passwd -S` do this conversion for us when
querying system account, so this snippet is only useful to convert a
value that does not already reside in `/etc/shadow`.

### /etc/group

This file tracks group membership, storing the list of members for each
group:

    manu:x:1006:manu
    wheel:x:10:root,manu
    […]

Every line define a single group and is composed of the following 4
field:

1. the _group name_;
2. the _group password_;
3. the _group ID (GID)_ of the group;
4. a comma-separated list of usernames of _group members_.

Just like `/etc/passwd`, the _group password_ field is actually unused
and filled with an `x` since the real password, if any, resides in
`/etc/gshadow`.

### /etc/gshadow

`/etc/gshadow` contains almost the same information as `/etc/group` with
two major differences:

* password are actually present as salted hashes;
* it adds a list of administrator members. We'll see this in a moment.

The contents would look like this:

    wheel:::root,manu
    manu:::manu
    […]

Each line is again composed of 4 fields:

1. the _group name_;
2. the _group password_;
3. a comma-separated list of usernames of _group administrators_;
4. a comma-separated list of usernames of _group members_.

This time, field #2 contains the real hashed password. Field #4 should
always be synced with field #4 of `/etc/group` and list all members.

Filed #3 is new: it defines group administrators. These users are group
members which have the ability to add or remove other members from the
group or change the group password, without being root and without
knowing the password.

Group passwords are used by some tools (for instance, `newgrp`) to gain
temporary membership of the group without being listed in `/etc/group`
or `/etc/gshadow` as a member. What `newgrp` does is spawning a new
shell whose real and effetive group ID's (RGID and EGID) are set to the
chosen group rather than to the primary group of the user as listed in
`/etc/passwd`.  If the calling user is alredy a member of the chosen
group, no password is asked. If it is not, the group password must be
entered. A passwordless group cannot be entered via `newgrp`.

As an example, let's see how the RGID and EGID of the current shell
change after a call to `newgrp`:

```sh
# I just logged in so my group ID's are set to my primary group
$ ps -o pid,ppid,euid,ruid,egid,rgid -p $$
    PID    PPID  EUID  RUID  EGID  RGID
  19905   13862  1000  1000   100   100
# Now let's enter a group I'm a member of
$ newgrp audio
# The group ID's are now different. Also, the shell has a different
# PID since it's a new process, and the old shell is its parent.
$ ps -o pid,ppid,euid,ruid,egid,rgid -p $$
    PID    PPID  EUID  RUID  EGID  RGID
  24111   19905  1000  1000    92    92
```

Note that group passwords have no aging information and as such cannot
expire. Since they are rarely used, this is not a concern. 

## Lifecycles

The next thing we must discuss are the lifecycles of passwords and
the accounts; that is, the time frames during which they are usable for
login or not.

Both the password and the account have their own lifecycles, and the two
are not necessarily identical. This means we may have an active account
with an expired password or, conversely, an expired account whose
password would still be valid given its aging information. Of course,
since the two concepts are strongly related, there must be some kind of
relationship between the two, whose ultimate goal is to determine if we
can login with that account or not.

### Account lifecycles

Let's talk about the account lifecycle first. Each account can be in
just one of two states: it can be either _active_ or _expired_. An
active account can be used to log in into the system, provided the
authentication method we are going to use is usable and that we pass the
authentication challenge. Conversely, an expired account cannot be used
for logging in, irrespective of how we would authenticate ourselves. No
matter if we try to log in using the account password, an SSH private
key or some other method. If the account is expired, it is not good for
that.

There is a single parameter which controls the expiration of an account:
the _account expiration date_ stored in `/etc/shadow` in the 8th field.
If the system time is before this date, the account is active, otherwise
it's expired. It's that simple.

Account expiration is optional: if a date is not provided, the
corresponding field will be empty and the account will never expire.
This is the usual condition for accounts. It makes sense to set an
expiration date for accounts which are bound to be temrinated unless
some manual process is enacted.  For example, an external contractor may
have its account bound to expire when its contract expires.

The expiration date can only be changed by the administrator. Updating
it to represent some point in the future effectively extends the
lifetime of an account. If it was expired, it will be active again.
Conversely, settings it to a value in the past (i.e. `1`) will
immediately expire the account.

`usermod -e` can set the expiration date of an account:

```sh
# Set my account to expire at the end of 2020.
# The date is in ISO 8601 format, but other variations are
# accepted (i.e. 'today' and 'tomorrow' work).
usermod -e 2020-12-31 $USER
```

### Password lifecycles

Password lifecycles are more complex. First, a password can be
in one of several states, which impact the availability of the password
for login purpouses. Second, a password will go through multiple
state changes during its lifetime, for example it may be usable,
then expire, then be usable again after the user has changed it, then
expire again, and so on.  Of course, if the corresponding account is expired,
we already now we won't be able to login.

Password state is determined by multiple attributes, but ultimately we
can split them in two logical groups:

* the _password age_, as defined by `/etc/shadow` fields #3 to #7: age
  is used to enforce a change when a password has been in use for too
  long and can make it expire after a set amount of time;
* the _passowrd field_ as stored in `/etc/shadow`, field #2. Normally,
  it will consiste of the output of a password hashing algorithm, but it
  can also be set to special values (more below) which can inhibit its
  usability.

Both groups contribute to deciding if the password can be used to login.
If aging data says that the password is expired, for example, we will
not be able to use it regardless of its value. But even if the password
is OK according to aging information, we may still be unable to use it:
for example, it may be locked.

#### Password field states

At any given time, the _password field_ may be in one of 4 forms:

* it can be _empty_;
* it can be _usable_;
* it can be _locked_;
* it can be _unusable_.

First, an account can have an empty password. While this is clearly not
optimal from the point of view of system security, it can be allowed,
depending on the system configuration. It is easy to spot such accounts
because the _password field_ will be empty.  In such cases, when logging
in the system will not even ask for a password, we will get to the shell
as soon as we enter the username.  This is what we would see in
`/etc/shadow`:

    test::18518::::::

We can use `passwd -S $USERNAME` to ask the system for the status of the
password for a specific user. In this case, we get:

    test NP 2020-09-13 -1 -1 -1 -1 (Empty password.)

Remember that some tools or libraries may be configured to reject
accounts with empty password. For example, SSH can be configured to
disallow logins if an account has no password (`PermitEmptyPasswords`
option). The Linux-PAM `pam_unix.so` module has a similar option
(`nullok`). If you really want to use passwordless accounts…

<div style="margin: 0 0 1em 0;">
<div class="tenor-gif-embed" data-postid="13199396"
data-share-method="host" data-width="30%"
data-aspect-ratio="1.78494623655914">
  <a
    href="https://tenor.com/view/why-huh-but-why-gif-13199396">Why Huh
    GIF</a> from <a href="https://tenor.com/search/why-gifs">Why
    GIFs
  </a>
</div>
<script type="text/javascript" async src="https://tenor.com/embed.js"></script>
</div>

…be sure to check that services using it work as intended.

Then, an account may have a usable, valid password. This is the usual
condition for user accounts. The _password field_ will store the hashed
password. The exact representation of the hash depends on the hashing
method and more can be read in [crypt(5)][crypt]. `/etc/shadow`
contains, for example:

    test:$1$ixE/9ivM$.BgDclGsEvrE/Uqd8TS9C1:18518::::::

and `passwd -S` reports:

    test PS 2020-09-13 -1 -1 -1 -1 (Password set, MD5 crypt.)

The password was hashed with the `md5crypt` algorithm, as indicated by
the password starting with `$1$`. We can login with the `test` user by
typing the plaintext password.

Passwords can be locked. What this means is that the password is marked
as unacceptable for login, while it original value is preserved.  This
way, when it gets unlocked, it will hold the same value it had before.

Password locking and unlocking can be performed using `passwd -l` and
`passwd -u`. What these tools actually do to mark the password as locked
is to add an exclamation mark (`!`) at the beginning of the _password
field_.  The rest of the field contains the original hash.  Predictably,
unlocking merely removes the leading `!`.

Adding the `!` at the beginning is simply a convention. What actually
makes the password locked is that no valid password hashing algorithm
will ever produce something starting with `!`. Therefore, no matter what
you type at login prompts, including the correct password, the
calculated hash will never match the _password field_. Any other way of
producing an impossible hash from which the original can be recovered
would work, but the use of `!` is historical, simple and effective.

Password locking can be used to temporarily freeze logins for unused
accounts, for example for a contractor whose contract is being renowned.
We don't delete its account, we simply put it on hold.  This is how a
locked password looks like:

    test:!$1$ixE/9ivM$.BgDclGsEvrE/Uqd8TS9C1:18518::::::

and `passwd -S` reports:

    test LK 2020-09-13 -1 -1 -1 -1 (Password locked.)

Remember that locking applies to the _password_, not to the account.
Depending on your system configuration and the tools handling the login,
you may still be able to login with the associated account.

Finally, we can give an account an unusable password: in this case,the
_password field_ will contain an impossible hash, just like a locked
password. The only difference is that such field will not follow the
convention for locked passwords: the system will report it as present,
not as locked.  However, any attempt to use it will fail.  A common use
for this is for accounts which use alternate authentication schemes
exclusively, like SSH keys.  If we alredy know an account will only be
use by an automated remote system to connect and that it will use an RSA
key, there is no point in also setting a password, which may be used by
an attacker to compromise the system.

A very common way of setting an unusable password is to set the
_password field_ to a single asterisk (`*`):

    test:*:18518::::::

and `passwd -S` reports:

    test LK 2020-09-13 -1 -1 -1 -1 (Alternate authentication scheme in use.)

This convention is widespread enough that `passwd -S` recognizes it as a
special convention and reports that an alternate authentication scheme
will be used to login.

The advantage of this scheme with respect to locked passwords is that it
does not look like it's locked. This may be useful if some login program
insists on your account having as unlocked password even if it is not
going to use it. An unusable password looks valid, but no one will ever
be able to use it, attackers included.

#### Password aging

Password aging information track the last time the password was changed,
and can be used to enforce some limits or mandatory behaviours about
password maintenance over time.

Since various fields are involved in defining password aging, the
following picture tries to summarize them. Account expiration is also
included.

![Password aging information on a timeline][pw_aging]

First, the system tracks the date of the most recent password change.
Various time frames are then defined as offsets from this moment, given
as day counts.

First, it is possible to define an optional _minimum password age_. This
field gives the number of days during which a password change cannot
happen. Foe example, after a user changes its password, it may be force
to keep it for 7 days before it can be changed again. Often, this
feature is not used and passwords can be changed at will at any moment.

Symmetrically, the is also a _maximum password age_. This is a number of
days that, when summed to the latest password change date, gives us the
_password expiration date_. After this date, the password will be
expired.  The exact behaviour of trying to login with an expired
password depends on both this field and on the _password inactivity
period_, so we'll talk about this in a moment.  This field is also
optional and not setting it means that the password will never expire
and thus will never need to be changed (altough the user is still free
to change it, if they so desire).

For user convenience, it is possible to define a _password warning
period_. This is the number of days immediately preceding the password
expiration date during which the system will warn users logging in that
the password should be changed. For example, this is what a CentOS 7
system would show:

![Password expiration warning message][pw_warning]

Again, this field is optional and if not specified, or set to 0, there
will be no warning.

Things get more interesting when considering the _password inactivity
period_, because it defined what happens when a password that has
exceeded its expiration date is used to login. Basically, depending on
how we set it, 3 different behaviours can be obtained:

* _forced change_: the expired password is still accepted, but before
  the login can complete the system will force the user to set a new
  password. There is no time limit during which the password must be
  changed, so there is no problem if a login happens months or years
  after the password has expired. We just need to change it and we are
  good to go. This is what happens if the _password inactivity period_
  is not set;
* _time-limited forced change_: this case is just like the previous
  bullet, but there is a time limit during which we can change the
  password: we must do it before _password inactivity period_ days has
  elapsed since the password expiration date. After that period, the old
  password will no longer be accepted and it will not be possible to
  change it at login time. The only way to set a new password is to
  contact the administrator and have her set a new password for us. This
  is the behavior we get by setting the inactivity period to a positive
  value;
* _forbidden login_: the old password is no longer accepted as soon as
  it expires, there is no forced-change period. Therefore, you must take
  care to not let it reach its expiration date. This is the behaviour
  caused by a zero inactivity period.

Always remember that, with the exception of the date of last change, all
other fields are relative. So, everytime the password is changed and the
date of last change is updated, the various time frames start all over
again.

## A note about PAM

On the system, various applications need to verify the identity of a
user and the validiity of its associated account. The `login` program
that lets us grab a virtual terminal is just one of them. `ssh`, `su`,
`sudo` all need to do the smae thing.

Instead of coding password and account verification functionalities
inside every single app, the modern approach is to delegate such checks
to a single external component, which does its own checking and returns
a green light/red light status to the application. On Linux, this goal
is fullfilled by [_Linux-PAM (Pluggable Authentication Modules)_][pam].

PAM is composed of a core library which exposes an API to authenticating
applications, and a series of modules that implement specific checks.
The advantages of such a system are manyfold:

* since PAM is a shared library used by many programs, updating it or
its module brings updates and fixes to all clients;
* the most disparate authentication schemes can be concocted as long as
the can be used viua the PAM API. Clients are oblivious of how checks
are done, they simply want to now if it is OK to proceed;
* PAM is driven by configuration files. Changing these files impacts
which checks, and in which order, are performed on a client-by-client
basis. It is possible to have different checks in place for console
logins with respect to `ssh` logins.

Since PAM is a large topic, I will not add much details here. I just
want to introduce the [`pam_unix.so`][pam_unix] module, because it the
one responsible for checks related to the contants of `/etc/passwd`,
`/etc/shadow` and the other files we mentioned.

`pam_unix.so` is usually included among standard system login checks.
Depending on your PAM configuration, it may or may not allow empty
passwords. It account-related checks verify that both the password and
the account are not expired: this is the reason why it is important to
have a non-expired password even if you plan to never use it.

A typical example is an account the is only accessed via `ssh` and
public key authentication. The password in `/etc/shadow` is not used in
this kind of authentication. However, `ssh` do asks PAM to perform
account validity checks, and the password age (but not its value) is
included. If the password is expired, PAM would return an error,
preventing `ssh` from logging in.

In this cases, it is better to configured the password to never expire,
then set it to an unusable digest such as `*`. As explained before, such
a digest will never match the output of `crypt` so it is impossible to
pass password validation. A the same time, this satisfies other checks
as the password is formally not empty and not locked.

<!-- Links -->

[passwd]: https://linux.die.net/man/5/passwd
[shadow]: https://linux.die.net/man/5/shadow
[gecos]: https://en.wikipedia.org/wiki/Gecos_field
[crypt]: https://linux.die.net/man/5/crypt
[pw_aging]: {{ site.baseurl }}/assets/img/pw_aging.png
[pw_warning]: {{ site.baseurl }}/assets/img/pw_warning.png
[pam]: http://www.linux-pam.org
[pam_unix]: http://linux-pam.org/Linux-PAM-html/sag-pam_unix.html



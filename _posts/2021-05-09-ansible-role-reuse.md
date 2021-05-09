---
# vi: set tw=72 et sw=2 sts=-1 autoindent fo=troqan spelllang=en:
title: Variable visibility and role reuse in Ansible
category: Ansible
---

# {{ page.title }}

In Ansible, we can create canned units of work through _roles_. Each
role contains tasks and their related files, templates, handlers and
variable definitions. Each role should be designed to perform a specific
job, like installing a web server or setting up routing tables.  They
are one of the basic forms of code reuse in Ansible.

To use a role, we add it to our plays so that it gets executed at the
proper time. Ansible provides 3 different methods to invoke a role from
a play:

* the `roles` play keyword: this is the traditional way of calling a
  role; each role is listed in the play in the order we want them to
  run. Ansible ensures that they are run after the `pre_tasks` but
  before the `tasks` for this play;
* the `import_role` task works much like `roles`, but being a task we
  can place it among other tasks. This allows us to reuse a role in
  between other tasks. Also, `import_role` is not subject to the
  limitations of `roles` regarding multiple executions of the same role,
  so calling it twice with the same arguments result in two calls in a
  row without special configurations (i.e. setting `allow_duplicates`);
* the `include_role` task is the dynamic version of `import_role`. Where
  `import_role` acts as if the callee role was effectively part of the
  play (which affects variable visibility as we'll see in a moment),
  `include_role` provides a higher degree of independence between the
  play and the role.

An important facet of role reuse regards variable visibility: if a role
is used in a play, its variables, as defined in its `defaults` and
`vars` files, can be made available to other parts of the play, and the
same is possible for variables defined for a specific role invocation
using the `vars` keyword. How this happens exactly depends on how the
role is called, using one of the methods described above.  This is a
point worth understanding because it can lead to surprising
consequences.

First, we'll have a look at the visibility of role variables defined in
`defaults` and `vars` files. After that, we'll explore visibility of
variables defined for individual role invocations.

All the following code snippets are fully runnable playbooks, and the
output has been produced with Ansible 2.10.

## Visibility of `vars` and `defaults`

### Importing roles statically

First, we analyze the case of static role imports. As mentioned above,
they are performed either using the `roles` play keyword or the
`include_role` task.  As far as this article is concerned, we'll see
that the two methods behave exactly the same.

When a role is imported statically, Ansible behaves as if all the
components of the role, its tasks, its variables and others, were
physically written inside the play itself. For example, if a play calls
on a role that defines a variable `foo` in its `defaults`:

```yaml
- name: I'm a play
  roles:
    # This role defines a variable 'foo` in its defaults
    - define_foo
```

Ansible treats it as if we had written:

```yaml
- name: I'm a play
  vars:
    foo: bar
  roles:
    - define_foo
```

The consequences of this design are far-reaching. If a variable is
defined at the play level, it is accessible from all the tasks and roles
called from that play. And this includes all tasks that would run
_before_ the one that defines the variable.

Consider the following example:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  pre_tasks:
    - debug:
        msg: "{{ foo }}"
  roles:
    - var
  tasks:
    - debug:
        msg: "{{ foo }}"
---
# ./roles/var/defaults/main.yaml
foo: "I'm 'foo' and I'm defined in 'var'"
```
{% endraw %}

The `var` role has only a `defaults` file. Being statically imported,
its variables are promoted to the play level. So, if we run it:

```
PLAY [Run the test] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [debug] *******************************************************************
ok: [localhost] => {
    "msg": "I'm 'foo' and I'm defined in 'var'"
}

TASK [debug] *******************************************************************
ok: [localhost] => {
    "msg": "I'm 'foo' and I'm defined in 'var'"
}

PLAY RECAP *********************************************************************
localhost                  : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0 
```

See how the `pre_tasks` can access the variable `foo` defined by role
`var`, even if `var` is meant to be executed _after_ the `pre_tasks`.
This can be surprising as there is no clue about the definition of that
variable when we reach the `pre_tasks`.

If we rewrite the example to use `import_role`, it behaves exactly the
same:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  pre_tasks:
    - debug:
        msg: "{{ foo }}"
  tasks:
    - import_role:
        name: var
    - debug:
        msg: "{{ foo }}"
---
# ./roles/var/defaults/main.yaml
foo: "I'm 'foo' and I'm defined in 'var'"
```
{% endraw %}

```
PLAY [Run the test] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [debug] *******************************************************************
ok: [localhost] => {
    "msg": "I'm 'foo' and I'm defined in 'var'"
}

TASK [debug] *******************************************************************
ok: [localhost] => {
    "msg": "I'm 'foo' and I'm defined in 'var'"
}

PLAY RECAP *********************************************************************
localhost                  : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

From now on, we'll only show example using `roles`, as the reader can
easily derive the equivalent version using `import_role`.

This is much what there is to say about static imports, as this behavior
cannot be tweaked in any way. Whenever you statically import a role, all
its variables can be accessed from any other task or role from the same
play, no matter their relative positioning.

<a name="name-chash"></a>

This can lead to unintended interactions. For example, suppose we call
a role which uses a variable `state` to decide which action it should
perform. If we do not specify a value, we would assume that the role
will receive no variable from outside and thus can fallback on a
default. This is a common pattern for many Ansible tasks:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  roles:
    - do_thing
    - role: do_another_thing
      vars:
        state: a nap
---
# ./roles/do_thing/tasks/main.yaml
- name: do_thing
  debug:
    msg: I'm going to do {{ state | default("nothing") }}
---
# ./roles/do_another_thing/tasks/main.yaml
- name: do_another_thing
  debug:
    msg: I'm going to do {{ state | default("a walk") }}
```
{% endraw %}

What we desire is, for the first role invocation, to have `do_thing`
called and perform its default action. After that, we call
`do_another_thing` with an explicit variable, to have it perform a
specific action. Therefore, the two tasks should do `nothing` and `a
nap`. However, what we get is:

```yaml
PLAY [Run the test] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [do_thing : do_thing] *****************************************************
ok: [localhost] => {
    "msg": "I'm going to do a nap"
}

TASK [do_another_thing : do_another_thing] *************************************
ok: [localhost] => {
    "msg": "I'm going to do a nap"
}

PLAY RECAP *********************************************************************
localhost                  : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

Without surprise, the `state` variable from the second role invocation
percolated up to the first one, subverting the intended semantics of the
call.

To put it differently, once you pass a variable to a statically imported
role invocation, that variable is also passed to all other invocations
of the same role. You can no longer count on any internal role defaults,
because play variables override them.

A simple solution to this kind of problem is to use prefixes in variable
names to isolate variable logically belonging to different roles. If
instead of `state` we used, for example, `do_thing_state` and
`do_another_thing_state` state, there would be no conflict between the two
role invocations. `do_thing` would still be able to access
`do_another_thing_state`, but it would simply not use it. And if it did,
it would be pretty easy to spot the mistake, since the variable prefix
does not belong to the role.

Unfortunately, this trick will not avoid name clashes between multiple
invocations of the _same_ role, because then prefixes would obviously
collide. We'll see a solution to this problem later.

### Importing roles dynamically

`include_role` behaves differently than `import_role`. Ansible performs
no pre-processing of this kind of role invocation and will not add
anything to the play. This behaves more like a real function call and
helps keeping things uncluttered.

By default, `defaults` and `vars` defined in a role that is called
dynamically will be unavailable to other roles or tasks in the same
play, no matter if they come before or after the include.

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  pre_tasks:
    - name: Before
      debug:
        msg: "{{ foo }}"
  tasks:
    - include_role:
        name: var
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/var/defaults/main.yaml
foo: "I'm 'foo' and I'm defined in 'var'"
```
{% endraw %}

Running this playbook produces the following error about `foo` being
undefined for the `Before` task. For readability, part of the error
message has been redacted:

```
PLAY [Run the test] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [Before] ******************************************************************
fatal: [localhost]: FAILED! => {"msg": "The task includes an option with
an undefined variable. The error was: 'foo' is undefined [REDACTED]

PLAY RECAP *********************************************************************
localhost                  : ok=1    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
```

If we want to be sure that `foo` is also unavailable to tasks following
the call, we can simply remove `Before` from the play:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  tasks:
    - include_role:
        name: var
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/var/defaults/main.yaml
foo: "I'm 'foo' and I'm defined in 'var'"
```
{% endraw %}

```
PLAY [Run the test] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [include_role : var] ******************************************************

TASK [After] *******************************************************************
fatal: [localhost]: FAILED! => {"msg": "The task includes an option with
an undefined variable. The error was: 'foo' is undefined [REDACTED]

PLAY RECAP *********************************************************************
localhost                  : ok=1    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0 
```

And again, the variable is undefined.

Unlike `import_role`, this behaviour can be tweaked: `include_role`
accepts a `public` boolean argument. It's default is `false` which
matches what we have just seen. Setting it to `true` makes `defaults`
and `vars` from the included role available to tasks coming _after_ the
`include_role`. This is safer than a static import, because we get to
read the task responsible for the definition of a variable before it can
be used. Also, the presence of `public` makes this explicit.

Let's review the previous example with a task before and one after the
include and check that, even with `public`, tasks coming before the
include cannot read role variables:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  pre_tasks:
    - name: Before
      debug:
        msg: "{{ foo }}"
  tasks:
    - include_role:
        name: var
        public: yes
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/var/defaults/main.yaml
foo: "I'm 'foo' and I'm defined in 'var'"
```
{% endraw %}

```
PLAY [Run the test] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [Before] ******************************************************************
fatal: [localhost]: FAILED! => {"msg": "The task includes an option with
an undefined variable. The error was: 'foo' is undefined [REDACTED]

PLAY RECAP *********************************************************************
localhost                  : ok=1    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
```

If we remove the `Before` task, everything works and `After` can access
the `foo` variable from the role:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  tasks:
    - include_role:
        name: var
        public: yes
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/var/defaults/main.yaml
foo: "I'm 'foo' and I'm defined in 'var'"
```
{% endraw %}

```
PLAY [Run the test] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [include_role : var] ******************************************************

TASK [After] *******************************************************************
ok: [localhost] => {
    "msg": "I'm 'foo' and I'm defined in 'var'"
}

PLAY RECAP *********************************************************************
localhost                  : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0  
```

## Visibility of task-level vars

At this point, we have clarified what happens to variables a role
defines via its `defaults` or `vars` files. But a role can also receive
variables from the caller via the role or tasks-level `vars` keyword.
This variables are meant to complement or override `defaults` and `vars`
from the role on a call-by-call basis.

The default Ansible behaviour for this variables is to give them the
same visibility as other role variables, which means that for static
imports they would be visible to tasks both before and after the import,
while for dynamic imports they follow the behaviour dictated by the
`public` attribute.

### Static imports

In the following examples, we'll use a `print` role which simply prints
a variable `foo` without defining it: it will be passed by the caller.
Let's see how this interacts with other tasks:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  pre_tasks:
    - debug:
        msg: "{{ foo }}"
  roles:
    - role: print
      vars:
        foo: "I'm the foo passed to print in vars"
  tasks:
    - debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
```
{% endraw %}

```
TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [debug] *******************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [print : Print 'foo'] *****************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [debug] *******************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0 
```

See how `foo` is made available to tasks before and after the role, just
as if it were defined in a `vars` file.

According to [variable precedence rules][precedence], task vars override
both play vars and role defaults, so if we also define `foo` within the role
and the play, those values will be ignored:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  vars:
    foo: "I'm the foo passed to the whole play"
  pre_tasks:
    - debug:
        msg: "{{ foo }}"
  roles:
    - role: print
      vars:
        foo: "I'm the foo passed to print in vars"
  tasks:
    - debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
---
# ./roles/print/defaults/main.yaml
foo: "I'm the foo defined in role vars"
```
{% endraw %}

```
PLAY [Run the test] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [debug] *******************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [print : Print 'foo'] *****************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [debug] *******************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

There is currently an [issue][vars-bug] in Ansible which causes
variables defined in a role's `vars` folder to take precedence over
variables defined for the individual `role` call.

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  vars:
    foo: "I'm the foo passed to the whole play"
  pre_tasks:
    - debug:
        msg: "{{ foo }}"
  roles:
    - role: print
      vars:
        foo: "I'm the foo passed to print in vars"
  tasks:
    - debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
---
# ./roles/print/vars/main.yaml
foo: "I'm the foo defined in role vars"
```
{% endraw %}

```
PLAY [Run the test] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [debug] *******************************************************************
ok: [localhost] => {
    "msg": "I'm the foo defined in role vars"
}

TASK [print : Print 'foo'] *****************************************************
ok: [localhost] => {
    "msg": "I'm the foo defined in role vars"
}

TASK [debug] *******************************************************************
ok: [localhost] => {
    "msg": "I'm the foo defined in role vars"
}

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=
```

To get the intended behaviour, with call-specific variables overriding
role-wide ones, stick to `defaults` rather than `vars` in a role layout.

Ansible provides a configuration switch that restricts the availability
of call-level variables to that single specific call. It can be set
either via the `ANSIBLE_PRIVATE_ROLE_VARS` environment variable or via
the configuration file, like this:

```ini
# This is ansible.cfg
[defaults]
private_role_vars = true
```

Once this setting is in effect, call-level variables will no longer be
available to other tasks. Let's retry the previous example with the new
configuration:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  pre_tasks:
    - name: Before
      debug:
        msg: "{{ foo }}"
  roles:
    - role: print
      vars:
        foo: "I'm the foo passed to print in vars"
  tasks:
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
---
# ./ansible.cfg
[defaults]
private_role_vars = true
```
{% endraw %}

```
PLAY [Run the test] ************************************************************************************************

TASK [Gathering Facts] *********************************************************************************************
ok: [localhost]

TASK [Before] ******************************************************************************************************
fatal: [localhost]: FAILED! => {"msg": "The task includes an option with
an undefined variable. The error was: 'foo' is undefined [REDACTED]

PLAY RECAP *********************************************************************************************************
localhost                  : ok=1    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0
```

The task before the role cannot access `foo`. This is also true for the
task after it:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  roles:
    - role: print
      vars:
        foo: "I'm the foo passed to print in vars"
  tasks:
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
---
# ./ansible.cfg
[defaults]
private_role_vars = true
```
{% endraw %}

```
PLAY [Run the test] ************************************************************************************************

TASK [Gathering Facts] *********************************************************************************************
ok: [localhost]

TASK [print : Print 'foo'] *****************************************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [After] *******************************************************************************************************
fatal: [localhost]: FAILED! => {"msg": "The task includes an option with
an undefined variable. The error was: 'foo' is undefined [REDACTED]

PLAY RECAP *********************************************************************************************************
localhost                  : ok=2    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0 
```

When combined with play-level variables, call-level variables are
visible to the role only, while other tasks still see the play-level
value:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  vars:
    foo: "I'm the global foo"
  pre_tasks:
    - debug:
        msg: "{{ foo }}"
  roles:
    - role: print
      vars:
        foo: "I'm the foo passed to print in vars"
  tasks:
    - debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
---
# ./ansible.cfg
[defaults]
private_role_vars = true
```
{% endraw %}

```
PLAY [Run the test] ************************************************************************************************

TASK [Gathering Facts] *********************************************************************************************
ok: [localhost]

TASK [debug] *******************************************************************************************************
ok: [localhost] => {
    "msg": "I'm the global foo"
}

TASK [print : Print 'foo'] *****************************************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [debug] *******************************************************************************************************
ok: [localhost] => {
    "msg": "I'm the global foo"
}

PLAY RECAP *********************************************************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0 
```

The same is true for role defaults: they are available to other tasks,
but the task itself sees the task-level overrides:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  pre_tasks:
    - debug:
        msg: "{{ foo }}"
  roles:
    - role: print
      vars:
        foo: "I'm the foo passed to print in vars"
  tasks:
    - debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
---
# ./roles/print/defaults/main.yaml
foo: "I'm foo defined in the defaults"
---
# ./ansible.cfg
[defaults]
private_role_vars = true
```
{% endraw %}

```
PLAY [Run the test] ************************************************************************************************

TASK [Gathering Facts] *********************************************************************************************
ok: [localhost]

TASK [debug] *******************************************************************************************************
ok: [localhost] => {
    "msg": "I'm foo defined in the defaults"
}

TASK [print : Print 'foo'] *****************************************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [debug] *******************************************************************************************************
ok: [localhost] => {
    "msg": "I'm foo defined in the defaults"
}

PLAY RECAP *********************************************************************************************************
localhost                  : ok=4    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0 
```

`import_role` behaves in the same way.

Using `private_role_vars` can help solve the other typical name clash
problem that arises with static imports. We have [already
seen](#name-clashes) how to handle clashes between different roles. But
that solution does not allow calling the same role more than once
without call-level variables passed to one call impacting the others.

`private_role_vars` can provide a solution:

{% raw %}
```yaml
# ./main.yaml <==
- name: Run the test
  hosts: localhost
  connection: local
  roles:
    - do_thing
    - role: do_thing
      vars:
        state: a nap
---
# ./roles/do_thing/tasks/main.yaml <==
- name: do_thing
  debug:
    msg: I'm going to do {{ state | default("nothing") }}
---
# ./ansible.cfg <==
[defaults]
private_role_vars = true
```
{% endraw %}


```
PLAY [Run the test] ************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [do_thing : do_thing] *****************************************************
ok: [localhost] => {
    "msg": "I'm going to do nothing"
}

TASK [do_thing : do_thing] *****************************************************
ok: [localhost] => {
    "msg": "I'm going to do a nap"
}

PLAY RECAP *********************************************************************
localhost                  : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

This time, the playbook work as intended. The `state` variable passed to
the second role invocation only affects that invocation. The first one
receives no `state` variable, and the default filter correctly expands
to the internally defined default value.

### Dynamic includes

When calling roles dynamically, task-level `vars` follow the behaviour
mandated by `public`. They are available to no other tasks if `public`
is set to `false`, and to subsequent tasks only if `public` is set to
`true`.

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  pre_tasks:
    - name: Before
      debug:
        msg: "{{ foo }}"
  tasks:
    - include_role:
        name: print
      vars:
        foo: "I'm the foo passed to print in vars"
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
```
{% endraw %}

```
PLAY [Run the test] ************************************************************************************************

TASK [Gathering Facts] *********************************************************************************************
ok: [localhost]

TASK [Before] ******************************************************************************************************
fatal: [localhost]: FAILED! => {"msg": "The task includes an option with
an undefined variable. The error was: 'foo' is undefined [REDACTED]

PLAY RECAP *********************************************************************************************************
localhost                  : ok=1    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0 
```

And:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  tasks:
    - include_role:
        name: print
      vars:
        foo: "I'm the foo passed to print in vars"
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
```
{% endraw %}

```
PLAY [Run the test] ************************************************************************************************

TASK [Gathering Facts] *********************************************************************************************
ok: [localhost]

TASK [include_role : print] ****************************************************************************************

TASK [print : Print 'foo'] *****************************************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [After] *******************************************************************************************************
fatal: [localhost]: FAILED! => {"msg": "The task includes an option with
an undefined variable. The error was: 'foo' is undefined [REDACTED]

PLAY RECAP *********************************************************************************************************
localhost                  : ok=2    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0 
```

And:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  tasks:
    - include_role:
        name: print
        public: yes
      vars:
        foo: "I'm the foo passed to print in vars"
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
```
{% endraw %}

```
PLAY [Run the test] ************************************************************************************************

TASK [Gathering Facts] *********************************************************************************************
ok: [localhost]

TASK [include_role : print] ****************************************************************************************

TASK [print : Print 'foo'] *****************************************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [After] *******************************************************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

PLAY RECAP *********************************************************************************************************
localhost                  : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

If we now add `private_role_vars` and a default value for `foo`, notice
how the subsequent task receives the default value of `foo`:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  tasks:
    - include_role:
        name: print
        public: yes
      vars:
        foo: "I'm the foo passed to print in vars"
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
---
# ./roles/print/defaults/main.yaml
foo: "I'm the foo from the defaults"
---
# ./ansible.cfg
[defaults]
private_role_vars = true
```
{% endraw %}

```
PLAY [Run the test] ************************************************************************************************

TASK [Gathering Facts] *********************************************************************************************
ok: [localhost]

TASK [include_role : print] ****************************************************************************************

TASK [print : Print 'foo'] *****************************************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [After] *******************************************************************************************************
ok: [localhost] => {
    "msg": "I'm the foo from the defaults"
}

PLAY RECAP *********************************************************************************************************
localhost                  : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0 
```

The same holds if we replace the role default with a play variable:

{% raw %}
```yaml
# ./main.yaml
- name: Run the test
  hosts: localhost
  connection: local
  vars:
    foo: Global foo
  tasks:
    - include_role:
        name: print
        public: yes
      vars:
        foo: "I'm the foo passed to print in vars"
    - name: After
      debug:
        msg: "{{ foo }}"
---
# ./roles/print/tasks/main.yaml
- name: Print 'foo'
  debug:
    msg: "{{ foo }}"
---
# ./ansible.cfg
[defaults]
private_role_vars = true
```
{% endraw %}

```
PLAY [Run the test] ************************************************************************************************

TASK [Gathering Facts] *********************************************************************************************
ok: [localhost]

TASK [include_role : print] ****************************************************************************************

TASK [print : Print 'foo'] *****************************************************************************************
ok: [localhost] => {
    "msg": "I'm the foo passed to print in vars"
}

TASK [After] *******************************************************************************************************
ok: [localhost] => {
    "msg": "Global foo"
}

PLAY RECAP *********************************************************************************************************
localhost                  : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0 
```

## Summing up

As we have seen, interactions between role defaults, play variables and
vars passed to specific tasks or role invocations can lead to surprises.
To minimize the chances of unwanted name clashes, some rules can be
helpful:

* prefer `include_role` to `import_role` or `roles` when possible, as
  this prevents role defaults being available to earlier roles and
  tasks;
* prefer keeping `public` in calls to `include_role` set to `false`, so
  that role defaults are not available to tasks coming later;
* prefer running with `private_role_vars` set to `true`;
* use prefixes (or any other naming scheme that can reasonably guarantee
  uniqueness) to logically separate variables belonging to different
  roles.


<!-- Links -->
[precedence]: https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#ansible-variable-precedence
[vars-bug]: https://github.com/ansible/ansible/issues/69388
[private-role-vars]: https://docs.ansible.com/ansible/latest/reference_appendices/config.html#default-private-role-vars

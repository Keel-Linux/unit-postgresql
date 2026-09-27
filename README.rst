unit-postgresql
===============

The PostgreSQL component of Keel Linux, as a fab unit: a directory carrying a
``plan``, an ``overlay/``, an executable ``conf`` and a ``conf-vars``, which
fab resolves and applies when the recipe being built has it under ``unit.d/``
(``UNIT_DIRS`` in ``share/product.mk``). Compatible with TurnKey Linux
appliances: this is the PostgreSQL half of ``turnkeylinux/common``, taken out
of the shared tree so that it can be released, pinned and rolled back on its
own (decision 0010).

Why a repository, and why this name
-----------------------------------

Decision 0006 gives appliances the ``keel-`` prefix and leaves infrastructure
unprefixed. A component is neither: not an appliance, and not a fork of an
upstream repository. ``unit-`` names the artefact in the vocabulary of the
build system that consumes it, and the name after the dash is the directory
under ``unit.d``, which is the name the layer manifest carries::

    keel-linux/unit-postgresql   ->   unit.d/postgresql   ->   units postgresql@1.0.0

The component is named ``postgresql`` and not ``pgsql``, which is what the
shared tree calls it, because that is the name of the server, of the layer and
of the appliance.

What it carries
---------------

======================  =====================================================
File                    Origin in the shared tree
======================  =====================================================
``plan``                the package names, which the shared tree kept in each
                        recipe because it had no ``plans/turnkey/pgsql``
``overlay/``            ``overlays/pgsql`` (2 files, byte identical)
``conf``                ``conf/pgsql``, plus the bind addresses, plus two
                        overridable directory roots
``conf-vars``           ``CONF_VARS += PGSQL_PASS`` of
                        ``mk/turnkey/pgsql.mk``
``version``             the pin ``bt-layer`` records in the layer manifest
======================  =====================================================

There is no ``removelist``: the shared tree had no ``removelists/pgsql``.

The bind addresses, and why they moved here
-------------------------------------------

The conf script sets::

    listen_addresses = '::1,127.0.0.1'

``keel-postgresql``'s ``conf.d/main`` did this until today. It moves into the
component because binding is what whoever installs the server decides, and
LAPP will carry this component without carrying that recipe: decision 0013
makes the database a component precisely so that LAMP and LAPP can share one
``apache-php`` layer, and a fix that lives in one recipe would have to be
copied into the other.

Debian's default is ``listen_addresses = 'localhost'``, which reads like "the
loopback of both families" and is not. Debian's ``/etc/hosts`` maps ``::1`` to
``ip6-localhost`` and ``ip6-loopback`` and never to ``localhost``, so
``getaddrinfo("localhost")`` answers ``127.0.0.1`` alone and the cluster binds
the IPv4 loopback only. Measured on a booted layer: ``LISTEN 127.0.0.1:5432``
and nothing on ``[::1]:5432``, with ``::1`` up on ``lo`` and ``pg_hba.conf``
already holding its ``scram-sha-256`` line for ``::1/128``. An appliance
reaching its own database over IPv6, which is the default this project builds
for, found nothing listening.

Two literal addresses cannot resolve into something else. The conf script
checks the file after writing it, and ``keel-postgresql`` keeps its own checks
on the built image and on the booted machine, so the component is verified by
the recipe rather than trusted by it.

How a recipe consumes it
------------------------

The recipe stops including the shared tree's makefile fragment, and the
component is materialised as a directory under the product's ``unit.d/``::

    git clone --branch v1.0.0 https://github.com/keel-linux/unit-postgresql.git \
        $FAB_PATH/products/postgresql/unit.d/postgresql
    bt-layer postgresql --parent core

``bt-layer`` reads ``version``, records ``units postgresql@1.0.0`` in the
layer manifest, and a child layer built on that one subtracts the component
instead of applying it again. Assembling ``unit.d`` from the pins a recipe
declares is the step decision 0010 names as new code of the project and does
not exist yet: today the clone above is the assembly step, and the layer
manifest is the record of what was applied.

Order in the build
------------------

fab applies every unit overlay, then every unit conf script, then every unit
removelist, after the common overlays, conf scripts and patches and before the
common removelists, the product overlay and the product's own ``conf.d``. So
this conf script runs before the recipe's, which is what lets
``keel-postgresql`` remove the ``postgres`` role's password afterwards and
check the bind addresses this script wrote.

Not measured here
-----------------

``overlay/usr/lib/inithooks/firstboot.d/35pgsqlpass`` sources
``/etc/default/inithooks`` by absolute path and
``overlay/usr/lib/inithooks/bin/pgsqlconf.py`` is Python: neither can be
redirected into a scratch tree without editing a file the image ships, and the
extraction must not change a byte of that. COVERAGE.md has the detail and the
plan.

Tests
-----

``tests/coverage.sh`` runs the bats suite under kcov and fails below
``COVERAGE_THRESHOLD``.

# Scoped authorization

Implement and review scope-based authorization in a multi-role Rails app — query-object scopes as the single read boundary, 404 for out-of-scope records versus 403 for forbidden actions, explicit unauthenticated opt-outs, and record isolation by payload construction. Use when adding a role, a scoped resource, an admin screen, an attachment or export route, or when auditing who can see what.

One skill, one repository. Part of a twelve-skill pack extracted from a production Rails 8 +
Inertia + React helpdesk monolith — the opinionated layer no public Rails or shadcn skill can know.
Version `2.0.0` tracks the source constitution.

## Install

```jsonc
// skills-lock.json
{
  "version": 1,
  "skills": {
    "scoped-authorization": {
      "source": "mahardikalgw/ruby-scoped-authorization",
      "sourceType": "github",
      "skillPath": "SKILL.md"
    }
  }
}
```

Or clone and symlink:

```bash
git clone git@github.com:mahardikalgw/ruby-scoped-authorization.git
ln -s "$PWD/ruby-scoped-authorization" .claude/skills/scoped-authorization
```

## When to activate

- Adding a role, a permission, or a scoped resource.
- Adding a route that reads or writes a record by id.
- Adding an admin screen, an export, an attachment download, or a notification list.
- Reviewing a diff that touches `before_action`, `find_*`, or a query object.
- Writing the test that proves a foreign record is unreachable.

## What's inside

```
ruby-scoped-authorization/
  SKILL.md
  assets/authorization_sweep_test.rb
  bin/check-skill
  references/denial-semantics.md
  references/isolation.md
```

`SKILL.md` is a router (kept under 250 lines) — the depth lives in `references/`, and the
copy-in code lives in `assets/`.

## Validate

```bash
./bin/check-skill
```

Checks frontmatter, the activation section, link resolution, orphaned references, script
executability, leftover placeholders, and — when the source app is checked out next to this
repository — that vendored scripts still match it byte for byte. Runs in CI on every push.

## Related skills

- [`inertia-test-harness`](https://github.com/mahardikalgw/ruby-inertia-test-harness) — minitest + inertia helpers, builder objects, and system tests that do not flake
- [`guarded-status-workflow`](https://github.com/mahardikalgw/ruby-guarded-status-workflow) — a declarative transition map, per-edge guards, one transaction, an event row

## Licence

MIT — see [LICENSE](LICENSE).

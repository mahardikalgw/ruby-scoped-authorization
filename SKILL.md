---
name: scoped-authorization
description: Implement and review scope-based authorization in a multi-role Rails app — query-object scopes as the single read boundary, 404 for out-of-scope records versus 403 for forbidden actions, explicit unauthenticated opt-outs, and record isolation by payload construction. Use when adding a role, a scoped resource, an admin screen, an attachment or export route, or when auditing who can see what.
version: 2.0.0
---

# Scoped authorization

One question decides the whole design: **can this row be seen by this user?** If the answer is no, the
row does not exist for that request. Every rule below follows from refusing to confirm existence.

## When to activate

- Adding a role, a permission, or a scoped resource.
- Adding a route that reads or writes a record by id.
- Adding an admin screen, an export, an attachment download, or a notification list.
- Reviewing a diff that touches `before_action`, `find_*`, or a query object.
- Writing the test that proves a foreign record is unreachable.

## The four layers

| Layer | Owns | Never does |
|---|---|---|
| Scope (query object) | *Which rows exist for this user* | Decide 403 vs 404 |
| `before_action` | Lookup through the scope, then a role refusal | Build a query |
| Payload builder | *Which fields* reach this audience | Filter by a flag |
| Test | The cross-account sweep + the leak assertion | Drive a UI |

## 1. The scope is the read boundary

```ruby
module Tickets
  class VisibleTo
    def initialize(user) = @user = user

    def relation
      scope = Ticket.where(workspace_id: @user.workspace_id)

      case @user.role
      when "requester"      then scope.where(requester_id: @user.id)
      when "agent"          then (scope.where(support_team_id: @user.support_team_ids)
                                       .or(scope.where(assigned_agent_id: @user.id)))
                                       .where(restricted: false)
      when "team_leader"    then scope.where(support_team_id: @user.led_team_ids).where(restricted: false)
      else                       scope
      end
    end
  end
end
```

Every controller read goes through it:

```ruby
before_action :find_visible_ticket!, only: :show

def find_visible_ticket!
  @ticket = Ticket.visible_to(Current.user).find_by!(ticket_number: params[:ticket_number])
end
```

`find_by!` on a scoped relation raises `RecordNotFound` for a foreign row, and the shared handler
renders **404**. That is the whole point: a 403 would confirm the row exists.

Make the scope a real query object the moment it has one role-specific branch. An `.or` inside a
controller is a scope that will be re-derived, slightly differently, at the next call site.

## 2. Two relations, two verbs

```ruby
class ManageableBy
  def initialize(user) = @user = user

  def relation
    return Ticket.none unless @user&.staff?
    Tickets::VisibleTo.new(@user).relation
  end
end
```

- `visible_to(user)` — reads. A requester sees their own.
- `manageable_by(user)` — writes and workflow. Requesters never manage; staff manage exactly what they
  can see.

Two relations means a service can assert "this actor may change this row" with one call, and a test can
assert a requester's `manageable_by` relation is empty without touching a controller.

## 3. 403 is for an action, 404 is for a record

```ruby
def authorize_my_tickets!
  deny! if Current.user.admin?          # an administrator has no My tickets destination at all
end
```

- **404** — the record is outside the scope. Typing a foreign id behaves exactly like typing a
  non-existent one.
- **403** — the *action* is closed to this role, and the page or route still exists. An administrator
  refused the ticket form gets 403, the same answer whether they clicked a hidden control or typed the
  URL.
## 4. Public routes opt out explicitly

```ruby
class PagesController < ApplicationController
  allow_unauthenticated_access only: %i[ home ]

  def home
    render inertia: "home", props: PublicOverview.call(workspace: current_workspace)
  end
end
```

The concern installs `before_action :require_authentication` for every controller. A public action must
say so **by name** — an audit of `allow_unauthenticated_access` then lists the entire attack surface.
An action that inherits the default is protected; there is no way to accidentally be public.

## 5. Isolation by construction, not by flag

```ruby
props = if Current.user.staff?
          Tickets::Payload.for_staff(ticket: @ticket, actor: Current.user)
        else
          Tickets::Payload.for_requester(ticket: @ticket)
        end
```

`for_requester` is handed `public_comments(ticket)` — a relation that cannot contain an internal note.
There is no `unless viewer.staff?` to forget. The same shape applies to restricted tickets, another
user's notifications, and attachment downloads.

## 6. Re-authorise on every request, not once at link time

An attachment is served by its own route because a signed blob URL is a bearer token: anyone holding it
can read it, forever. The controller re-scopes the **parent** on each request:

```ruby
class AttachmentsController < ApplicationController
  def show
    blob = ActiveStorage::Blob.find_signed!(params[:signed_id])
    record = blob.attachments.first&.record
    raise ActiveRecord::RecordNotFound unless record

    authorize_parent!(record)          # scope + visibility, exactly as the page does
    send_data blob.download, filename: blob.filename.to_s, type: blob.content_type, disposition: "attachment"
  end
end
```

## The test that proves it

One sweep test with ~30 attempts, asserting status codes:

```ruby
test "cross-account attempts return 404 and leak nothing" do
  sign_in_as @outsider

  get ticket_path(@ticket.ticket_number)
  assert_response :not_found

  get attachment_path(@internal_note.files.first.blob.signed_id)
  assert_response :not_found

  get export_path(@export)
  assert_response :not_found
end
```

Plus one body-level leak assertion per isolated field, because a status code cannot prove a string is
absent:

```ruby
get ticket_path(@ticket.ticket_number)
refute_includes response.body, "CATATAN-INTERNAL-RAHASIA"
```

## Prohibitions

| Never | Why |
|---|---|
| `Ticket.find(params[:id])` | Bypasses the scope entirely |
| A role check inside a view or component | Two authorization surfaces, one of them unaudited |
| `if user.admin?` decided by a client string | Authorization is never a client decision |
| A `restricted` flag checked only where the UI hides it | The route is the boundary, not the button |
| The same 403 for a missing row and a foreign row | Confirms existence |
| Revealing counts ("3 restricted tickets hidden") | Leaks existence through an aggregate |

## References

- [references/denial-semantics.md](references/denial-semantics.md) — which status for which refusal, and the handler
- [references/isolation.md](references/isolation.md) — payload builders, attachments, exports, notifications
- [assets/authorization_sweep_test.rb](assets/authorization_sweep_test.rb) — the sweep test to adapt


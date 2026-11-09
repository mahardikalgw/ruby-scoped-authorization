# Isolation: payloads, files, exports, notifications

A scope decides which **rows** a request can reach. Isolation decides which **fields** leave the server
once a row is reachable. Most leaks are the second kind: the right row for the wrong audience.

## Two builders, not a flag

```ruby
module Tickets
  class Payload
    def self.for_staff(ticket:, actor:)
      {
        ticket: summary(ticket),
        comments: ticket.comments.ordered,                    # public + internal
        can: staff_can(ticket, actor)
      }
    end

    def self.for_requester(ticket:)
      {
        ticket: summary(ticket),
        comments: ticket.comments.public_only.ordered,        # cannot contain an internal note
        can: { reply: true, close: true }
      }
    end
  end
end
```

`public_comments` is a relation on the model, so "no internal note reaches a requester" is a property of
the query rather than of a conditional. A reviewer can verify it by reading one line.

## Attachments

Three rules, because a signed blob URL is a bearer token:

1. Files are never served from `/rails/active_storage/blobs/:signed_id`; the route is
   `GET /attachments/:signed_id` and it re-authorises the **parent record** on every request.
2. A file attached to an internal note is reachable only through a payload that already excluded the
   note — so an internal attachment has no route for a requester in the first place.
3. The filename is a header parameter, not an interpolated string; `send_data` with `disposition:
   "attachment"` prevents the browser rendering an uploaded HTML file same-origin.

```ruby
def show
  blob = ActiveStorage::Blob.find_signed!(params[:signed_id])
  record = blob.attachments.first&.record
  raise ActiveRecord::RecordNotFound unless record
  raise ActiveRecord::RecordNotFound unless visible_parent?(record)

  send_data blob.download, filename: blob.filename.to_s, type: blob.content_type, disposition: "attachment"
end
```

Validation on upload belongs in a model, not in a controller: allowed content types, a byte ceiling,
and a workspace-level storage cap. A rejected upload must leave no blob behind.

## Exports

An export is a record with a status, because generating it is not the request:

```ruby
ExportRequest.create!(workspace: current_workspace, requested_by: Current.user, filters: filters, status: "queued")
ExportTicketsJob.perform_later(export.id)
```

- The export stores the **identity of the requester**, so `GET /exports/:id` scopes through
  `current_user.export_requests`, and a foreign export is a 404.
- The CSV is built from the same scoped relation as the screen. An export that runs its own query will
  eventually export rows the screen does not show.
- Column selection is explicit. A CSV of `ticket.attributes` leaks every column, including the ones the
  payload builder exists to withhold. Never include comment bodies in a ticket export.
- The file is written to a private location and served through the authorised route, never to `public/`.

## Notifications

A notification is a delivery of a fact, and the fact is per-audience:

```ruby
Tickets::Notify.call(ticket: ticket, kind: "ticket_reply", actor: actor)
```

- An internal note notifies **no requester**. The service branches on `comment.public?` before it writes
  a ledger row.
- The mail body uses the requester payload, so an internal field cannot ride along in an email.
- A notification row is scoped by `user_id`; the inbox and the bell both read
  `user.notifications`, never a workspace-wide relation filtered in the view.

## The aggregates trap

```ruby
# no
"#{@ticket.comments.count} komentar"
# yes
"#{@visible_comments.count} komentar"
```

A count of everything, shown to someone who may not see everything, leaks existence. Count the scoped
relation, always.

## Search

Full-text and keyword search must run on the scoped relation:

```ruby
Ticket.visible_to(Current.user).where("title ILIKE :q OR description ILIKE :q", q: "%#{q}%")
```

A global search index that is filtered after retrieval returns a page whose total count is wrong and
whose timing leaks the existence of rows the user cannot open. Scope first, then search.

## Checklist for a new audience

1. Does a scope exist that answers "which rows"? If not, write it before the controller.
2. Does each reachable row have a builder for this audience? If not, write it.
3. Is every child row (comments, files, events, notifications) reachable only through that builder?
4. Does the route re-authorise on every request, including files and exports?
5. Is there a sweep test and a body-level leak test?
6. Are the counts scoped?

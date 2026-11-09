# Denial semantics

## The decision table

| Situation | Response | Rendered by | Why |
|---|---|---|---|
| Not signed in, protected route | 302 → landing | `request_authentication` | The deep link is stored and restored after sign-in |
| Record outside the scope | **404** | `rescue_from RecordNotFound` | Confirming 403 would confirm the row exists |
| Role may not perform the action | **403** | `deny!` | The route exists; this actor may not use it |
| Validation refused a write | 302 back with Inertia `errors` | the action's own branch | The form keeps its state and shows field errors |
| Unknown path | **404** | catch-all route | One shared Inertia error page |
| Server error | **500** | shared handler | No stack trace in production |

## `deny!`

```ruby
module Authorization
  extend ActiveSupport::Concern

  class NotPermitted < StandardError; end

  included do
    rescue_from NotPermitted, with: :render_forbidden
  end

  private
    def deny!
      raise NotPermitted
    end

    def render_forbidden
      render inertia: "errors/show", props: { status: 403 }, status: :forbidden
    end
end
```

Two properties worth keeping:

- The refusal is an **exception**, not a return value. A `if !allowed then return` can be swallowed by a
  later edit; an exception cannot.
- The rendered page is the same Inertia error page as 404 and 500, so there is exactly one error
  surface to style and to test.

## Sessions: the three ways a request is refused

```ruby
require_authentication          # no cookie -> store deep link, redirect to landing
terminate_session               # user deactivated -> clear cookie, redirect with a stated reason
find_session_by_cookie          # expired -> destroy the row, delete the cookie, continue as anonymous
```

A deactivated account is refused on **every** request, not only at sign-in:

```ruby
before_action :require_active_user

def require_active_user
  return if Current.user.nil? || !Current.user.deactivated?

  terminate_session
  redirect_to root_path, alert: I18n.t("helpdesk.errors.account_inactive"), status: :see_other
end
```

## What a refusal may say

The reason belongs on the same page as the entry point, next to the button:

```
"Alamat surel Anda di luar domain institusi."
"Akun Anda tidak aktif. Hubungi administrator."
"Penyedia masuk menolak permintaan. Coba lagi."
```

What a refusal may **not** say:

- Which record caused it ("that ticket belongs to another user") — confirms existence.
- How many records were withheld.
- Whether the id format was valid.

## Deep links

```ruby
def request_authentication
  session[:return_to_after_authenticating] = request.url
  redirect_to root_path
end

def after_authentication_url
  session.delete(:return_to_after_authenticating) || Current.user&.home_path || dashboard_path
end
```

A stored deep link is a URL, not a permission: after sign-in it still goes through the scope, so a link
someone else mailed you cannot open their record.

## Authorization is not authentication

| Question | Answered by | Where |
|---|---|---|
| Who is this? | signed session cookie → `Current.user` | `Authentication` concern |
| Is the account still allowed? | `require_active_user` | `ApplicationController` |
| Which rows exist for them? | `visible_to` / `manageable_by` | query objects |
| May they perform this action? | `deny!` in a `before_action` | controller |
| Which fields do they receive? | payload builder per audience | payload objects |

Five questions, five places. Any of them answered in two places is the bug this file prevents.

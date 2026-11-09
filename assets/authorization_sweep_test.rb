require "test_helper"

# The sweep: every cross-account attempt on every surface, asserted on status codes because a body
# must never confirm that a record exists. Add one block per new route — this file is the regression
# fence around the scope, not a sample.
class AuthorizationSweepTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = create_domain_workspace
    @owner = create_domain_user(workspace: @workspace, email_address: "owner@example.test")
    @peer = create_domain_user(workspace: @workspace, email_address: "peer@example.test")
    @agent = create_domain_user(workspace: @workspace, role: "agent", email_address: "agent-a@example.test")
    @other_workspace = create_domain_workspace(name: "Other Workspace")
    @outsider = create_domain_user(workspace: @other_workspace, email_address: "outsider@example.test")

    @team = create_team(workspace: @workspace)
    SupportTeamMembership.create!(support_team: @team, user: @agent)

    @ticket = create_ticket(workspace: @workspace, requester: @owner, support_team: @team, assigned_agent: @agent)
    @internal_note = create_comment(ticket: @ticket, author: @agent, visibility: "internal",
                                    body: "CATATAN-INTERNAL-RAHASIA-991")
    @ticket.files.attach(io: StringIO.new("bukti"), filename: "bukti.txt", content_type: "text/plain")
    @notification = create_notification(ticket: @ticket, user: @owner)
  end

  test "a peer from the same workspace cannot read the owner's ticket" do
    sign_in_as @peer

    get ticket_path(@ticket.ticket_number)
    assert_response :not_found

    get attachment_path(@ticket.files.first.blob.signed_id)
    assert_response :not_found

    get notification_path(@notification)
    assert_response :not_found
  end

  test "a user from another workspace reaches nothing" do
    sign_in_as @outsider

    get ticket_path(@ticket.ticket_number)
    assert_response :not_found

    get attachment_path(@ticket.files.first.blob.signed_id)
    assert_response :not_found

    get queue_path
    assert_includes [ 404, 403 ], response.status   # whichever this product's policy answers
  end

  test "an anonymous visitor is redirected, not shown an error" do
    get ticket_path(@ticket.ticket_number)
    assert_redirected_to root_path
  end

  test "the requester payload never carries an internal note or its attachment" do
    @internal_note.files.attach(io: StringIO.new("rahasia"), filename: "lampiran-internal.txt",
                                content_type: "text/plain")
    sign_in_as @owner

    get ticket_path(@ticket.ticket_number)

    refute_includes response.body, "CATATAN-INTERNAL-RAHASIA-991"
    refute_includes response.body, "lampiran-internal.txt"
  end

  test "the staff payload does carry the note and marks its visibility" do
    sign_in_as @agent

    get ticket_path(@ticket.ticket_number)

    assert_includes response.body, "CATATAN-INTERNAL-RAHASIA-991"
    assert_includes response.body, "internal"
  end

  test "an internal note creates no requester notification" do
    assert_equal 0, Notification.where(user: @owner, kind: "ticket_reply").count
  end
end

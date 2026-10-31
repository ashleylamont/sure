require "test_helper"
require_relative "../support/goal_funding_test_helpers"

class GoalFundingSafetyTest < ActiveSupport::TestCase
  include GoalFundingTestHelpers
  setup { setup_funding_context }
  teardown { travel_back }

  test "operating floor is counted once alongside protected purposes" do
    adjustment([], floors: { @cash.id => "800" }).apply!
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    run = plan.process_source!(salary_entry)
    assert_equal "awaiting_funds", run.status
    assert_equal 0, allocation_for(@etf)
    snapshot = Goal::CashReservation.new(@cash.reload, user: @user)
    assert_equal 200, snapshot.unallocated
    assert_equal 1000, snapshot.fixed_total
  end

  test "pending holds block cash funding without being added twice" do
    plan = funding_plan
    @cash.entries.create!(name: "Card hold", amount: 100, currency: "USD", date: @family.local_date,
      entryable: Transaction.new(extra: { "up" => { "pending" => true } }))
    Goal::CashReservation.record_reconciliation!(@cash)
    travel_to Time.utc(2026, 11, 12, 12)
    run = plan.process_source!(salary_entry)
    assert_equal "needs_review", run.status
    assert_equal "pending_cash", run.reason_code
    assert_equal 0, allocation_for(@etf)
  end

  test "backing shortfalls use requested fixed commitments and block automatic funding" do
    plan = funding_plan
    @cash.update!(balance: 900)
    Goal::CashReservation.record_reconciliation!(@cash)
    travel_to Time.utc(2026, 11, 12, 12)
    run = plan.process_source!(salary_entry)
    assert_equal "awaiting_funds", run.status
    assert_equal 100, Goal::CashReservation.new(@cash.reload, user: @user).shortage
    assert_equal 1000, allocation_for(@protected_goal)
  end

  test "a failed audit rolls back the entire payday and an explicit retry stays safe" do
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    GoalAllocationChange.any_instance.stubs(:save!).raises(StandardError, "Synthetic failure")
    entry = salary_entry
    run = plan.process_source!(entry)
    assert_equal "failed", run.status
    assert_nil run.applied_at
    assert_equal 0, allocation_for(@etf)
    assert_equal 0, GoalAllocation.where(goal_funding_run_id: run.id).count
    GoalAllocationChange.any_instance.unstub(:save!)
    run.retry_with_preview!(actor: @user, preview_token: plan.preview(entry: entry, run: run)[:preview_token])
    assert_equal "applied", run.reload.status
    assert_equal 150, allocation_for(@etf)
  end

  test "release of a protected reservation retries an awaiting run without another payday" do
    plan = funding_plan
    @cash.update!(balance: 1000)
    Goal::CashReservation.record_reconciliation!(@cash)
    travel_to Time.utc(2026, 11, 12, 12)
    run = plan.process_source!(salary_entry)
    assert_equal "awaiting_funds", run.status
    adjustment([ { goal_id: @protected_goal.id, account_id: @cash.id, mode: "release", amount: "300" } ]).apply!
    GoalFundingJob.perform_now(@cash.id)
    assert_equal "applied", run.reload.status
    assert_equal 700, allocation_for(@protected_goal)
    assert_equal 150, allocation_for(@etf)
  end

  test "future dates use the family timezone and activation never backfills same-day or historical salary" do
    @family.update!(timezone: "Australia/Sydney")
    travel_to Time.utc(2026, 11, 1, 12)
    plan = funding_plan
    assert_equal Date.new(2026, 11, 2), plan.automatic_start_on
    assert_nil plan.process_source!(salary_entry(date: Date.new(2026, 11, 1)))
    tomorrow = salary_entry(date: Date.new(2026, 11, 2))
    assert_nil plan.process_source!(tomorrow)
    travel_to Time.utc(2026, 11, 1, 14)
    assert_equal Date.new(2026, 11, 2), @family.local_date
    assert_equal "applied", plan.process_source!(tomorrow).status
    assert_nil plan.process_source!(salary_entry(date: Date.new(2026, 10, 1)))
  end

  test "disabled plans preserve reservations and recovery still reviews deleted applied sources" do
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    entry = salary_entry
    run = plan.process_source!(entry)
    plan.disable!(actor: @user)
    travel_to Time.utc(2026, 11, 27, 12)
    assert_nil plan.process_source!(salary_entry)
    entry.destroy!
    RecoverGoalFundingJob.perform_now(phase: "sources")
    assert_equal "needs_review", run.reload.status
    assert_equal "source_changed", run.reason_code
    assert_equal 150, allocation_for(@etf)
  end

  test "a reversal cannot release cash already used and remains reviewable" do
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    run = plan.process_source!(salary_entry)
    adjustment([ { goal_id: @etf.id, account_id: @cash.id, mode: "release", amount: "100" } ]).apply!
    assert_raises(Goal::AllocationError) { run.reversal_preview(actor: @user) }
    assert_equal 50, allocation_for(@etf)
    assert_nil run.reversed_at
    assert_equal 1, GoalAllocation.where(goal_funding_run_id: run.id).count
  end

  test "preview tokens expire when cash or rules change and plan updates require revision" do
    plan = funding_plan(enable: false)
    token = plan.preview[:preview_token]
    adjustment([ { goal_id: @giving.id, account_id: @cash.id, amount: "10" } ]).apply!
    error = assert_raises(Goal::AllocationError) { plan.enable!(actor: @user, preview_token: token, confirm_salary_source: true) }
    assert_equal "stale_preview", error.code
    assert_raises(Goal::AllocationError) { plan.configure!(actor: @user, expected_revision: 0, attributes: { name: "No" }, rules: nil) }
    assert_not plan.reload.enabled?
  end

  test "old allocation forms cannot overwrite a plan-managed reservation" do
    funding_plan
    assert_not @etf.goal_accounts.first.update(allocated_amount: 100)
    assert_equal 0, allocation_for(@etf)
  end

  test "repeated enable requests preserve the original salary eligibility boundary" do
    plan = funding_plan
    activated_at = plan.enabled_at
    travel_to Time.utc(2026, 11, 12, 12)
    plan.enable!(actor: @user, preview_token: plan.preview[:preview_token], confirm_salary_source: true)
    assert_equal activated_at, plan.reload.enabled_at
    assert_equal "applied", plan.process_source!(salary_entry).status
  end

  test "moving a card donation and releasing investment cash leave bank activity unchanged" do
    adjustment([ { goal_id: @giving.id, account_id: @cash.id, amount: "100" },
                 { goal_id: @etf.id, account_id: @cash.id, amount: "300" } ]).apply!
    counts = [ Entry.count, Transaction.count, Budget.count ]
    adjustment([ { goal_id: @giving.id, account_id: @cash.id, mode: "release", amount: "80" },
                 { goal_id: @protected_goal.id, account_id: @cash.id, mode: "add", amount: "80" } ]).apply!
    adjustment([ { goal_id: @etf.id, account_id: @cash.id, mode: "release", amount: "300" } ]).apply!
    assert_equal 20, allocation_for(@giving)
    assert_equal 1080, allocation_for(@protected_goal)
    assert_equal 0, allocation_for(@etf)
    assert_equal counts, [ Entry.count, Transaction.count, Budget.count ]
    assert_equal 2000, @cash.reload.balance
  end

  test "an archived reserve cannot reclaim cash already committed by a funding plan" do
    @protected_goal.archive!
    funding_plan
    adjustment([ { goal_id: @etf.id, account_id: @cash.id, amount: "1500" } ]).apply!
    assert_not @protected_goal.unarchive!
    assert @protected_goal.reload.archived?
  end

  test "a source still reconciling cannot fund before its sync completes" do
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    entry = salary_entry
    sync = @salary_account.syncs.create!(status: "syncing")
    assert_nil plan.process_source!(entry)
    assert_equal 0, plan.runs.count
    sync.update!(status: "completed", completed_at: Time.current)
    GoalFundingJob.perform_now(@salary_account.id)
    assert_equal "applied", plan.runs.first.status
  end

  test "committed balance-affecting entry edits invalidate cached funding cash" do
    entry = @cash.entries.create!(name: "Real purchase", amount: 20, date: @family.local_date, currency: "USD", entryable: Transaction.new)
    assert_nil @cash.reload.goal_cash_reconciled_at
    Goal::CashReservation.record_reconciliation!(@cash)
    entry.update!(amount: 30)
    assert_nil @cash.reload.goal_cash_reconciled_at
    assert_equal "cash_not_reconciled", Goal::CashReservation.new(@cash, user: @user).review_reason
  end

  test "read-only backing shares and private linked accounts never authorize funding" do
    plan = funding_plan
    @cash.update!(owner: users(:family_member))
    @cash.account_shares.create!(user: @user, permission: "read_only")
    travel_to Time.utc(2026, 11, 12, 12)
    run = plan.process_source!(salary_entry)
    assert_equal "needs_review", run.status
    assert_equal 0, allocation_for(@etf)
    assert_equal 1000, allocation_for(@protected_goal)
  end

  test "history checks original goals after the plan has been reconfigured" do
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    run = plan.process_source!(salary_entry)
    private_account = funding_account("Private linked savings", 100)
    private_account.update!(owner: users(:family_member))
    @etf.goal_accounts.create!(account: private_account, allocated_amount: 0)
    plan.configure!(actor: @user, expected_revision: plan.revision, attributes: { name: "Reconfigured" },
      rules: [ { goal_id: @giving.id, amount: "100" } ])
    access = Goal::Funding.new(@user)
    assert_equal plan.id, access.plan(plan.id).id
    assert_raises(ActiveRecord::RecordNotFound) { access.run(run.id) }
    assert_empty access.runs(plan)
    payload = Goal::CashReservation.new(@cash.reload, user: @user).as_json
    assert_not_includes payload[:reservations].map { |item| item[:goal_name] }, @etf.name
  end
end

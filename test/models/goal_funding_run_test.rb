require "test_helper"
require_relative "../support/goal_funding_test_helpers"

class GoalFundingRunTest < ActiveSupport::TestCase
  include GoalFundingTestHelpers

  setup { setup_funding_context }
  teardown { travel_back }

  test "salary in a different account funds fixed purposes once without moving bank money" do
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    entry = salary_entry
    original_counts = [ Entry.count, Transaction.count ]
    run = plan.process_source!(entry)
    assert_equal "applied", run.status
    assert_equal 150, allocation_for(@etf)
    assert_equal 100, allocation_for(@giving)
    assert_equal 750, Goal::CashReservation.new(@cash.reload, user: @user).unallocated
    assert_equal 2000, @cash.balance
    assert_equal original_counts, [ Entry.count, Transaction.count ]
    3.times { plan.process_source!(entry) }
    assert_equal 1, plan.runs.count
    assert_equal 1, GoalAllocation.where(goal_funding_run_id: run.id, kind: "funding").count
    assert_equal 2, GoalAllocation.find_by!(goal_funding_run_id: run.id).allocation_changes.count
    assert_equal 150, allocation_for(@etf)
  end

  test "insufficient funds allocate nothing and a later reconciliation retries the same run" do
    plan = funding_plan
    @cash.update!(balance: 1200)
    Goal::CashReservation.record_reconciliation!(@cash)
    travel_to Time.utc(2026, 11, 12, 12)
    run = plan.process_source!(salary_entry)
    assert_equal "awaiting_funds", run.status
    assert_equal 0, allocation_for(@etf)
    assert_equal 0, allocation_for(@giving)
    @cash.update!(balance: 2000)
    Goal::CashReservation.record_reconciliation!(@cash)
    plan.recover!
    assert_equal "applied", run.reload.status
    assert_equal 1, plan.runs.count
    assert_equal 150, allocation_for(@etf)
  end

  test "pending transfer excluded equity historical and future transactions do not create runs" do
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    pending = salary_entry
    pending.entryable.update!(extra: { "up" => { "pending" => true } })
    transfer = salary_entry
    transfer.entryable.update!(kind: "funds_movement")
    examples = [ pending, transfer, salary_entry(excluded: true), salary_entry(name: "Payroll credit equity proceeds"), salary_entry(amount: -12000),
                 salary_entry(date: Date.new(2026, 10, 29)), salary_entry(date: Date.new(2026, 11, 27)) ]
    examples.each { |entry| assert_nil plan.process_source!(entry) }
    assert_equal 0, plan.runs.count
    pending.entryable.update!(extra: { "up" => { "pending" => false } })
    Goal::CashReservation.record_reconciliation!(@salary_account.reload)
    assert_equal "applied", plan.process_source!(pending).status
    assert_equal 1, plan.runs.count
  end

  test "a newer payday sends an older waiting run to review instead of applying a backlog" do
    plan = funding_plan
    @cash.update!(balance: 1000)
    Goal::CashReservation.record_reconciliation!(@cash)
    travel_to Time.utc(2026, 11, 12, 12)
    older = plan.process_source!(salary_entry)
    travel_to Time.utc(2026, 11, 27, 12)
    newest = plan.process_source!(salary_entry)
    assert_equal "needs_review", older.reload.status
    assert_equal "newer_payday", older.reason_code
    @cash.update!(balance: 2000)
    Goal::CashReservation.record_reconciliation!(@cash)
    plan.recover!
    assert_equal "applied", newest.reload.status
    assert_equal "needs_review", older.reload.status
    assert_equal 150, allocation_for(@etf)
  end

  test "paused goals keep their money and make a payday require review" do
    plan = funding_plan
    @etf.pause!
    travel_to Time.utc(2026, 11, 12, 12)
    run = plan.process_source!(salary_entry)
    assert_equal "needs_review", run.status
    assert_equal 1000, allocation_for(@protected_goal)
    assert_equal 0, allocation_for(@giving)
  end

  test "funding continues above maintained targets unless explicitly capped" do
    plan = funding_plan
    adjustment([ { goal_id: @etf.id, account_id: @cash.id, amount: "300" } ]).apply!
    travel_to Time.utc(2026, 11, 12, 12)
    assert_equal "applied", plan.process_source!(salary_entry).status
    assert_equal 450, allocation_for(@etf)
    assert @etf.reload.active?
  end

  test "stop at target contributes the gap and records a zero gap as a no-op" do
    @etf.goal_accounts.first.update!(allocated_amount: 250)
    plan = funding_plan(rules: [ { goal_id: @etf.id, amount: "150", stop_at_target: true } ])
    travel_to Time.utc(2026, 11, 12, 12)
    first = plan.process_source!(salary_entry)
    assert_equal "applied", first.status
    assert_equal 300, allocation_for(@etf)
    travel_to Time.utc(2026, 11, 27, 12)
    second = plan.process_source!(salary_entry)
    assert_equal "applied", second.status
    assert_equal true, GoalAllocation.find_by!(goal_funding_run_id: second.id).result["no_op"]
    assert_equal 300, allocation_for(@etf)
  end

  test "plan changes while waiting require a newly reviewed payload" do
    plan = funding_plan
    @cash.update!(balance: 1000)
    Goal::CashReservation.record_reconciliation!(@cash)
    travel_to Time.utc(2026, 11, 12, 12)
    entry = salary_entry
    run = plan.process_source!(entry)
    original_payload = run.rules_snapshot
    plan.configure!(actor: @user, expected_revision: plan.revision,
                    attributes: { name: "Revised funding" }, rules: [ { goal_id: @etf.id, amount: "200" } ])
    assert_equal "needs_review", run.reload.status
    assert_equal original_payload, run.rules_snapshot
    @cash.update!(balance: 2000)
    Goal::CashReservation.record_reconciliation!(@cash)
    plan.enable!(actor: @user, preview_token: plan.preview[:preview_token], confirm_salary_source: true)
    preview = plan.preview(entry: entry, run: run)
    run.retry_with_preview!(actor: @user, preview_token: preview[:preview_token])
    assert_equal "applied", run.reload.status
    assert_equal 200, allocation_for(@etf)
    assert_equal 1, run.review_history.size
  end

  test "reversing a reviewed run writes compensation without reversing its bank transaction" do
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    entry = salary_entry
    run = plan.process_source!(entry)
    preview = run.reversal_preview(actor: @user)
    run.reverse!(actor: @user, preview_token: preview[:preview_token])
    assert_equal "reversed", run.status
    assert_equal 0, allocation_for(@etf)
    assert_equal 0, allocation_for(@giving)
    assert_equal(-4000, entry.reload.amount)
    assert_equal 2, GoalAllocation.where(goal_funding_run_id: run.id).count
    assert_equal 1000, allocation_for(@protected_goal)
  end

  test "editing or deleting a funded source flags review without clawing cash back" do
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    entry = salary_entry
    run = plan.process_source!(entry)
    entry.update!(amount: -4100)
    run.check_source!
    assert_equal "needs_review", run.reload.status
    assert run.applied_at
    assert_equal 150, allocation_for(@etf)
    plan.process_source!(entry)
    assert_equal 150, allocation_for(@etf)
  end

  test "previews and interest deposits make no allocation changes" do
    plan = funding_plan
    assert_no_difference [ "GoalAllocation.count", "GoalFundingRun.count" ] do
      plan.preview
    end
    travel_to Time.utc(2026, 11, 12, 12)
    interest = @cash.entries.create!(name: "Interest credit", date: @family.local_date, amount: -10, currency: "USD", entryable: Transaction.new)
    assert_nil plan.process_source!(interest)
    assert_equal 0, plan.runs.count
  end
end

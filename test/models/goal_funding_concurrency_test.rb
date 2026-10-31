require "test_helper"
require_relative "../support/goal_funding_test_helpers"

class GoalFundingConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  include GoalFundingTestHelpers
  setup { setup_funding_context }
  teardown { travel_back }

  test "concurrent retries of one canonical salary apply one audited batch" do
    plan = funding_plan
    travel_to Time.utc(2026, 11, 12, 12)
    entry = salary_entry
    concurrently(2) { GoalFundingPlan.find(plan.id).process_source!(Entry.find(entry.id)) }
    assert_equal 1, plan.runs.count
    run = plan.runs.first
    assert_equal "applied", run.status
    assert_equal 1, GoalAllocation.where(goal_funding_run_id: run.id, kind: "funding").count
    assert_equal 2, GoalAllocationChange.joins(:goal_allocation).where(goal_allocations: { goal_funding_run_id: run.id }).count
    assert_equal 150, allocation_for(@etf)
    assert_equal 100, allocation_for(@giving)
  end

  test "a manual edit racing automation cannot lose an update or overcommit" do
    plan = funding_plan(rules: [ { goal_id: @etf.id, amount: "150" } ])
    @cash.update!(balance: 1200)
    Goal::CashReservation.record_reconciliation!(@cash)
    version = @cash.reload.goal_allocation_version
    travel_to Time.utc(2026, 11, 12, 12)
    entry = salary_entry
    outcomes = concurrently(2) do |index|
      if index.zero?
        GoalFundingPlan.find(plan.id).process_source!(Entry.find(entry.id)).status
      else
        begin
          Goal::AllocationAdjustment.new(user: User.find(@user.id), adjustments: [ { goal_id: @giving.id, account_id: @cash.id, mode: "add", amount: "100" } ],
            versions: { @cash.id => version }, idempotency_key: "concurrent-manual", reason: "Manual reservation").apply!
          "manual_applied"
        rescue Goal::AllocationError => error
          error.code
        end
      end
    end
    assert_equal 1, outcomes.count { |outcome| %w[applied manual_applied].include?(outcome) }, outcomes.inspect
    snapshot = Goal::CashReservation.new(@cash.reload, user: @user)
    assert_operator snapshot.fixed_total, :<=, snapshot.cash
    assert_equal 0, snapshot.shortage
    assert_operator allocation_for(@etf) + allocation_for(@giving), :<=, 200
  end

  private
    def concurrently(count)
      ready = Queue.new
      start = Queue.new
      threads = count.times.map do |index|
        Thread.new do
          ready << true
          start.pop
          ActiveRecord::Base.connection_pool.with_connection { yield index }
        end
      end
      count.times { ready.pop }
      count.times { start << true }
      threads.map(&:value)
    end
end

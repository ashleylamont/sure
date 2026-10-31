require "test_helper"
require_relative "../../support/goal_funding_test_helpers"

class Goal::AllocationAdjustmentTest < ActiveSupport::TestCase
  include GoalFundingTestHelpers

  setup { setup_funding_context }
  teardown { travel_back }

  test "moves fixed cash atomically without manufacturing financial activity" do
    operations = [ { goal_id: @protected_goal.id, account_id: @cash.id, mode: "release", amount: "80" },
                   { goal_id: @giving.id, account_id: @cash.id, mode: "add", amount: "80" } ]
    original_entry_count = Entry.count
    original_transaction_count = Transaction.count
    result = adjustment(operations).apply!
    assert_equal 920, allocation_for(@protected_goal)
    assert_equal 80, allocation_for(@giving)
    assert_equal 2000, @cash.reload.balance
    assert_equal original_entry_count, Entry.count
    assert_equal original_transaction_count, Transaction.count
    assert_equal "1000.0", result.fetch("accounts").first.fetch(:unallocated, result.fetch("accounts").first["unallocated"])
  end

  test "refuses to overcommit even when displayed backing has been scaled down" do
    @protected_goal.goal_accounts.first.update!(allocated_amount: 3000)
    attempt = adjustment([ { goal_id: @giving.id, account_id: @cash.id, mode: "add", amount: "1" } ])
    assert_equal "insufficient_cash", assert_raises(Goal::AllocationError) { attempt.apply! }.code
    assert_equal 0, allocation_for(@giving)
    assert_equal 1000, Goal::CashReservation.new(@cash.reload, user: @user).shortage
  end

  test "releases remain possible while cash is uncertain or underfunded" do
    @cash.update!(goal_cash_reconciled_at: nil)
    adjustment([ { goal_id: @protected_goal.id, account_id: @cash.id, mode: "release", amount: "100" } ]).apply!
    assert_equal 900, allocation_for(@protected_goal)
  end

  test "legacy whole-account reservations require a signed reviewed conversion" do
    legacy = funding_goal("Existing whole-account reserve", nil)
    operations = [ { goal_id: legacy.id, account_id: @cash.id, mode: "set", amount: "700" } ]
    item = adjustment(operations, key: "convert-existing")
    preview = item.preview
    assert preview[:requires_conversion]
    assert_equal "conversion_confirmation_required", assert_raises(Goal::AllocationError) { item.apply! }.code
    adjustment(operations, key: "convert-existing", preview_token: preview[:preview_token], confirm_conversion: true).apply!
    assert_equal 700, allocation_for(legacy)
    assert_equal 300, Goal::CashReservation.new(@cash.reload, user: @user).unallocated
  end

  test "optimistic versions refuse a stale edit without a lost update" do
    versions = { @cash.id => @cash.reload.goal_allocation_version }
    adjustment([ { goal_id: @etf.id, account_id: @cash.id, amount: "100" } ]).apply!
    error = assert_raises(Goal::AllocationError) do
      adjustment([ { goal_id: @giving.id, account_id: @cash.id, amount: "100" } ], versions: versions).apply!
    end
    assert_equal "stale_state", error.code
    assert_equal :conflict, error.status
    assert_equal 0, allocation_for(@giving)
  end

  test "an identical key returns the original result and changed payload is refused" do
    versions = { @cash.id => @cash.reload.goal_allocation_version }
    operations = [ { goal_id: @etf.id, account_id: @cash.id, amount: "100" } ]
    result = adjustment(operations, key: "request-once", versions: versions).apply!
    assert_no_difference "GoalAllocation.count" do
      assert_equal result, adjustment(operations, key: "request-once", versions: versions).apply!
    end
    error = assert_raises(Goal::AllocationError) do
      adjustment([ operations.first.merge(amount: "101") ], key: "request-once", versions: versions).apply!
    end
    assert_equal "idempotency_mismatch", error.code
  end

  test "audit failure rolls back every reservation change" do
    GoalAllocationChange.any_instance.stubs(:save!).raises(StandardError, "audit unavailable")
    assert_no_difference "GoalAllocation.count" do
      assert_raises(StandardError) { adjustment([ { goal_id: @etf.id, account_id: @cash.id, amount: "100" } ]).apply! }
    end
    assert_equal 0, allocation_for(@etf)
  end

  test "audit rows cannot be edited or removed through the model" do
    result = adjustment([ { goal_id: @etf.id, account_id: @cash.id, amount: "100" } ]).apply!
    batch = GoalAllocation.find_by!(idempotency_key: result.fetch("idempotency_key"))
    assert_raises(ActiveRecord::ReadOnlyRecord) { batch.update!(reason: "Rewritten") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { batch.allocation_changes.first.destroy! }
  end

  test "cross-family goals and read-only account shares cannot be adjusted" do
    outsider = users(:family_member)
    @cash.update!(owner: outsider)
    assert_raises(ActiveRecord::RecordNotFound) do
      adjustment([ { goal_id: @etf.id, account_id: @cash.id, amount: "100" } ]).apply!
    end
  end

  test "money parsing rejects nonfinite negative and subprecision amounts" do
    %w[NaN Infinity -1 0.00001 nonsense].each do |value|
      assert_raises(Goal::AllocationError) { adjustment([ { goal_id: @etf.id, account_id: @cash.id, amount: value } ]) }
    end
  end

  test "replay refuses a saved response containing a purpose that has become private" do
    operations = [ { goal_id: @giving.id, account_id: @cash.id, amount: "10" } ]
    versions = { @cash.id => @cash.reload.goal_allocation_version }
    adjustment(operations, key: "privacy-replay", versions: versions).apply!
    private_account = funding_account("Private savings", 0)
    private_account.update!(owner: users(:family_member))
    @etf.goal_accounts.create!(account: private_account, allocated_amount: 0)
    assert_raises(ActiveRecord::RecordNotFound) { adjustment(operations, key: "privacy-replay", versions: versions).apply! }
    assert_equal 10, allocation_for(@giving)
  end
end

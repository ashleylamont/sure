class GoalAccount < ApplicationRecord
  attr_accessor :reservation_audit_managed, :reservation_write_authorized

  belongs_to :goal
  belongs_to :account

  validates :account_id, uniqueness: { scope: :goal_id }
  validates :allocated_amount,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true

  validate :whole_account_link_must_be_exclusive
  validate :funding_accounts_use_reservation_controls
  before_validation :lock_reservation_account, if: -> { new_record? || allocated_amount_changed? || account_id_changed? || goal_id_changed? }
  before_destroy :lock_reservation_account
  after_save :record_reservation_change
  after_destroy :record_reservation_release

  # nil allocated_amount means "dedicate the whole account balance" (the v1
  # default). A set amount earmarks a fixed slice of the account toward this
  # goal. The share that actually counts toward the goal — after sibling
  # earmarks and the pro-rata over-allocation haircut — is computed by
  # Goal#current_balance, which owns the shared-pool math.
  def whole_account?
    allocated_amount.nil?
  end

  private
    def funding_accounts_use_reservation_controls
      return if reservation_audit_managed || reservation_write_authorized
      return if new_record? && allocated_amount == 0
      return unless new_record? || allocated_amount_changed? || account_id_changed? || goal_id_changed?
      return unless GoalFundingPlan.where(backing_account_id: [ account_id, account_id_in_database ].compact).exists?
      errors.add(:base, I18n.t("goal_funding.errors.use_reservation_controls"))
    end

    def lock_reservation_account
      Goal.lock_whole_account_claims!(account_id) if account_id
    end

    def record_reservation_change
      return if reservation_audit_managed
      return unless previously_new_record? || saved_change_to_allocated_amount?

      before = previously_new_record? ? 0.to_d : allocated_amount_before_last_save
      GoalAllocation.record_link_change!(self, before: before, after: allocated_amount)
    end

    def record_reservation_release
      return if reservation_audit_managed
      GoalAllocation.record_link_change!(self, before: allocated_amount, after: 0.to_d)
    end

    # A whole-account link claims the account's ENTIRE balance, so two of them
    # on one account double-count it. Goal#backing_share_for's pro-rata haircut
    # can't catch this: it only scales FIXED earmarks, and an unallocated link
    # contributes nil.to_d — zero — to `others_fixed`, so the two links never
    # see each other. Both then read the full balance and both show 100%.
    # The invariant "shares never sum past the balance" is therefore enforced
    # at the door instead of in the math.
    #
    # The conflict lookup itself lives on Goal (`whole_account_conflicts_on`),
    # scoped to Goal::RELEASED_STATES — exactly the set
    # Goal.pooled_allocations_for feeds into the backing math. A completed goal
    # has released its earmark, so it no longer blocks a new whole-balance
    # link: refusing one because of a finished goal whose money has already
    # been handed back would be inexplicable to the user. Sharing one method
    # with the restore guard is what keeps this door and that one from
    # disagreeing about which goals still hold their money.
    def whole_account_link_must_be_exclusive
      return unless whole_account?
      return if account_id.nil? || goal.nil?
      # Only guard what is being written now. Rows that predate this
      # validation stay readable and editable: autosave revalidates every
      # loaded goal_account on goal.save, and blocking there would make a
      # goal that merely holds a legacy overlap impossible to rename.
      #
      # "Written now" has to include moving the link, not just re-pricing it.
      # A whole-account row whose account_id or goal_id changes is neither new
      # nor allocation-dirty, so on those two predicates alone it would land on
      # an account nobody checked — the same hole as a restore, through a
      # different door. Widening the bound rather than dropping it: the reason
      # above still holds for every row that is merely along for the ride.
      return unless new_record? ||
                    will_save_change_to_allocated_amount? ||
                    will_save_change_to_account_id? ||
                    will_save_change_to_goal_id?

      other = goal.whole_account_conflicts_on(account_id, excluding_link_id: id).first
      return if other.nil?

      errors.add(:base, :account_already_fully_earmarked, goal_name: other.goal.name)
    end
end

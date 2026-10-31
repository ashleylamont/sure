class CreateGoalFunding < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :goal_operating_floor, :decimal, precision: 19, scale: 4, default: 0, null: false
    add_column :accounts, :goal_allocation_version, :bigint, default: 0, null: false
    add_column :accounts, :goal_reconciled_cash, :decimal, precision: 19, scale: 4
    add_column :accounts, :goal_cash_reconciled_at, :datetime
    add_check_constraint :accounts, "goal_operating_floor >= 0", name: "chk_goal_operating_floor_non_negative"

    create_table :goal_funding_plans, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :backing_account, type: :uuid, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.references :source_account, type: :uuid, foreign_key: { to_table: :accounts, on_delete: :nullify }
      t.uuid :sample_entry_id
      t.string :name, null: false
      t.string :currency, null: false
      t.string :source_name, null: false
      t.text :source_notes
      t.decimal :minimum_salary, precision: 19, scale: 4, null: false
      t.decimal :maximum_salary, precision: 19, scale: 4, null: false
      t.boolean :enabled, default: false, null: false
      t.integer :revision, default: 1, null: false
      t.date :effective_on, null: false
      t.datetime :enabled_at
      t.timestamps
      t.index [ :enabled, :id ]
      t.check_constraint "minimum_salary > 0 AND maximum_salary >= minimum_salary", name: "chk_goal_funding_salary_range"
      t.check_constraint "revision > 0", name: "chk_goal_funding_revision"
    end

    create_table :goal_funding_rules, id: :uuid do |t|
      t.references :goal_funding_plan, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :goal, type: :uuid, foreign_key: { on_delete: :nullify }
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.boolean :stop_at_target, default: false, null: false
      t.timestamps
      t.index [ :goal_funding_plan_id, :goal_id ], unique: true, name: "idx_goal_funding_rule_unique_goal"
      t.check_constraint "amount > 0", name: "chk_goal_funding_rule_amount"
    end

    create_table :goal_funding_runs, id: :uuid do |t|
      t.references :goal_funding_plan, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      # Retain the canonical identity even when the source transaction is deleted.
      t.uuid :source_entry_id, null: false
      t.string :source_fingerprint, null: false
      t.date :source_date, null: false
      t.integer :plan_revision, null: false
      t.jsonb :rules_snapshot, null: false, default: []
      t.jsonb :review_history, null: false, default: []
      t.string :status, null: false, default: "pending"
      t.string :reason_code
      t.datetime :applied_at
      t.datetime :reversed_at
      t.timestamps
      t.index [ :goal_funding_plan_id, :source_entry_id ], unique: true, name: "idx_goal_funding_run_canonical_source"
      t.index [ :goal_funding_plan_id, :status ]
      t.index :source_entry_id
      t.check_constraint "status IN ('pending','applied','awaiting_funds','needs_review','skipped','failed','reversed')", name: "chk_goal_funding_run_status"
    end

    create_table :goal_allocations, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, foreign_key: { on_delete: :nullify }
      t.uuid :goal_funding_run_id
      t.string :idempotency_key, null: false
      t.string :payload_fingerprint, null: false
      t.string :kind, null: false
      t.text :reason, null: false
      t.jsonb :result, null: false, default: {}
      t.timestamps
      t.index [ :family_id, :idempotency_key ], unique: true, name: "idx_goal_allocation_idempotency"
      t.index [ :goal_funding_run_id, :kind ], unique: true, where: "goal_funding_run_id IS NOT NULL", name: "idx_goal_allocation_run_once"
    end

    create_table :goal_allocation_changes, id: :uuid do |t|
      t.references :goal_allocation, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      # These references intentionally survive account/goal deletion for the audit.
      t.uuid :account_id, null: false
      t.uuid :goal_id
      t.string :account_name, null: false
      t.string :goal_name
      t.string :currency, null: false
      t.decimal :before_amount, precision: 19, scale: 4
      t.decimal :after_amount, precision: 19, scale: 4
      t.decimal :delta, precision: 19, scale: 4
      t.timestamps
      t.index [ :goal_allocation_id, :account_id, :goal_id ], unique: true, nulls_not_distinct: true, name: "idx_goal_allocation_change_once"
      t.index [ :account_id, :created_at ]
    end
  end
end

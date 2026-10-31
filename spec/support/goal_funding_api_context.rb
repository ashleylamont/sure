RSpec.shared_context 'goal funding API' do
  let(:family) { Family.create!(name: 'Funding docs family', currency: 'USD', locale: 'en', date_format: '%m-%d-%Y', timezone: 'UTC') }
  let(:user) do
    family.users.create!(email: "funding-#{SecureRandom.hex(5)}@example.com", password: 'password123',
      password_confirmation: 'password123', preferences: { 'preview_features_enabled' => true })
  end
  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(user: user, name: 'API Docs Key', key: key, scopes: %w[read_write], source: 'web')
  end
  let(:'X-Api-Key') { api_key.plain_key }
  let(:account) do
    family.accounts.create!(owner: user, name: 'Savings', currency: 'USD', balance: 2000,
      accountable: Depository.create!, goal_reconciled_cash: 2000, goal_cash_reconciled_at: Time.current)
  end
  let(:goal) do
    record = family.goals.new(name: 'Maintained cash', kind: 'maintained', target_amount: 5000, currency: 'USD', color: Goal::COLORS.first)
    record.goal_accounts.build(account: account, allocated_amount: 0)
    record.save!
    record
  end
  let(:salary_account) { family.accounts.create!(owner: user, name: 'Payroll receiving', currency: 'USD', balance: 0, accountable: Depository.create!) }
  let(:sample) { salary_account.entries.create!(name: 'Ordinary payroll', amount: -4000, currency: 'USD', date: family.local_date, entryable: Transaction.new) }
  let(:funding_plan) do
    record = family.goal_funding_plans.new(user: user)
    record.configure!(actor: user, attributes: { name: 'Payday reserves', backing_account_id: account.id, sample_entry_id: sample.id,
      minimum_salary: '4000', maximum_salary: '4000', effective_on: family.local_date.next_day }, rules: [ { goal_id: goal.id, amount: '150' } ])
    record
  end
  let(:funding_run) do
    funding_plan.runs.create!(source_entry_id: sample.id, source_fingerprint: GoalFundingRun.fingerprint(sample), source_date: sample.date,
      plan_revision: funding_plan.revision, rules_snapshot: funding_plan.rules.map(&:snapshot), status: 'needs_review')
  end
end

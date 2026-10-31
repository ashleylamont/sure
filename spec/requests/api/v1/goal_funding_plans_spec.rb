require 'swagger_helper'
require Rails.root.join('spec/support/goal_funding_api_context')

RSpec.describe 'Payday funding plans API', type: :request do
  include_context 'goal funding API'
  let(:id) { funding_plan.id }
  let(:body) { { plan: { name: 'Payday reserves', revision: funding_plan.revision, backing_account_id: account.id, sample_entry_id: sample.id, minimum_salary: '4000', maximum_salary: '4000', effective_on: family.local_date.next_day, rules: [ { goal_id: goal.id, amount: '150' } ] } } }
  path '/api/v1/goal_funding_plans' do
    get 'List your accessible plans' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      response '200', 'List your accessible plans' do
        schema({ type: :object, properties: { plans: { type: :array, items: { '$ref' => '#/components/schemas/GoalFundingPlanRecord' } } } })
        run_test!
      end
    end
    post 'Create a disabled plan' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      consumes 'application/json'
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[plan], properties: { plan: { '$ref' => '#/components/schemas/GoalFundingPlanWrite' } } }
      response '201', 'Create a disabled plan' do
        schema({ '$ref' => '#/components/schemas/GoalFundingPlanRecord' })
        run_test!
      end
    end
  end
  path '/api/v1/goal_funding_plans/{id}' do
    parameter name: :id, in: :path, type: :string, required: true
    get 'Read a plan' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      response '200', 'Read a plan' do
        schema({ '$ref' => '#/components/schemas/GoalFundingPlanRecord' })
        run_test!
      end
    end
    patch 'Update and disable a plan pending fresh confirmation' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      consumes 'application/json'
      parameter name: :body, in: :body, required: true, schema: { type: :object, properties: { plan: { allOf: [ { '$ref' => '#/components/schemas/GoalFundingPlanWrite' }, { type: :object, properties: { revision: { type: :integer } } } ] } } }
      response '200', 'Update and disable a plan pending fresh confirmation' do
        schema({ '$ref' => '#/components/schemas/GoalFundingPlanRecord' })
        run_test!
      end
    end
  end
  path '/api/v1/goal_funding_plans/{id}/preview' do
    parameter name: :id, in: :path, type: :string, required: true
    get 'Preview salary matches and cash availability' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      response '200', 'Preview salary matches and cash availability' do
        schema({ '$ref' => '#/components/schemas/GoalFundingPreview' })
        run_test!
      end
    end
  end
  path '/api/v1/goal_funding_plans/{id}/enable' do
    parameter name: :id, in: :path, type: :string, required: true
    post 'Explicitly enable future payday funding' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      consumes 'application/json'
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[preview_token confirm_salary_source], properties: { preview_token: { type: :string }, confirm_salary_source: { type: :boolean } } }
      let(:body) { { preview_token: funding_plan.preview[:preview_token], confirm_salary_source: true } }
      response '200', 'Explicitly enable future payday funding' do
        schema({ '$ref' => '#/components/schemas/GoalFundingPlanRecord' })
        run_test!
      end
    end
  end
  path '/api/v1/goal_funding_plans/{id}/disable' do
    parameter name: :id, in: :path, type: :string, required: true
    post 'Disable funding and preserve reservations' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      response '200', 'Disable funding and preserve reservations' do
        schema({ type: :object, properties: { id: { type: :string }, enabled: { type: :boolean } } })
        run_test!
      end
    end
  end
end

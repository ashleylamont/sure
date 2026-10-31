require 'swagger_helper'
require Rails.root.join('spec/support/goal_funding_api_context')

RSpec.describe 'Goals API', type: :request do
  include_context 'goal funding API'
  let(:id) { goal.id }
  let(:body) { { goal: { name: 'Emergency', kind: 'maintained', target_amount: '5000', version: goal.updated_at.iso8601(6), allocations: [ { account_id: account.id, amount: '100' } ], versions: { account.id => account.reload.goal_allocation_version }, idempotency_key: 'docs-create', reason: 'Reviewed opening cash' } } }
  path '/api/v1/goals' do
    get 'List visible goals and cash reservations' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      response '200', 'List visible goals and cash reservations' do
        schema({ type: :object, properties: { goals: { type: :array, items: { '$ref' => '#/components/schemas/GoalRecord' } }, accounts: { type: :array, items: { '$ref' => '#/components/schemas/GoalCashReservation' } } } })
        run_test!
      end
    end
    post 'Create a goal with explicit reservations' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      consumes 'application/json'
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[goal], properties: { goal: { '$ref' => '#/components/schemas/GoalWrite' } } }
      response '201', 'Create a goal with explicit reservations' do
        schema({ '$ref' => '#/components/schemas/GoalRecord' })
        run_test!
      end
    end
  end
  path '/api/v1/goals/{id}' do
    parameter name: :id, in: :path, type: :string, required: true
    get 'Read a visible goal' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      response '200', 'Read a visible goal' do
        schema({ '$ref' => '#/components/schemas/GoalRecord' })
        run_test!
      end
    end
    patch 'Update a goal using its version' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      consumes 'application/json'
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[goal], properties: { goal: { '$ref' => '#/components/schemas/GoalWrite' } } }
      response '200', 'Update a goal using its version' do
        schema({ '$ref' => '#/components/schemas/GoalRecord' })
        run_test!
      end
    end
    delete 'Delete a goal and retain its audit' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      consumes 'application/json'
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[version], properties: { version: { type: :string } } }
      let(:body) { { version: goal.updated_at.iso8601(6) } }
      response '204', 'Delete a goal and retain its audit' do
        run_test!
      end
    end
  end
end

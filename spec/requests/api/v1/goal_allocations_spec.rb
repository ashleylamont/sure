require 'swagger_helper'
require Rails.root.join('spec/support/goal_funding_api_context')

RSpec.describe 'Goal reservations API', type: :request do
  include_context 'goal funding API'
  let(:body) { { allocation: { adjustments: [ { account_id: account.id, goal_id: goal.id, mode: 'add', amount: '150' } ], versions: { account.id => account.reload.goal_allocation_version }, idempotency_key: 'docs-allocation', reason: 'Reviewed reserve' } } }
  path '/api/v1/goal_allocations' do
    post 'Apply atomic reservation changes' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      consumes 'application/json'
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[allocation], properties: { allocation: { '$ref' => '#/components/schemas/GoalAllocationRequest' } } }
      response '200', 'Apply atomic reservation changes' do
        schema({ type: :object })
        run_test!
      end
    end
  end
  path '/api/v1/goal_allocations/preview' do
    post 'Preview reservation changes without writes' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      consumes 'application/json'
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[allocation], properties: { allocation: { '$ref' => '#/components/schemas/GoalAllocationRequest' } } }
      response '200', 'Preview reservation changes without writes' do
        schema({ type: :object })
        run_test!
      end
    end
  end
end

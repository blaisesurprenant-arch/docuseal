# frozen_string_literal: true

class TransactionsDashboardController < ApplicationController
  load_and_authorize_resource :transaction, parent: false

  def index
    @transactions = @transactions.order(created_at: :desc)
    @pagy, @transactions = pagy_auto(@transactions)
  end
end

# frozen_string_literal: true

class TransactionsController < ApplicationController
  load_and_authorize_resource :transaction

  def show
    @envelopes = @transaction.envelopes.order(created_at: :desc)
  end

  def new; end

  def edit; end

  def create
    @transaction.account = current_account
    @transaction.created_by_user = current_user

    if @transaction.save
      redirect_to transaction_path(@transaction), notice: 'Transaction has been created.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @transaction.update(transaction_params)
      redirect_to transaction_path(@transaction), notice: 'Transaction has been updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @transaction.destroy!

    redirect_to transactions_path, notice: 'Transaction has been deleted.'
  end

  private

  def transaction_params
    params.require(:transaction).permit(:name, :status)
  end
end

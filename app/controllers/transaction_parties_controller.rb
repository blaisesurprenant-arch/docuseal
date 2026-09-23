# frozen_string_literal: true

class TransactionPartiesController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :transaction_party, through: :transaction

  NEW_ROLE_OPTION = 'new'

  def new; end

  def edit; end

  def create
    assign_role

    if @transaction_party.save
      redirect_to transaction_path(@transaction), notice: 'Party has been added.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    assign_role

    if @transaction_party.update(transaction_party_params.except(:role_id))
      redirect_to transaction_path(@transaction), notice: 'Party has been updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @transaction_party.destroy!

    redirect_to transaction_path(@transaction), notice: 'Party has been removed.'
  end

  private

  def assign_role
    if transaction_party_params[:role_id] == NEW_ROLE_OPTION
      @transaction_party.role = Roles.find_or_create_by_name(current_account, params[:new_role_name])
    else
      @transaction_party.role_id = transaction_party_params[:role_id]
    end

    @transaction_party.assign_attributes(transaction_party_params.except(:role_id))
  end

  def transaction_party_params
    params.require(:transaction_party).permit(
      :role_id, :party_type, :first_name, :last_name, :company_name,
      :signer_first_name, :signer_last_name, :signer_title, :email, :phone,
      :address_street, :address_city, :address_state, :address_zip,
      :mailing_address_street, :mailing_address_city, :mailing_address_state, :mailing_address_zip
    )
  end
end

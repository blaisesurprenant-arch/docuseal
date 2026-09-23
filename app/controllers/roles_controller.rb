# frozen_string_literal: true

class RolesController < ApplicationController
  load_and_authorize_resource :role, parent: false, only: %i[index new create update destroy]

  def index
    @roles = @roles.order(:name)
    @role = Role.new
  end

  def new; end

  def create
    @role.account = current_account

    if @role.save
      redirect_to settings_roles_path, notice: 'Role has been added.'
    else
      redirect_to settings_roles_path, alert: @role.errors.full_messages.to_sentence
    end
  end

  def update
    @role.update!(role_params)

    redirect_to settings_roles_path, notice: 'Role has been updated.'
  end

  def destroy
    @role.destroy!

    redirect_to settings_roles_path, notice: 'Role has been deleted.'
  rescue ActiveRecord::DeleteRestrictionError
    redirect_to settings_roles_path, alert: 'Role is still in use and cannot be deleted.'
  end

  private

  def role_params
    return params.require(:roles).require(@role.id.to_s).permit(:name) if params[:roles].present?

    params.require(:role).permit(:name)
  end
end

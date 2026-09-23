# frozen_string_literal: true

class EnvelopeRolesController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def show
    @role_names = @envelope.source_templates.flat_map { |t| t.submitters.pluck('name') }.uniq
    @existing_role_names = @transaction.transaction_parties.includes(:role).map { |p| p.role.name }
    @unresolved_role_names = @role_names - @existing_role_names
    @unresolved_roles = @unresolved_role_names.index_with do |name|
      Roles.find_or_create_by_name(@transaction.account, name)
    end
  end
end

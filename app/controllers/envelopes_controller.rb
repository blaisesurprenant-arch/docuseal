# frozen_string_literal: true

class EnvelopesController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def show; end

  def new
    @templates = Template.active.accessible_by(current_ability).order(:id)
  end

  def create
    template_ids = Array(params[:template_ids]).compact_blank

    if template_ids.blank?
      @templates = Template.active.accessible_by(current_ability).order(:id)
      flash.now[:alert] = 'Select at least one template.'
      return render :new, status: :unprocessable_content
    end

    @envelope.name = envelope_params[:name]

    ActiveRecord::Base.transaction do
      @envelope.save!

      template_ids.each_with_index do |template_id, index|
        @envelope.envelope_source_templates.create!(source_template_id: template_id, position: index)
      end
    end

    redirect_to transaction_envelope_roles_path(@transaction, @envelope)
  end

  private

  def envelope_params
    params.require(:envelope).permit(:name)
  end
end

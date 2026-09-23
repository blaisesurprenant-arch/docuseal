# frozen_string_literal: true

class EnvelopesController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def show; end

  def new
    @templates = Template.active.accessible_by(current_ability).order(:id)
  end

  def edit
    return block_editing_sent_envelope if @envelope.sent? || @envelope.voided?

    @templates = Template.active.accessible_by(current_ability).order(:id)
    @selected_template_ids = @envelope.envelope_source_templates.order(:position).pluck(:source_template_id)
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
      assign_source_templates(template_ids)
    end

    redirect_to transaction_envelope_roles_path(@transaction, @envelope)
  end

  def update
    return block_editing_sent_envelope if @envelope.sent? || @envelope.voided?

    template_ids = Array(params[:template_ids]).compact_blank

    if template_ids.blank?
      @templates = Template.active.accessible_by(current_ability).order(:id)
      @selected_template_ids = []
      flash.now[:alert] = 'Select at least one template.'
      return render :edit, status: :unprocessable_content
    end

    ActiveRecord::Base.transaction do
      @envelope.update!(name: envelope_params[:name], template: nil)
      @envelope.envelope_source_templates.destroy_all
      assign_source_templates(template_ids)
    end

    redirect_to transaction_envelope_roles_path(@transaction, @envelope)
  end

  private

  def block_editing_sent_envelope
    redirect_to transaction_path(@transaction), alert: 'Only draft envelopes can be edited.'
  end

  def assign_source_templates(template_ids)
    template_ids.each_with_index do |template_id, index|
      @envelope.envelope_source_templates.create!(source_template_id: template_id, position: index)
    end
  end

  def envelope_params
    params.require(:envelope).permit(:name)
  end
end

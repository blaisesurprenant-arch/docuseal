# frozen_string_literal: true

RSpec.describe Envelopes::Merge do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:transaction) { create(:transaction, account:) }
  let(:buyer_role) { create(:role, account:, name: 'Buyer') }
  let(:seller_role) { create(:role, account:, name: 'Seller') }

  def template_with_role_names(*names)
    template = create(:template, account:, author:, submitter_count: names.size)
    template.submitters.each_with_index { |s, i| s['name'] = names[i] }
    template.save!
    template
  end

  it 'combines two templates into one saved template' do
    template_a = template_with_role_names('Buyer')
    template_b = template_with_role_names('Seller')
    envelope = create(:envelope, parent_transaction: transaction)
    envelope.envelope_source_templates.create!(source_template: template_a, position: 0)
    envelope.envelope_source_templates.create!(source_template: template_b, position: 1)

    merged = Envelopes::Merge.call(envelope:, author:)

    expect(merged).to be_persisted
    expect(merged.fields.size).to eq(template_a.fields.size + template_b.fields.size)
    expect(merged.schema.size).to eq(template_a.schema.size + template_b.schema.size)
  end

  it 'unifies same-named roles into a single submitter slot' do
    template_a = template_with_role_names('Buyer', 'Seller')
    template_b = template_with_role_names('Buyer')
    envelope = create(:envelope, parent_transaction: transaction)
    envelope.envelope_source_templates.create!(source_template: template_a, position: 0)
    envelope.envelope_source_templates.create!(source_template: template_b, position: 1)

    merged = Envelopes::Merge.call(envelope:, author:)

    expect(merged.submitters.map { |s| s['name'] }).to contain_exactly('Buyer', 'Seller')

    buyer_uuid = merged.submitters.find { |s| s['name'] == 'Buyer' }['uuid']
    buyer_field_uuids_from_b = merged.fields.select { |f| f['submitter_uuid'] == buyer_uuid }

    expect(buyer_field_uuids_from_b.size).to eq(template_a.fields.count { |f|
      f['submitter_uuid'] == template_a.submitters.find { |s| s['name'] == 'Buyer' }['uuid']
    } + template_b.fields.size)
  end

  it 'does not corrupt attachment references across sources' do
    template_a = template_with_role_names('Buyer')
    template_b = template_with_role_names('Seller')
    envelope = create(:envelope, parent_transaction: transaction)
    envelope.envelope_source_templates.create!(source_template: template_a, position: 0)
    envelope.envelope_source_templates.create!(source_template: template_b, position: 1)

    merged = Envelopes::Merge.call(envelope:, author:)

    expect(merged.schema_documents.count).to eq(template_a.schema_documents.count + template_b.schema_documents.count)

    merged.schema.each do |schema_item|
      expect(merged.schema_documents.map(&:uuid)).to include(schema_item['attachment_uuid'])
    end
  end

  it 'sets envelope.template to the merged template without saving the envelope' do
    template_a = template_with_role_names('Buyer')
    envelope = create(:envelope, parent_transaction: transaction)
    envelope.envelope_source_templates.create!(source_template: template_a, position: 0)

    Envelopes::Merge.call(envelope:, author:)

    expect(envelope.template).to be_present
    expect(envelope.reload.template_id).to be_nil
  end
end

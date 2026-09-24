# frozen_string_literal: true

RSpec.describe 'Envelope Build - Choose Parties and Send' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:buyer_role) { create(:role, account:, name: 'Buyer') }
  let!(:seller_role) { create(:role, account:, name: 'Seller') }
  let!(:buyer) { create(:transaction_party, parent_transaction: transaction, role: buyer_role, first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com') }
  let!(:seller) { create(:transaction_party, parent_transaction: transaction, role: seller_role, first_name: 'Sam', last_name: 'Lee', email: 'sam@example.com') }

  let!(:template) do
    t = create(:template, account:, author: user, submitter_count: 2)
    t.submitters[0]['name'] = 'Buyer'
    t.submitters[1]['name'] = 'Seller'
    t.save!
    t
  end

  let!(:envelope) do
    e = create(:envelope, parent_transaction: transaction, name: 'Move-In Packet')
    e.envelope_source_templates.create!(source_template: template, position: 0)
    e
  end

  before { sign_in(user) }

  it 'defaults to including every resolved party' do
    visit transaction_envelope_send_path(transaction, envelope)

    expect(page).to have_field('party_ids[]', checked: true, count: 2)
  end

  it 'sends the envelope to the checked parties, creating a merged template and submission' do
    expect do
      visit transaction_envelope_send_path(transaction, envelope)
      uncheck "party_ids_#{seller.id}"
      click_button 'Send'
    end.to change(Submission, :count).by(1).and change(Template, :count).by(1)

    envelope.reload

    expect(envelope).to be_sent
    expect(envelope.transaction_parties).to eq([buyer])
    expect(envelope.submission.submitters.count).to eq(1)
    expect(envelope.submission.submitters.first.email).to eq('jane@example.com')
  end

  it 'defaults to sequential signing order' do
    expect do
      visit transaction_envelope_send_path(transaction, envelope)
      click_button 'Send'
    end.to change(Submission, :count).by(1)

    expect(envelope.reload.submission.submitters_order).to eq('preserved')
  end

  it 'sends in parallel when parallel signing order is chosen' do
    expect do
      visit transaction_envelope_send_path(transaction, envelope)
      choose 'Parallel'
      click_button 'Send'
    end.to change(Submission, :count).by(1)

    expect(envelope.reload.submission.submitters_order).to eq('random')
    expect(envelope).to be_signing_order_parallel
  end

  it 'marks a CC-role submitter as a viewer end to end' do
    create(:role, account:, name: 'Notary', is_viewer: true)
    notary = create(:transaction_party, parent_transaction: transaction, role: Role.find_by(name: 'Notary'),
                                        first_name: 'Pat', last_name: 'Reed', email: 'pat@example.com')
    notary_template = create(:template, account:, author: user, submitter_count: 1)
    notary_template.submitters[0]['name'] = 'Notary'
    notary_template.save!
    notary_envelope = create(:envelope, parent_transaction: transaction, name: 'Notarized Packet')
    notary_envelope.envelope_source_templates.create!(source_template: notary_template, position: 0)

    visit transaction_envelope_send_path(transaction, notary_envelope)
    click_button 'Send'

    notary_submitter = notary_envelope.reload.submission.submitters.find_by(email: notary.email)
    expect(notary_submitter).to be_viewer
  end

  it 'sets the submission expiration date when provided' do
    visit transaction_envelope_send_path(transaction, envelope)
    fill_in 'envelope[expire_at]', with: '2027-01-15'
    click_button 'Send'

    expect(envelope.reload.submission.expire_at.to_date).to eq(Date.new(2027, 1, 15))
  end

  it 'leaves the submission without an expiration date when left blank' do
    visit transaction_envelope_send_path(transaction, envelope)
    click_button 'Send'

    expect(envelope.reload.submission.expire_at).to be_nil
  end

  it "keys prefilled contact info by the field's uuid, not its name (submitter.values contract)" do
    email_field_uuid = SecureRandom.uuid
    template.fields << {
      'uuid' => email_field_uuid, 'submitter_uuid' => template.submitters[0]['uuid'],
      'name' => 'Email', 'type' => 'text', 'required' => false, 'areas' => []
    }
    template.save!

    visit transaction_envelope_send_path(transaction, envelope)
    click_button 'Send'

    buyer_submitter = envelope.reload.submission.submitters.find_by(email: 'jane@example.com')
    merged_field_uuid = envelope.template.fields.find { |f| f['name'] == 'Email' }['uuid']

    expect(buyer_submitter.values[merged_field_uuid]).to eq('jane@example.com')
  end

  it 'lets the sender fill in prefillable fields for the whole document before sending' do
    price_field_uuid = SecureRandom.uuid
    template.fields << {
      'uuid' => price_field_uuid, 'submitter_uuid' => template.submitters[0]['uuid'],
      'name' => 'Purchase Price', 'type' => 'text', 'required' => false, 'areas' => [], 'prefillable' => true
    }
    template.save!

    visit transaction_envelope_send_path(transaction, envelope)

    expect(page).to have_field('Purchase Price')

    fill_in 'Purchase Price', with: '450000'
    click_button 'Send'

    buyer_submitter = envelope.reload.submission.submitters.find_by(email: 'jane@example.com')
    merged_field_uuid = envelope.template.fields.find { |f| f['name'] == 'Purchase Price' }['uuid']

    expect(buyer_submitter.values[merged_field_uuid]).to eq('450000')
  end

  it 'actually notifies the signer -- enqueues the invitation email job on send' do
    expect do
      visit transaction_envelope_send_path(transaction, envelope)
      uncheck "party_ids_#{seller.id}"
      click_button 'Send'
    end.to change(SendSubmitterInvitationEmailJob.jobs, :size).by(1)

    buyer_submitter = envelope.reload.submission.submitters.find_by(email: 'jane@example.com')
    expect(SendSubmitterInvitationEmailJob.jobs.last['args']).to eq([{ 'submitter_id' => buyer_submitter.id }])
  end

  it "blocks sending with a clear error instead of silently dropping a co-party who shares a role" do
    co_buyer = create(:transaction_party, parent_transaction: transaction, role: buyer_role, first_name: 'Jo',
                                          last_name: 'Doe', email: 'jo@example.com')

    visit transaction_envelope_send_path(transaction, envelope)
    uncheck "party_ids_#{seller.id}"

    expect do
      click_button 'Send'
    end.not_to change(Submission, :count)

    expect(page).to have_content('Buyer')
    expect(page).to have_content('more than one party')
    expect(envelope.reload).to be_draft
    expect(TransactionParty.exists?(co_buyer.id)).to be true
  end

  it 'redirects back to role resolution instead of showing the send page when a role is unresolved' do
    unresolved_template = create(:template, account:, author: user, submitter_count: 1)
    unresolved_template.submitters[0]['name'] = 'Agent'
    unresolved_template.save!
    unresolved_envelope = create(:envelope, parent_transaction: transaction, name: 'Missing Role Packet')
    unresolved_envelope.envelope_source_templates.create!(source_template: unresolved_template, position: 0)

    visit transaction_envelope_send_path(transaction, unresolved_envelope)

    expect(page).to have_current_path(transaction_envelope_roles_path(transaction, unresolved_envelope))
    expect(page).to have_content('Agent')
  end


  it 'blocks sending with zero parties included' do
    visit transaction_envelope_send_path(transaction, envelope)
    uncheck "party_ids_#{buyer.id}"
    uncheck "party_ids_#{seller.id}"

    expect do
      click_button 'Send'
    end.not_to change(Submission, :count)

    expect(page).to have_content('Select at least one party')
    expect(envelope.reload).to be_draft
  end
end

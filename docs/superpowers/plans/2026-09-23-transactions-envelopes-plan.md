# Transactions & Envelopes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Transactions/Envelopes system to this DocuSeal fork: transactions represent a deal (e.g. "123 E Main St Unit A") with parties assigned global roles; envelopes bundle selected templates into one merged template, sent as a single signing session to a chosen subset of the transaction's parties.

**Architecture:** New models (`Role`, `Transaction`, `TransactionParty`, `Envelope`, `EnvelopeSourceTemplate`, `EnvelopePart`) sit alongside the existing `Template`/`Submission` system untouched. A new `Envelopes::Merge` service clones and combines selected templates' documents/fields/schema into one new `Template` record (reusing `Templates::Clone`/`Templates::CloneAttachments`), from which a normal `Submission` is created exactly as DocuSeal does today. UI follows the existing dashboard-toggle pattern (`Templates`/`Submissions`/now `Transactions`) and the existing settings-CRUD pattern (for the global Roles list).

**Tech Stack:** Ruby on Rails 8.0.1, PostgreSQL, CanCanCan (authorization), Devise (auth), RSpec + Capybara/Cuprite (system specs), FactoryBot, Tailwind/DaisyUI + Turbo/Stimulus-less custom elements (`toggle-attribute`, `toggle-cookies`).

**Spec:** `docs/superpowers/specs/2026-09-23-transactions-envelopes-design.md`

## Global Constraints

- All new models are account-scoped (`account_id` or scoped through an account-scoped parent) — never global across accounts, matching every existing model in this codebase.
- Every new controller uses CanCanCan (`load_and_authorize_resource`) exactly like existing controllers — no hand-rolled authorization checks.
- No changes to `Template`, `Submission`, `Submitter`, or any file under `lib/templates/` or the signing/PDF pipeline — envelopes only build inputs to that pipeline (per spec's "Out of scope").
- New user-facing strings are hardcoded English in the view (not added to `config/locales/i18n.yml`), per this fork's own established convention for internal-only features rather than touching all 8 locale blocks.
- Money/PII fields (party contact info) are plain-text columns like the rest of this codebase's contact fields (e.g. `Submitter#email`) — no new encryption layer introduced (matches existing pattern, out of scope to change).
- Follows this codebase's existing RSpec conventions: system specs (Capybara, `sign_in(user)` helper) for user-facing flows, `spec/lib/**/*_spec.rb` for service objects — no `spec/models` directory is used in this codebase and this plan does not introduce one.

## Review Focus

- **A template with zero role placeholders (a single-signer doc with no named roles)** — the role-resolution step must not block adding it to an envelope; it should resolve trivially (Task 11).
- **Two selected templates whose role names are spelled differently but mean the same person (e.g. "Buyer" vs "buyer")** — role matching must not silently treat these as different parties or crash; Task 9's merge/role-matching does exact, case-sensitive matching, and Task 11's resolution step is the safety net a human uses to fix this rather than the system guessing.
- **Sending an envelope with zero parties actually included** (all unchecked in the party-inclusion step) — must be blocked with a validation error, not silently create a submission nobody can access (Task 12).
- **A business-type party with a blank signer name/title** — since a business party still needs a human signer, `signer_first_name`/`signer_last_name` must be required when `party_type` is `business`, not just company name (Task 6).
- **Deleting a `Role` that's still referenced by an existing `TransactionParty`** — must be blocked (not cascade-delete parties or leave orphaned foreign keys), since a party's role assignment is load-bearing data, not incidental (Task 2).

---

## Task 1: Role model + migration

**Files:**
- Create: `db/migrate/20260923000001_create_roles.rb`
- Create: `app/models/role.rb`
- Create: `spec/factories/roles.rb`
- Modify: `app/models/account.rb` (add `has_many :roles`)
- Modify: `lib/ability.rb` (add `can :manage, Role, account_id: user.account_id`)

**Interfaces:**
- Produces: `Role` — `belongs_to :account`, columns `name:string`, `account_id:bigint`. Validates `name` presence and uniqueness scoped to `account_id` (case-insensitive).

- [ ] **Step 1: Write the failing test**

Create `spec/lib/roles_model_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Role do
  let(:account) { create(:account) }

  it 'is valid with a unique name for the account' do
    role = build(:role, account:, name: 'Buyer')

    expect(role).to be_valid
  end

  it 'is invalid without a name' do
    role = build(:role, account:, name: '')

    expect(role).not_to be_valid
  end

  it 'is invalid with a duplicate name (case-insensitive) within the same account' do
    create(:role, account:, name: 'Buyer')
    role = build(:role, account:, name: 'buyer')

    expect(role).not_to be_valid
  end

  it 'allows the same name in a different account' do
    create(:role, account:, name: 'Buyer')
    other_account = create(:account)
    role = build(:role, account: other_account, name: 'Buyer')

    expect(role).to be_valid
  end

  it 'prevents destroying a role still referenced by a transaction party' do
    role = create(:role, account:)
    create(:transaction_party, role:)

    expect { role.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/roles_model_spec.rb`
Expected: FAIL — `uninitialized constant Role` (and later, once the model exists, `uninitialized constant Account.roles`/factory errors), since nothing has been created yet. This test also references `:transaction_party` factory, which doesn't exist until Task 6 — for now, comment out the last `it` block with a `# TODO(task-6)` marker... actually **do not** leave TODOs per plan convention. Instead, skip that last example for now:

Replace the last example with:

```ruby
  it 'prevents destroying a role still referenced by a transaction party', skip: 'enabled in Task 6 once TransactionParty exists' do
    role = create(:role, account:)
    create(:transaction_party, role:)

    expect { role.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
```

- [ ] **Step 3: Write the migration**

```ruby
# frozen_string_literal: true

class CreateRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :roles do |t|
      t.string :name, null: false
      t.references :account, null: false, foreign_key: true, index: true

      t.timestamps
    end

    add_index :roles, %i[account_id name], unique: true
  end
end
```

Run: `bundle exec rails db:migrate`

- [ ] **Step 4: Write the model**

```ruby
# frozen_string_literal: true

class Role < ApplicationRecord
  belongs_to :account

  has_many :transaction_parties, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :name, uniqueness: { scope: :account_id, case_sensitive: false }
end
```

- [ ] **Step 5: Add the account association**

In `app/models/account.rb`, alongside the existing `has_many :template_folders, dependent: :destroy` line, add:

```ruby
  has_many :roles, dependent: :destroy
```

- [ ] **Step 6: Add the ability rule**

In `lib/ability.rb`, alongside `can :manage, TemplateFolder, account_id: user.account_id`, add:

```ruby
    can :manage, Role, account_id: user.account_id
```

- [ ] **Step 7: Write the factory**

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :role do
    account

    sequence(:name) { |n| "Role #{n}" }
  end
end
```

- [ ] **Step 8: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/roles_model_spec.rb`
Expected: PASS (4 examples), 1 pending (the skipped destroy-restriction example)

- [ ] **Step 9: Commit**

```bash
git add db/migrate/20260923000001_create_roles.rb db/schema.rb app/models/role.rb app/models/account.rb lib/ability.rb spec/factories/roles.rb spec/lib/roles_model_spec.rb
git commit -m "Add Role model for shared transaction/template role vocabulary"
```

---

## Task 2: Roles settings CRUD (global list management)

**Files:**
- Create: `app/controllers/roles_controller.rb`
- Create: `app/views/roles/index.html.erb`
- Create: `app/views/roles/_form.html.erb`
- Create: `lib/roles.rb`
- Create: `spec/system/roles_settings_spec.rb`
- Modify: `config/routes.rb`

**Interfaces:**
- Consumes: `Role` model (Task 1)
- Produces: `Roles.find_or_create_by_name(account, name)` — module function other tasks (7, 9) call to resolve/append a role by name without duplicating the find-or-create logic.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe 'Roles Settings' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }

  before { sign_in(user) }

  it 'shows an empty state when there are no roles' do
    visit settings_roles_path

    expect(page).to have_content('Roles')
    expect(page).to have_field('role[name]')
  end

  it 'creates a role' do
    visit settings_roles_path

    fill_in 'role[name]', with: 'Buyer'

    expect do
      click_button 'Add Role'
    end.to change(Role, :count).by(1)

    expect(account.roles.last.name).to eq('Buyer')
    expect(page).to have_content('Buyer')
  end

  it 'rejects a duplicate role name' do
    create(:role, account:, name: 'Buyer')

    visit settings_roles_path
    fill_in 'role[name]', with: 'Buyer'

    expect do
      click_button 'Add Role'
    end.not_to change(Role, :count)

    expect(page).to have_content('has already been taken')
  end

  it 'renames a role' do
    role = create(:role, account:, name: 'Buyer')

    visit settings_roles_path
    within "#role_#{role.id}" do
      fill_in "roles[#{role.id}][name]", with: 'Purchaser'
      click_button 'Save'
    end

    expect(role.reload.name).to eq('Purchaser')
  end

  it 'deletes an unused role' do
    create(:role, account:, name: 'Buyer')

    visit settings_roles_path

    expect do
      accept_confirm { click_button 'Delete' }
    end.to change(Role, :count).by(-1)
  end

  it 'shows an error instead of deleting a role still in use' do
    role = create(:role, account:, name: 'Buyer')
    transaction = create(:transaction, account:)
    create(:transaction_party, transaction:, role:)

    visit settings_roles_path

    expect do
      accept_confirm { click_button 'Delete' }
    end.not_to change(Role, :count)

    expect(page).to have_content('still in use')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/roles_settings_spec.rb`
Expected: FAIL — `undefined method 'settings_roles_path'` (route doesn't exist yet). The last test also needs `:transaction`/`:transaction_party` factories (Tasks 3, 6) — mark it pending for now the same way as Task 1:

```ruby
  it 'shows an error instead of deleting a role still in use', skip: 'enabled once Transaction/TransactionParty exist (Tasks 3, 6)' do
```

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, inside the existing `scope '/settings', as: :settings do ... end` block, alongside `resources :webhooks, ...`, add:

```ruby
    resources :roles, only: %i[index new create update destroy]
```

- [ ] **Step 4: Write the lib helper module**

```ruby
# frozen_string_literal: true

module Roles
  module_function

  def find_or_create_by_name(account, name)
    return nil if name.blank?

    account.roles.where('lower(name) = ?', name.to_s.downcase).first ||
      account.roles.create!(name: name.to_s.strip)
  end
end
```

- [ ] **Step 5: Write the controller**

```ruby
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
    params.require(:role).permit(:name)
  end
end
```

- [ ] **Step 6: Write the views**

`app/views/roles/index.html.erb`:

```erb
<h1 class="text-2xl md:text-3xl font-bold mb-4">Roles</h1>

<div class="space-y-2 mb-6">
  <% @roles.each do |role| %>
    <div id="role_<%= role.id %>" class="flex items-center gap-2">
      <%= form_for role, url: settings_role_path(role), method: :patch, html: { class: 'flex items-center gap-2' } do |f| %>
        <%= f.text_field :name, name: "roles[#{role.id}][name]", value: role.name, class: 'base-input' %>
        <%= f.submit 'Save', class: 'btn btn-neutral btn-sm' %>
      <% end %>
      <%= button_to 'Delete', settings_role_path(role), method: :delete, form: { data: { turbo_confirm: 'Are you sure?' } }, class: 'btn btn-outline btn-sm' %>
    </div>
  <% end %>
</div>

<%= render 'form', role: @role %>
```

`app/views/roles/_form.html.erb`:

```erb
<%= form_for role, url: settings_roles_path, html: { class: 'flex items-center gap-2' } do |f| %>
  <%= f.text_field :name, class: 'base-input', placeholder: 'e.g. Buyer' %>
  <%= f.submit 'Add Role', class: 'btn btn-neutral btn-sm' %>
<% end %>
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bundle exec rspec spec/system/roles_settings_spec.rb`
Expected: PASS (5 examples), 1 pending

- [ ] **Step 8: Commit**

```bash
git add app/controllers/roles_controller.rb app/views/roles lib/roles.rb config/routes.rb spec/system/roles_settings_spec.rb
git commit -m "Add global Roles settings CRUD page"
```

---

## Task 3: Transaction model + migration

**Files:**
- Create: `db/migrate/20260923000002_create_transactions.rb`
- Create: `app/models/transaction.rb`
- Create: `spec/factories/transactions.rb`
- Modify: `app/models/account.rb`
- Modify: `app/models/user.rb` (add `has_many :transactions, foreign_key: :created_by_user_id` — only if `User` already has similar `created_by_user_id` reverse associations; otherwise skip and rely on the `belongs_to :created_by_user` side only, matching how `Submission#created_by_user` works today with no reverse `has_many` on `User`)
- Modify: `lib/ability.rb`

**Interfaces:**
- Produces: `Transaction` — `belongs_to :account`, `belongs_to :created_by_user, class_name: 'User', optional: true`, `enum :status, { active: 0, closed: 1 }`, `has_many :transaction_parties, dependent: :destroy`, `has_many :envelopes, dependent: :destroy`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe Transaction do
  let(:account) { create(:account) }

  it 'is valid with a name' do
    transaction = build(:transaction, account:, name: '123 E Main St Unit A')

    expect(transaction).to be_valid
  end

  it 'is invalid without a name' do
    transaction = build(:transaction, account:, name: '')

    expect(transaction).not_to be_valid
  end

  it 'defaults to active status' do
    transaction = create(:transaction, account:)

    expect(transaction).to be_active
  end
end
```

Save as `spec/lib/transaction_model_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/transaction_model_spec.rb`
Expected: FAIL — `uninitialized constant Transaction`

- [ ] **Step 3: Write the migration**

```ruby
# frozen_string_literal: true

class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.string :name, null: false
      t.integer :status, null: false, default: 0
      t.references :account, null: false, foreign_key: true, index: true
      t.references :created_by_user, null: true, foreign_key: { to_table: :users }, index: true

      t.timestamps
    end
  end
end
```

Run: `bundle exec rails db:migrate`

- [ ] **Step 4: Write the model**

```ruby
# frozen_string_literal: true

class Transaction < ApplicationRecord
  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: true

  has_many :transaction_parties, dependent: :destroy
  has_many :envelopes, dependent: :destroy

  enum :status, { active: 0, closed: 1 }

  validates :name, presence: true
end
```

- [ ] **Step 5: Add the account association**

In `app/models/account.rb`:

```ruby
  has_many :transactions, dependent: :destroy
```

- [ ] **Step 6: Add the ability rule**

In `lib/ability.rb`:

```ruby
    can :manage, Transaction, account_id: user.account_id
```

- [ ] **Step 7: Write the factory**

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :transaction do
    account

    sequence(:name) { |n| "123 Test St Unit #{n}" }
  end
end
```

- [ ] **Step 8: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/transaction_model_spec.rb`
Expected: PASS (3 examples)

- [ ] **Step 9: Commit**

```bash
git add db/migrate/20260923000002_create_transactions.rb db/schema.rb app/models/transaction.rb app/models/account.rb lib/ability.rb spec/factories/transactions.rb spec/lib/transaction_model_spec.rb
git commit -m "Add Transaction model"
```

---

## Task 4: Transactions dashboard tab + list + detail shell

**Files:**
- Create: `app/controllers/transactions_dashboard_controller.rb`
- Create: `app/controllers/transactions_controller.rb`
- Create: `app/views/transactions_dashboard/index.html.erb`
- Create: `app/views/transactions/new.html.erb`
- Create: `app/views/transactions/_form.html.erb`
- Create: `app/views/transactions/show.html.erb`
- Create: `app/views/transactions/edit.html.erb`
- Create: `spec/system/transactions_dashboard_spec.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/dashboard_controller.rb`
- Modify: `app/views/dashboard/_toggle_view.html.erb`

**Interfaces:**
- Consumes: `Transaction` (Task 3)
- Produces: `transactions_path`, `new_transaction_path`, `transaction_path(t)`, `edit_transaction_path(t)` route helpers other tasks (5, 14) build on.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe 'Transactions Dashboard' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }

  before { sign_in(user) }

  it 'shows the transactions tab as a peer to templates/submissions' do
    visit root_path

    expect(page).to have_css('form#templates_submissions_toggle toggle-cookies[data-value="transactions"]')
  end

  it 'shows an empty state with no transactions' do
    visit transactions_path

    expect(page).to have_content('Transactions')
    expect(page).to have_link('New Transaction')
  end

  it 'lists existing transactions' do
    transaction = create(:transaction, account:, name: '123 E Main St Unit A')

    visit transactions_path

    expect(page).to have_link('123 E Main St Unit A', href: transaction_path(transaction))
  end

  it 'creates a transaction' do
    visit transactions_path
    click_link 'New Transaction'

    fill_in 'transaction[name]', with: '123 E Main St Unit A'

    expect do
      click_button 'Create Transaction'
    end.to change(Transaction, :count).by(1)

    expect(page).to have_content('123 E Main St Unit A')
  end
end
```

Save as `spec/system/transactions_dashboard_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/transactions_dashboard_spec.rb`
Expected: FAIL — `undefined method 'transactions_path'`

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, alongside `resources :templates, only: %i[index], controller: 'templates_dashboard'`, add:

```ruby
  resources :transactions, only: %i[index], controller: 'transactions_dashboard'
  resources :transactions, only: %i[new create edit update show destroy]
```

Place both lines directly above the existing `resources :templates, only: %i[new create edit update show destroy] do ... end` block (order matters for the `only: %i[index]` dashboard route to not be shadowed, mirroring how the templates lines are ordered today).

- [ ] **Step 4: Update the dashboard controller**

In `app/controllers/dashboard_controller.rb`, replace:

```ruby
  def index
    if cookies.permanent[:dashboard_view] == 'submissions'
      SubmissionsDashboardController.dispatch(:index, request, response)
    else
      TemplatesDashboardController.dispatch(:index, request, response)
    end
  end
```

with:

```ruby
  def index
    case cookies.permanent[:dashboard_view]
    when 'submissions'
      SubmissionsDashboardController.dispatch(:index, request, response)
    when 'transactions'
      TransactionsDashboardController.dispatch(:index, request, response)
    else
      TemplatesDashboardController.dispatch(:index, request, response)
    end
  end
```

- [ ] **Step 5: Add the third toggle button**

In `app/views/dashboard/_toggle_view.html.erb`, add a third `toggle-cookies` button after the `submissions` one, following the exact same structure:

```erb
  <toggle-cookies data-value="transactions" data-key="dashboard_view" class="tooltip tooltip-top tooltip-no-touch" data-tip="Transactions">
    <button class="<%= local_assigns[:selected] == 'transactions' ? 'btn btn-neutral !rounded-lg btn-square !p-0 hover:text-neutral-300 !btn-sm !h-8 !w-9' : 'btn !border !rounded-lg btn-square !p-0 !btn-sm !h-8 !w-9 disabled:btn-neutral' %>">
      <%= svg_icon('building', class: 'w-6 h-6 stroke-2') %>
    </button>
  </toggle-cookies>
```

Check `app/views/icons` has a `building` partial (`ls app/views/icons | grep building`); if it doesn't exist, use `svg_icon('folder', ...)` instead, which is confirmed to exist (used elsewhere in this codebase for folder-like entities).

- [ ] **Step 6: Write the dashboard (list) controller**

```ruby
# frozen_string_literal: true

class TransactionsDashboardController < ApplicationController
  load_and_authorize_resource :transaction, parent: false

  def index
    @transactions = @transactions.order(created_at: :desc)
    @pagy, @transactions = pagy_auto(@transactions)
  end
end
```

- [ ] **Step 7: Write the CRUD controller**

```ruby
# frozen_string_literal: true

class TransactionsController < ApplicationController
  load_and_authorize_resource :transaction

  def show; end

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
```

- [ ] **Step 8: Write the views**

`app/views/transactions_dashboard/index.html.erb`:

```erb
<div class="flex justify-between items-center mb-4">
  <div class="flex items-center">
    <div class="mr-2"><%= render 'dashboard/toggle_view', selected: 'transactions' %></div>
    <h1 class="text-2xl md:text-3xl font-bold">Transactions</h1>
  </div>
  <%= link_to 'New Transaction', new_transaction_path, class: 'btn btn-neutral btn-sm' %>
</div>

<div class="space-y-2">
  <% @transactions.each do |transaction| %>
    <%= link_to transaction.name, transaction_path(transaction), class: 'block base-input' %>
  <% end %>
</div>
```

`app/views/transactions/_form.html.erb`:

```erb
<%= form_for transaction do |f| %>
  <div class="form-control mb-4">
    <%= f.label :name, 'Transaction Name' %>
    <%= f.text_field :name, class: 'base-input', placeholder: 'e.g. 123 E Main St Unit A' %>
  </div>
  <%= f.submit transaction.new_record? ? 'Create Transaction' : 'Save', class: 'btn btn-neutral' %>
<% end %>
```

`app/views/transactions/new.html.erb`:

```erb
<h1 class="text-2xl md:text-3xl font-bold mb-4">New Transaction</h1>
<%= render 'form', transaction: @transaction %>
```

`app/views/transactions/edit.html.erb`:

```erb
<h1 class="text-2xl md:text-3xl font-bold mb-4">Edit Transaction</h1>
<%= render 'form', transaction: @transaction %>
```

`app/views/transactions/show.html.erb`:

```erb
<h1 class="text-2xl md:text-3xl font-bold mb-4"><%= @transaction.name %></h1>
<p class="text-sm mb-4"><%= link_to 'Edit', edit_transaction_path(@transaction) %></p>
```

(Parties and envelopes sections are added to this view in Tasks 7 and 14.)

- [ ] **Step 9: Run test to verify it passes**

Run: `bundle exec rspec spec/system/transactions_dashboard_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 10: Commit**

```bash
git add app/controllers/transactions_dashboard_controller.rb app/controllers/transactions_controller.rb app/views/transactions_dashboard app/views/transactions config/routes.rb app/controllers/dashboard_controller.rb app/views/dashboard/_toggle_view.html.erb spec/system/transactions_dashboard_spec.rb
git commit -m "Add Transactions dashboard tab, list, and basic CRUD"
```

---

## Task 5: TransactionParty model + migration

**Files:**
- Create: `db/migrate/20260923000003_create_transaction_parties.rb`
- Create: `app/models/transaction_party.rb`
- Create: `spec/factories/transaction_parties.rb`
- Modify: `lib/ability.rb`

**Interfaces:**
- Consumes: `Transaction` (Task 3), `Role` (Task 1)
- Produces: `TransactionParty` — `belongs_to :transaction`, `belongs_to :role`, `enum :party_type, { individual: 0, business: 1 }`, `display_name` instance method other tasks (7, 10-13) use to render/label a party regardless of type.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe TransactionParty do
  let(:account) { create(:account) }
  let(:transaction) { create(:transaction, account:) }
  let(:role) { create(:role, account:) }

  it 'is valid as an individual with a name and email' do
    party = build(:transaction_party, transaction:, role:, party_type: 'individual',
                                      first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com')

    expect(party).to be_valid
  end

  it 'requires first and last name for an individual' do
    party = build(:transaction_party, transaction:, role:, party_type: 'individual', first_name: '', last_name: '')

    expect(party).not_to be_valid
    expect(party.errors[:first_name]).to be_present
    expect(party.errors[:last_name]).to be_present
  end

  it 'is valid as a business with a company name and a signer name/title' do
    party = build(:transaction_party, transaction:, role:, party_type: 'business',
                                      company_name: 'Acme LLC', signer_first_name: 'Jane',
                                      signer_last_name: 'Doe', signer_title: 'Managing Member',
                                      email: 'jane@acme.com')

    expect(party).to be_valid
  end

  it 'requires company name, signer name, and signer title for a business' do
    party = build(:transaction_party, transaction:, role:, party_type: 'business',
                                      company_name: '', signer_first_name: '', signer_last_name: '',
                                      signer_title: '')

    expect(party).not_to be_valid
    expect(party.errors[:company_name]).to be_present
    expect(party.errors[:signer_first_name]).to be_present
    expect(party.errors[:signer_last_name]).to be_present
    expect(party.errors[:signer_title]).to be_present
  end

  it 'builds a display name for an individual' do
    party = build(:transaction_party, transaction:, role:, party_type: 'individual',
                                      first_name: 'Jane', last_name: 'Doe')

    expect(party.display_name).to eq('Jane Doe')
  end

  it 'builds a display name for a business' do
    party = build(:transaction_party, transaction:, role:, party_type: 'business',
                                      company_name: 'Acme LLC', signer_first_name: 'Jane', signer_last_name: 'Doe')

    expect(party.display_name).to eq('Acme LLC (Jane Doe)')
  end
end
```

Save as `spec/lib/transaction_party_model_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/transaction_party_model_spec.rb`
Expected: FAIL — `uninitialized constant TransactionParty`

- [ ] **Step 3: Write the migration**

```ruby
# frozen_string_literal: true

class CreateTransactionParties < ActiveRecord::Migration[8.0]
  def change
    create_table :transaction_parties do |t|
      t.references :transaction, null: false, foreign_key: true, index: true
      t.references :role, null: false, foreign_key: true, index: true

      t.integer :party_type, null: false, default: 0

      t.string :first_name
      t.string :last_name
      t.string :company_name
      t.string :signer_first_name
      t.string :signer_last_name
      t.string :signer_title

      t.string :email
      t.string :phone

      t.string :address_street
      t.string :address_city
      t.string :address_state
      t.string :address_zip

      t.string :mailing_address_street
      t.string :mailing_address_city
      t.string :mailing_address_state
      t.string :mailing_address_zip

      t.timestamps
    end
  end
end
```

Run: `bundle exec rails db:migrate`

- [ ] **Step 4: Write the model**

```ruby
# frozen_string_literal: true

class TransactionParty < ApplicationRecord
  belongs_to :transaction
  belongs_to :role

  has_many :envelope_parts, dependent: :destroy
  has_many :envelopes, through: :envelope_parts

  enum :party_type, { individual: 0, business: 1 }

  validates :first_name, :last_name, presence: true, if: :individual?
  validates :company_name, :signer_first_name, :signer_last_name, :signer_title, presence: true, if: :business?

  def display_name
    if business?
      "#{company_name} (#{signer_first_name} #{signer_last_name})"
    else
      "#{first_name} #{last_name}"
    end
  end

  def signer_name
    business? ? "#{signer_first_name} #{signer_last_name}" : "#{first_name} #{last_name}"
  end
end
```

- [ ] **Step 5: Add the ability rule**

In `lib/ability.rb`:

```ruby
    can :manage, TransactionParty, transaction: { account_id: user.account_id }
```

- [ ] **Step 6: Write the factory**

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :transaction_party do
    transaction
    role

    party_type { 'individual' }
    first_name { 'Jane' }
    last_name { 'Doe' }
    email { 'jane@example.com' }

    trait :business do
      party_type { 'business' }
      company_name { 'Acme LLC' }
      signer_first_name { 'Jane' }
      signer_last_name { 'Doe' }
      signer_title { 'Managing Member' }
    end
  end
end
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/transaction_party_model_spec.rb`
Expected: PASS (6 examples)

- [ ] **Step 8: Un-skip the pending Task 1 and Task 2 examples**

Remove the `skip:` keyword from the pending example in `spec/lib/roles_model_spec.rb` and from `spec/system/roles_settings_spec.rb`.

Run: `bundle exec rspec spec/lib/roles_model_spec.rb spec/system/roles_settings_spec.rb`
Expected: PASS (all examples, none pending)

- [ ] **Step 9: Commit**

```bash
git add db/migrate/20260923000003_create_transaction_parties.rb db/schema.rb app/models/transaction_party.rb lib/ability.rb spec/factories/transaction_parties.rb spec/lib/transaction_party_model_spec.rb spec/lib/roles_model_spec.rb spec/system/roles_settings_spec.rb
git commit -m "Add TransactionParty model with individual/business validation"
```

---

## Task 6: Transaction party CRUD UI (nested under a transaction)

**Files:**
- Create: `app/controllers/transaction_parties_controller.rb`
- Create: `app/views/transaction_parties/new.html.erb`
- Create: `app/views/transaction_parties/edit.html.erb`
- Create: `app/views/transaction_parties/_form.html.erb`
- Modify: `app/views/transactions/show.html.erb`
- Create: `spec/system/transaction_parties_spec.rb`
- Modify: `config/routes.rb`

**Interfaces:**
- Consumes: `TransactionParty` (Task 5), `Roles.find_or_create_by_name` (Task 2)
- Produces: `new_transaction_transaction_party_path(transaction)`, `edit_transaction_transaction_party_path(transaction, party)` route helpers.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe 'Transaction Parties' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:, name: '123 E Main St Unit A') }

  before { sign_in(user) }

  it 'adds an individual party with an existing role' do
    create(:role, account:, name: 'Buyer')

    visit transaction_path(transaction)
    click_link 'Add Party'

    select 'Buyer', from: 'transaction_party[role_id]'
    fill_in 'transaction_party[first_name]', with: 'Jane'
    fill_in 'transaction_party[last_name]', with: 'Doe'
    fill_in 'transaction_party[email]', with: 'jane@example.com'

    expect do
      click_button 'Add Party'
    end.to change(TransactionParty, :count).by(1)

    expect(page).to have_content('Jane Doe')
    expect(page).to have_content('Buyer')
  end

  it 'adds a new role inline while adding a party' do
    visit transaction_path(transaction)
    click_link 'Add Party'

    select '+ Add new role...', from: 'transaction_party[role_id]'
    fill_in 'new_role_name', with: 'Escrow Agent'
    fill_in 'transaction_party[first_name]', with: 'Sam'
    fill_in 'transaction_party[last_name]', with: 'Lee'

    expect do
      click_button 'Add Party'
    end.to change(Role, :count).by(1).and change(TransactionParty, :count).by(1)

    expect(account.roles.last.name).to eq('Escrow Agent')
  end

  it 'toggles to a business party and requires signer name/title' do
    create(:role, account:, name: 'Seller')

    visit transaction_path(transaction)
    click_link 'Add Party'

    select 'Seller', from: 'transaction_party[role_id]'
    select 'Business', from: 'transaction_party[party_type]'
    fill_in 'transaction_party[company_name]', with: 'Acme LLC'

    expect do
      click_button 'Add Party'
    end.not_to change(TransactionParty, :count)

    expect(page).to have_content("can't be blank")
  end

  it 'edits an existing party' do
    role = create(:role, account:, name: 'Buyer')
    party = create(:transaction_party, transaction:, role:, first_name: 'Jane', last_name: 'Doe')

    visit transaction_path(transaction)
    click_link 'Edit', href: edit_transaction_transaction_party_path(transaction, party)

    fill_in 'transaction_party[last_name]', with: 'Smith'
    click_button 'Save'

    expect(party.reload.last_name).to eq('Smith')
  end
end
```

Save as `spec/system/transaction_parties_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/transaction_parties_spec.rb`
Expected: FAIL — `undefined method 'new_transaction_transaction_party_path'`

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, change the Task 4 `resources :transactions, only: %i[new create edit update show destroy]` line into a block:

```ruby
  resources :transactions, only: %i[new create edit update show destroy] do
    resources :transaction_parties, only: %i[new create edit update destroy]
  end
```

- [ ] **Step 4: Write the controller**

```ruby
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
```

- [ ] **Step 5: Write the shared form partial**

```erb
<%= form_for [transaction, transaction_party] do |f| %>
  <div class="form-control mb-4">
    <%= f.label :role_id, 'Role' %>
    <%= f.select :role_id, options_for_select(transaction.account.roles.order(:name).pluck(:name, :id), transaction_party.role_id), { include_blank: false }, class: 'base-select' %>
    <select name="transaction_party[role_id]" class="base-select mt-1" onchange="document.getElementById('new_role_wrapper').classList.toggle('hidden', this.value !== '<%= TransactionPartiesController::NEW_ROLE_OPTION %>')">
      <% transaction.account.roles.order(:name).each do |role| %>
        <option value="<%= role.id %>" <%= 'selected' if transaction_party.role_id == role.id %>><%= role.name %></option>
      <% end %>
      <option value="<%= TransactionPartiesController::NEW_ROLE_OPTION %>">+ Add new role...</option>
    </select>
    <div id="new_role_wrapper" class="hidden mt-2">
      <%= text_field_tag :new_role_name, nil, id: 'new_role_name', class: 'base-input', placeholder: 'New role name' %>
    </div>
  </div>

  <div class="form-control mb-4">
    <%= f.label :party_type, 'Party Type' %>
    <toggle-attribute data-target-id="business_fields" data-class-name="hidden" data-value="business">
      <%= f.select :party_type, [['Individual', 'individual'], ['Business', 'business']], {}, class: 'base-select' %>
    </toggle-attribute>
  </div>

  <div id="individual_fields" class="<%= 'hidden' if transaction_party.business? %>">
    <div class="form-control mb-2"><%= f.label :first_name %> <%= f.text_field :first_name, class: 'base-input' %></div>
    <div class="form-control mb-2"><%= f.label :last_name %> <%= f.text_field :last_name, class: 'base-input' %></div>
  </div>

  <div id="business_fields" class="<%= 'hidden' unless transaction_party.business? %>">
    <div class="form-control mb-2"><%= f.label :company_name %> <%= f.text_field :company_name, class: 'base-input' %></div>
    <div class="form-control mb-2"><%= f.label :signer_first_name, 'Signer First Name' %> <%= f.text_field :signer_first_name, class: 'base-input' %></div>
    <div class="form-control mb-2"><%= f.label :signer_last_name, 'Signer Last Name' %> <%= f.text_field :signer_last_name, class: 'base-input' %></div>
    <div class="form-control mb-2"><%= f.label :signer_title, 'Signer Title' %> <%= f.text_field :signer_title, class: 'base-input' %></div>
  </div>

  <div class="form-control mb-2"><%= f.label :email %> <%= f.text_field :email, class: 'base-input' %></div>
  <div class="form-control mb-2"><%= f.label :phone %> <%= f.text_field :phone, class: 'base-input' %></div>

  <div class="form-control mb-2"><%= f.label :address_street, 'Address' %> <%= f.text_field :address_street, class: 'base-input mb-1' %></div>
  <div class="grid grid-cols-3 gap-2 mb-4">
    <%= f.text_field :address_city, class: 'base-input', placeholder: 'City' %>
    <%= f.text_field :address_state, class: 'base-input', placeholder: 'State' %>
    <%= f.text_field :address_zip, class: 'base-input', placeholder: 'ZIP' %>
  </div>

  <% if transaction_party.errors.any? %>
    <div class="text-error mb-4"><%= transaction_party.errors.full_messages.to_sentence %></div>
  <% end %>

  <%= f.submit transaction_party.new_record? ? 'Add Party' : 'Save', class: 'btn btn-neutral' %>
<% end %>
```

Note: this partial deliberately omits `role_id` from the visible `f.select` and uses a plain `select_tag`-style raw `<select name="transaction_party[role_id]">` instead, so the inline "+ Add new role..." option can be handled with plain `onchange` JS without fighting Rails' `form_for` select helper twice for the same field — remove the first (unused) `f.select :role_id` line above; only the raw `<select name="transaction_party[role_id]">` should remain. Fix this before running tests:

Delete this line from the partial:
```erb
    <%= f.select :role_id, options_for_select(transaction.account.roles.order(:name).pluck(:name, :id), transaction_party.role_id), { include_blank: false }, class: 'base-select' %>
```

- [ ] **Step 6: Write new.html.erb and edit.html.erb**

`app/views/transaction_parties/new.html.erb`:

```erb
<h1 class="text-2xl font-bold mb-4">Add Party to <%= @transaction.name %></h1>
<%= render 'form', transaction: @transaction, transaction_party: @transaction_party %>
```

`app/views/transaction_parties/edit.html.erb`:

```erb
<h1 class="text-2xl font-bold mb-4">Edit Party</h1>
<%= render 'form', transaction: @transaction, transaction_party: @transaction_party %>
```

- [ ] **Step 7: Wire up the transaction show page**

In `app/views/transactions/show.html.erb`, add below the existing "Edit" link:

```erb
<h2 class="text-xl font-bold mt-6 mb-2">Parties</h2>
<%= link_to 'Add Party', new_transaction_transaction_party_path(@transaction), class: 'btn btn-neutral btn-sm mb-2' %>
<div class="space-y-2">
  <% @transaction.transaction_parties.includes(:role).each do |party| %>
    <div class="base-input flex justify-between items-center">
      <span><%= party.display_name %> — <%= party.role.name %></span>
      <%= link_to 'Edit', edit_transaction_transaction_party_path(@transaction, party) %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 8: Run test to verify it passes**

Run: `bundle exec rspec spec/system/transaction_parties_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 9: Commit**

```bash
git add app/controllers/transaction_parties_controller.rb app/views/transaction_parties app/views/transactions/show.html.erb config/routes.rb spec/system/transaction_parties_spec.rb
git commit -m "Add transaction party CRUD with individual/business toggle and inline role creation"
```

---

## Task 7: Envelope, EnvelopeSourceTemplate, EnvelopePart models + migrations

**Files:**
- Create: `db/migrate/20260923000004_create_envelopes.rb`
- Create: `db/migrate/20260923000005_create_envelope_source_templates.rb`
- Create: `db/migrate/20260923000006_create_envelope_parts.rb`
- Create: `app/models/envelope.rb`
- Create: `app/models/envelope_source_template.rb`
- Create: `app/models/envelope_part.rb`
- Create: `spec/factories/envelopes.rb`
- Modify: `app/models/template.rb` (add `has_many :envelope_source_templates, foreign_key: :source_template_id, dependent: :destroy`)
- Modify: `lib/ability.rb`

**Interfaces:**
- Produces: `Envelope` — `belongs_to :transaction`, `belongs_to :template, optional: true`, `belongs_to :submission, optional: true`, `enum :status, { draft: 0, sent: 1, completed: 2, voided: 3 }`, `has_many :envelope_source_templates, -> { order(:position) }, dependent: :destroy`, `has_many :source_templates, through: :envelope_source_templates`, `has_many :envelope_parts, dependent: :destroy`, `has_many :transaction_parties, through: :envelope_parts`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe Envelope do
  let(:account) { create(:account) }
  let(:transaction) { create(:transaction, account:) }
  let(:author) { create(:user, account:) }

  it 'is valid with a name and defaults to draft status' do
    envelope = create(:envelope, transaction:, name: 'Lease Packet')

    expect(envelope).to be_draft
  end

  it 'tracks its source templates in order' do
    template_a = create(:template, account:, author:)
    template_b = create(:template, account:, author:)
    envelope = create(:envelope, transaction:)

    envelope.envelope_source_templates.create!(source_template: template_a, position: 0)
    envelope.envelope_source_templates.create!(source_template: template_b, position: 1)

    expect(envelope.source_templates).to eq([template_a, template_b])
  end

  it 'tracks which transaction parties are included' do
    role = create(:role, account:)
    party = create(:transaction_party, transaction:, role:)
    envelope = create(:envelope, transaction:)

    envelope.envelope_parts.create!(transaction_party: party)

    expect(envelope.transaction_parties).to eq([party])
  end
end
```

Save as `spec/lib/envelope_model_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/envelope_model_spec.rb`
Expected: FAIL — `uninitialized constant Envelope`

- [ ] **Step 3: Write the migrations**

`db/migrate/20260923000004_create_envelopes.rb`:

```ruby
# frozen_string_literal: true

class CreateEnvelopes < ActiveRecord::Migration[8.0]
  def change
    create_table :envelopes do |t|
      t.references :transaction, null: false, foreign_key: true, index: true
      t.references :template, null: true, foreign_key: true, index: true
      t.references :submission, null: true, foreign_key: true, index: true

      t.string :name, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
```

`db/migrate/20260923000005_create_envelope_source_templates.rb`:

```ruby
# frozen_string_literal: true

class CreateEnvelopeSourceTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :envelope_source_templates do |t|
      t.references :envelope, null: false, foreign_key: true, index: true
      t.references :source_template, null: false, foreign_key: { to_table: :templates }, index: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
```

`db/migrate/20260923000006_create_envelope_parts.rb`:

```ruby
# frozen_string_literal: true

class CreateEnvelopeParts < ActiveRecord::Migration[8.0]
  def change
    create_table :envelope_parts do |t|
      t.references :envelope, null: false, foreign_key: true, index: true
      t.references :transaction_party, null: false, foreign_key: true, index: true

      t.timestamps
    end
  end
end
```

Run: `bundle exec rails db:migrate`

- [ ] **Step 4: Write the models**

`app/models/envelope.rb`:

```ruby
# frozen_string_literal: true

class Envelope < ApplicationRecord
  belongs_to :transaction
  belongs_to :template, optional: true
  belongs_to :submission, optional: true

  has_many :envelope_source_templates, -> { order(:position) }, dependent: :destroy
  has_many :source_templates, through: :envelope_source_templates
  has_many :envelope_parts, dependent: :destroy
  has_many :transaction_parties, through: :envelope_parts

  enum :status, { draft: 0, sent: 1, completed: 2, voided: 3 }

  validates :name, presence: true
end
```

`app/models/envelope_source_template.rb`:

```ruby
# frozen_string_literal: true

class EnvelopeSourceTemplate < ApplicationRecord
  belongs_to :envelope
  belongs_to :source_template, class_name: 'Template'
end
```

`app/models/envelope_part.rb`:

```ruby
# frozen_string_literal: true

class EnvelopePart < ApplicationRecord
  belongs_to :envelope
  belongs_to :transaction_party
end
```

- [ ] **Step 5: Add the reverse Template association**

In `app/models/template.rb`, alongside `has_many :submissions, dependent: :destroy`, add:

```ruby
  has_many :envelope_source_templates, foreign_key: :source_template_id, inverse_of: :source_template,
                                       dependent: :destroy
```

- [ ] **Step 6: Add ability rules**

In `lib/ability.rb`:

```ruby
    can :manage, Envelope, transaction: { account_id: user.account_id }
```

- [ ] **Step 7: Write the factory**

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :envelope do
    transaction

    sequence(:name) { |n| "Envelope #{n}" }
  end
end
```

- [ ] **Step 8: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/envelope_model_spec.rb`
Expected: PASS (3 examples)

- [ ] **Step 9: Commit**

```bash
git add db/migrate/20260923000004_create_envelopes.rb db/migrate/20260923000005_create_envelope_source_templates.rb db/migrate/20260923000006_create_envelope_parts.rb db/schema.rb app/models/envelope.rb app/models/envelope_source_template.rb app/models/envelope_part.rb app/models/template.rb lib/ability.rb spec/factories/envelopes.rb spec/lib/envelope_model_spec.rb
git commit -m "Add Envelope, EnvelopeSourceTemplate, and EnvelopePart models"
```

---

## Task 8: Envelopes::Merge service

This is the core, highest-risk piece: combining N templates' documents/fields/schema into one, unifying same-named roles into single submitter slots, without corrupting attachment references.

**Files:**
- Create: `lib/envelopes/merge.rb`
- Create: `spec/lib/envelopes/merge_spec.rb`

**Interfaces:**
- Consumes: `Templates::Clone.update_submitters_and_fields_and_schema` (existing), `Templates::CloneAttachments.call` (existing)
- Produces: `Envelopes::Merge.call(envelope:, author:)` — persists and returns a new saved `Template` built from `envelope.source_templates` (in position order), and sets `envelope.template = <that template>` (does not save the envelope — the caller, Task 12, does that as part of a larger transaction).

- [ ] **Step 1: Write the failing test**

```ruby
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
    envelope = create(:envelope, transaction:)
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
    envelope = create(:envelope, transaction:)
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
    envelope = create(:envelope, transaction:)
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
    envelope = create(:envelope, transaction:)
    envelope.envelope_source_templates.create!(source_template: template_a, position: 0)

    Envelopes::Merge.call(envelope:, author:)

    expect(envelope.template).to be_present
    expect(envelope.reload.template_id).to be_nil
  end
end
```

Save as `spec/lib/envelopes/merge_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/envelopes/merge_spec.rb`
Expected: FAIL — `uninitialized constant Envelopes`

- [ ] **Step 3: Write the service**

```ruby
# frozen_string_literal: true

module Envelopes
  module Merge
    module_function

    def call(envelope:, author:)
      merged = author.account.templates.new(
        name: envelope.name,
        author:,
        folder: author.account.default_template_folder,
        submitters: [],
        fields: [],
        schema: [],
        preferences: {}
      )

      role_uuid_by_name = {}
      source_attachment_uuids_by_template_id = {}

      envelope.source_templates.each do |source_template|
        merge_source_template(merged, source_template, role_uuid_by_name)

        source_attachment_uuids_by_template_id[source_template.id] =
          source_template.schema.pluck('attachment_uuid')
      end

      merged.save!

      attach_documents(merged, envelope.source_templates, source_attachment_uuids_by_template_id)

      envelope.template = merged

      merged
    end

    def merge_source_template(merged, source_template, role_uuid_by_name)
      cloned_submitters, cloned_fields, cloned_schema, =
        Templates::Clone.update_submitters_and_fields_and_schema(
          source_template.submitters.deep_dup,
          source_template.fields.deep_dup,
          source_template.schema.deep_dup,
          source_template.preferences.deep_dup
        )

      uuid_remap = {}

      cloned_submitters.each do |submitter|
        canonical_uuid = role_uuid_by_name[submitter['name']]

        if canonical_uuid
          uuid_remap[submitter['uuid']] = canonical_uuid
        else
          role_uuid_by_name[submitter['name']] = submitter['uuid']
          merged.submitters << submitter
        end
      end

      cloned_fields.each do |field|
        remapped = uuid_remap[field['submitter_uuid']]
        field['submitter_uuid'] = remapped if remapped
      end

      merged.fields.concat(cloned_fields)
      merged.schema.concat(cloned_schema)
    end

    def attach_documents(merged, source_templates, source_attachment_uuids_by_template_id)
      source_templates.each do |source_template|
        this_source_uuids = source_attachment_uuids_by_template_id.fetch(source_template.id)
        excluded_attachment_uuids = merged.schema.pluck('attachment_uuid') - this_source_uuids

        Templates::CloneAttachments.call(
          template: merged,
          original_template: source_template,
          excluded_attachment_uuids:
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/envelopes/merge_spec.rb`
Expected: PASS (4 examples)

If the "does not corrupt attachment references" test fails because `Templates::CloneAttachments.call` mutates `schema_item['attachment_uuid']` for excluded items despite the exclusion check — re-read `lib/templates/clone_attachments.rb`'s `next if excluded_attachment_uuids.include?(schema_item['attachment_uuid'])` line: this check runs against the CURRENT value of `schema_item['attachment_uuid']`, which for excluded items must still equal an ORIGINAL uuid from a different, not-yet-processed source at the time this runs. Confirm the loop order: since Step 3's `merge_source_template` never touches `schema_item['attachment_uuid']` (only `Templates::Clone` fields/submitters are remapped, schema attachment_uuid values are carried over untouched from each source until `CloneAttachments` runs), every schema item's attachment_uuid is still its original source value going into `attach_documents`, so the exclusion set computed as `merged.schema.pluck('attachment_uuid') - this_source_uuids` correctly identifies every OTHER source's untouched original uuids at each iteration. This should pass as designed; if it doesn't, print `merged.schema` before and after each `CloneAttachments.call` in the test to see which item's uuid changed unexpectedly, and fix the exclusion set computation rather than the exclusion check itself.

- [ ] **Step 5: Commit**

```bash
git add lib/envelopes/merge.rb spec/lib/envelopes/merge_spec.rb
git commit -m "Add Envelopes::Merge service combining multiple templates into one"
```

---

## Task 9: Envelope build flow — step 1 (template picker)

**Files:**
- Create: `app/controllers/envelopes_controller.rb`
- Create: `app/views/envelopes/new.html.erb`
- Create: `app/views/envelopes/show.html.erb`
- Modify: `app/views/transactions/show.html.erb`
- Create: `spec/system/envelope_build_spec.rb`
- Modify: `config/routes.rb`

**Interfaces:**
- Consumes: `Envelope`, `EnvelopeSourceTemplate` (Task 7)
- Produces: `new_transaction_envelope_path(transaction)`, `transaction_envelope_path(transaction, envelope)` route helpers Task 10/11/12 build on. `EnvelopesController#create` persists a `draft` `Envelope` plus its `EnvelopeSourceTemplate` rows and redirects into the role-resolution step (Task 10).

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe 'Envelope Build - Template Picker' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:template_a) { create(:template, account:, author: user, name: 'Lease Agreement') }
  let!(:template_b) { create(:template, account:, author: user, name: 'Disclosure Form') }

  before { sign_in(user) }

  it 'shows the template picker' do
    visit new_transaction_envelope_path(transaction)

    expect(page).to have_content('Lease Agreement')
    expect(page).to have_content('Disclosure Form')
  end

  it 'creates a draft envelope with the selected templates in order' do
    visit new_transaction_envelope_path(transaction)

    fill_in 'envelope[name]', with: 'Move-In Packet'
    check "template_ids_#{template_a.id}"
    check "template_ids_#{template_b.id}"

    expect do
      click_button 'Next: Assign Roles'
    end.to change(Envelope, :count).by(1).and change(EnvelopeSourceTemplate, :count).by(2)

    envelope = transaction.envelopes.last

    expect(envelope).to be_draft
    expect(envelope.source_templates).to eq([template_a, template_b])
  end

  it 'requires at least one template to be selected' do
    visit new_transaction_envelope_path(transaction)

    fill_in 'envelope[name]', with: 'Move-In Packet'

    expect do
      click_button 'Next: Assign Roles'
    end.not_to change(Envelope, :count)

    expect(page).to have_content('Select at least one template')
  end
end
```

Save as `spec/system/envelope_build_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/envelope_build_spec.rb`
Expected: FAIL — `undefined method 'new_transaction_envelope_path'`

- [ ] **Step 3: Add the routes**

In `config/routes.rb`, add nested under the `resources :transactions ... do` block from Task 6:

```ruby
    resources :envelopes, only: %i[new create show]
```

So the block reads:

```ruby
  resources :transactions, only: %i[new create edit update show destroy] do
    resources :transaction_parties, only: %i[new create edit update destroy]
    resources :envelopes, only: %i[new create show]
  end
```

- [ ] **Step 4: Write the controller**

```ruby
# frozen_string_literal: true

class EnvelopesController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def new
    @templates = Template.active.accessible_by(current_ability).order(:name)
  end

  def show; end

  def create
    template_ids = Array(params[:template_ids]).reject(&:blank?)

    if template_ids.blank?
      @templates = Template.active.accessible_by(current_ability).order(:name)
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
```

Note: `redirect_to transaction_envelope_roles_path` references a route added in Task 10 — until Task 10 lands, this redirect will raise `NoMethodError`. Since Task 9's own tests only assert on `Envelope`/`EnvelopeSourceTemplate` counts and flash content *before* following the redirect (Capybara's `click_button` follows redirects by default, so this WILL surface as a failure) — replace the redirect for now with `redirect_to transaction_path(@transaction)` and revisit it in Task 10's Step 3, where it gets changed to the real target once that route exists.

- [ ] **Step 5: Write the views**

`app/views/envelopes/new.html.erb`:

```erb
<h1 class="text-2xl font-bold mb-4">New Envelope for <%= @transaction.name %></h1>

<%= form_for [@transaction, @envelope], url: transaction_envelopes_path(@transaction) do |f| %>
  <div class="form-control mb-4">
    <%= f.label :name, 'Envelope Name' %>
    <%= f.text_field :name, class: 'base-input', placeholder: 'e.g. Move-In Packet' %>
  </div>

  <h2 class="font-bold mb-2">Select Templates</h2>
  <div class="space-y-2 mb-4">
    <% @templates.each do |template| %>
      <label class="flex items-center gap-2">
        <%= check_box_tag 'template_ids[]', template.id, false, id: "template_ids_#{template.id}" %>
        <%= template.name %>
      </label>
    <% end %>
  </div>

  <%= f.submit 'Next: Assign Roles', class: 'btn btn-neutral' %>
<% end %>
```

`app/views/envelopes/show.html.erb`:

```erb
<h1 class="text-2xl font-bold mb-4"><%= @envelope.name %></h1>
<p>Status: <%= @envelope.status %></p>
```

- [ ] **Step 6: Wire up the transaction show page**

In `app/views/transactions/show.html.erb`, add:

```erb
<h2 class="text-xl font-bold mt-6 mb-2">Envelopes</h2>
<%= link_to 'New Envelope', new_transaction_envelope_path(@transaction), class: 'btn btn-neutral btn-sm mb-2' %>
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bundle exec rspec spec/system/envelope_build_spec.rb`
Expected: PASS (3 examples)

- [ ] **Step 8: Commit**

```bash
git add app/controllers/envelopes_controller.rb app/views/envelopes app/views/transactions/show.html.erb config/routes.rb spec/system/envelope_build_spec.rb
git commit -m "Add envelope build flow step 1: template picker"
```

---

## Task 10: Envelope build flow — step 2 (role resolution)

**Files:**
- Create: `app/controllers/envelope_roles_controller.rb`
- Create: `app/views/envelope_roles/show.html.erb`
- Modify: `app/controllers/envelopes_controller.rb` (fix the Task 9 redirect)
- Modify: `config/routes.rb`
- Create: `spec/system/envelope_role_resolution_spec.rb`

**Interfaces:**
- Consumes: `Envelope`, `TransactionParty`, `Role` (Tasks 1, 5, 7)
- Produces: `transaction_envelope_roles_path(transaction, envelope)` route helper (referenced by Task 9's redirect). `EnvelopeRolesController#unresolved_role_names` — the list of role names appearing in the envelope's source templates with no matching `TransactionParty` on the transaction; other tasks don't consume this directly (it's used only by this controller/view), but it's the key piece of behavior the Review Focus item about mismatched role names depends on.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe 'Envelope Build - Role Resolution' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:buyer_role) { create(:role, account:, name: 'Buyer') }
  let!(:buyer_party) { create(:transaction_party, transaction:, role: buyer_role, first_name: 'Jane', last_name: 'Doe') }

  before { sign_in(user) }

  def build_envelope_with_roles(*role_names)
    template = create(:template, account:, author: user, submitter_count: role_names.size)
    template.submitters.each_with_index { |s, i| s['name'] = role_names[i] }
    template.save!

    envelope = create(:envelope, transaction:, name: 'Test Envelope')
    envelope.envelope_source_templates.create!(source_template: template, position: 0)
    envelope
  end

  it 'auto-resolves when the template role matches an existing party by name' do
    envelope = build_envelope_with_roles('Buyer')

    visit transaction_envelope_roles_path(transaction, envelope)

    expect(page).to have_content('All roles resolved')
    expect(page).to have_link('Next: Choose Parties')
  end

  it 'blocks progress and prompts to resolve an unmatched role' do
    envelope = build_envelope_with_roles('Buyer', 'Agent')

    visit transaction_envelope_roles_path(transaction, envelope)

    expect(page).to have_content('Agent')
    expect(page).not_to have_link('Next: Choose Parties')
    expect(page).to have_button('Add Party for This Role')
  end

  it 'resolves an unmatched role by adding a new party for it, then unblocks progress' do
    envelope = build_envelope_with_roles('Buyer', 'Agent')

    visit transaction_envelope_roles_path(transaction, envelope)
    click_button 'Add Party for This Role'

    expect(page).to have_field('transaction_party[role_id]', with: Role.find_by(name: 'Agent').id.to_s)

    fill_in 'transaction_party[first_name]', with: 'Sam'
    fill_in 'transaction_party[last_name]', with: 'Lee'
    click_button 'Add Party'

    expect(page).to have_content('All roles resolved')
  end

  it 'resolves trivially when the template has no role placeholders' do
    template = create(:template, account:, author: user, submitter_count: 0)
    template.submitters = []
    template.save!
    envelope = create(:envelope, transaction:, name: 'No Roles Envelope')
    envelope.envelope_source_templates.create!(source_template: template, position: 0)

    visit transaction_envelope_roles_path(transaction, envelope)

    expect(page).to have_content('All roles resolved')
  end
end
```

Save as `spec/system/envelope_role_resolution_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/envelope_role_resolution_spec.rb`
Expected: FAIL — `undefined method 'transaction_envelope_roles_path'`

- [ ] **Step 3: Add the route and fix the Task 9 redirect**

In `config/routes.rb`, change:

```ruby
    resources :envelopes, only: %i[new create show]
```

to:

```ruby
    resources :envelopes, only: %i[new create show] do
      resource :roles, only: %i[show], controller: 'envelope_roles'
    end
```

In `app/controllers/envelopes_controller.rb`, change the `create` action's redirect from:

```ruby
    redirect_to transaction_path(@transaction)
```

to:

```ruby
    redirect_to transaction_envelope_roles_path(@transaction, @envelope)
```

- [ ] **Step 4: Write the controller**

```ruby
# frozen_string_literal: true

class EnvelopeRolesController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def show
    @role_names = @envelope.source_templates.flat_map { |t| t.submitters.pluck('name') }.uniq
    @existing_role_names = @transaction.transaction_parties.includes(:role).map { |p| p.role.name }
    @unresolved_role_names = @role_names - @existing_role_names
  end
end
```

- [ ] **Step 5: Write the view**

```erb
<h1 class="text-2xl font-bold mb-4">Assign Roles for <%= @envelope.name %></h1>

<% if @unresolved_role_names.empty? %>
  <p class="text-success mb-4">All roles resolved.</p>
  <%= link_to 'Next: Choose Parties', '#', class: 'btn btn-neutral' %>
<% else %>
  <p class="mb-4">These templates use roles that don't have a matching party on this transaction yet:</p>
  <div class="space-y-4">
    <% @unresolved_role_names.each do |role_name| %>
      <div class="base-input">
        <p class="font-bold mb-2"><%= role_name %></p>
        <%= form_for TransactionParty.new(role: Role.find_by(account: @transaction.account, name: role_name)), url: transaction_transaction_parties_path(@transaction), html: { class: 'flex items-center gap-2' } do |f| %>
          <%= f.hidden_field :role_id, value: Role.find_by(account: @transaction.account, name: role_name).id %>
          <%= f.text_field :first_name, placeholder: 'First Name', class: 'base-input' %>
          <%= f.text_field :last_name, placeholder: 'Last Name', class: 'base-input' %>
          <%= f.submit 'Add Party', class: 'btn btn-neutral btn-sm' %>
        <% end %>
      </div>
    <% end %>
  </div>
<% end %>
```

Note: the "Add Party for This Role" button in the test is the form's own submit button relabeled — rename the submit above from `'Add Party'` to `'Add Party for This Role'` to match the test's `click_button 'Add Party for This Role'` expectation, and keep the *transaction-level* "Add Party" button (Task 6) distinctly labeled `'Add Party'` as already implemented, so the two don't collide within the same test suite's `have_button` lookups across different pages.

Since submitting this form redirects (per Task 6's `TransactionPartiesController#create`) to `transaction_path(@transaction)`, not back to this roles page, add a `return_to` hidden field so the user lands back on the role-resolution screen instead of losing their place:

Update the form to include a redirect-back param:

```erb
          <%= f.hidden_field :role_id, value: Role.find_by(account: @transaction.account, name: role_name).id %>
          <input type="hidden" name="return_to" value="<%= transaction_envelope_roles_path(@transaction, @envelope) %>">
```

And in `app/controllers/transaction_parties_controller.rb`'s `create` action, change the success redirect from:

```ruby
      redirect_to transaction_path(@transaction), notice: 'Party has been added.'
```

to:

```ruby
      redirect_to (params[:return_to].presence || transaction_path(@transaction)), notice: 'Party has been added.'
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bundle exec rspec spec/system/envelope_role_resolution_spec.rb`
Expected: PASS (4 examples)

Also re-run Task 9's suite to confirm the redirect fix didn't break it:

Run: `bundle exec rspec spec/system/envelope_build_spec.rb`
Expected: PASS (3 examples)

- [ ] **Step 7: Commit**

```bash
git add app/controllers/envelope_roles_controller.rb app/controllers/envelopes_controller.rb app/controllers/transaction_parties_controller.rb app/views/envelope_roles config/routes.rb spec/system/envelope_role_resolution_spec.rb
git commit -m "Add envelope build flow step 2: role resolution"
```

---

## Task 11: Autofill prefill mapping service

**Files:**
- Create: `lib/envelopes/prefill_values.rb`
- Create: `spec/lib/envelopes/prefill_values_spec.rb`

**Interfaces:**
- Consumes: `TransactionParty` (Task 5)
- Produces: `Envelopes::PrefillValues.call(party:, field_names:)` — given the list of field names present on the merged template for that party's submitter slot, returns a `{ field_name => value }` hash used by Task 12 when building submitter `values` for the `Submission`.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe Envelopes::PrefillValues do
  let(:account) { create(:account) }
  let(:transaction) { create(:transaction, account:) }
  let(:role) { create(:role, account:, name: 'Buyer') }

  it 'maps an individual party contact info to matching field names' do
    party = create(:transaction_party, transaction:, role:, first_name: 'Jane', last_name: 'Doe',
                                       email: 'jane@example.com', phone: '555-1234',
                                       address_street: '1 Main St', address_city: 'Springfield',
                                       address_state: 'IL', address_zip: '62704')

    values = Envelopes::PrefillValues.call(party:, field_names: %w[Name Email Phone Address Company Title])

    expect(values).to eq(
      'Name' => 'Jane Doe',
      'Email' => 'jane@example.com',
      'Phone' => '555-1234',
      'Address' => '1 Main St, Springfield, IL 62704'
    )
  end

  it 'maps a business party contact info, including company and signer title' do
    party = create(:transaction_party, :business, transaction:, role:, email: 'jane@acme.com')

    values = Envelopes::PrefillValues.call(party:, field_names: %w[Name Email Company Title])

    expect(values).to eq(
      'Name' => 'Jane Doe',
      'Email' => 'jane@acme.com',
      'Company' => 'Acme LLC',
      'Title' => 'Managing Member'
    )
  end

  it 'omits fields the template does not define' do
    party = create(:transaction_party, transaction:, role:, first_name: 'Jane', last_name: 'Doe')

    values = Envelopes::PrefillValues.call(party:, field_names: %w[Name])

    expect(values).to eq('Name' => 'Jane Doe')
  end
end
```

Save as `spec/lib/envelopes/prefill_values_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/envelopes/prefill_values_spec.rb`
Expected: FAIL — `uninitialized constant Envelopes::PrefillValues`

- [ ] **Step 3: Write the service**

```ruby
# frozen_string_literal: true

module Envelopes
  module PrefillValues
    module_function

    def call(party:, field_names:)
      candidates = {
        'Name' => party.signer_name,
        'Email' => party.email,
        'Phone' => party.phone,
        'Address' => format_address(party),
        'Company' => (party.company_name if party.business?),
        'Title' => (party.signer_title if party.business?)
      }

      candidates.slice(*field_names).compact_blank
    end

    def format_address(party)
      return nil if party.address_street.blank?

      [party.address_street, party.address_city, [party.address_state, party.address_zip].compact_blank.join(' ')]
        .compact_blank.join(', ')
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/envelopes/prefill_values_spec.rb`
Expected: PASS (3 examples)

- [ ] **Step 5: Commit**

```bash
git add lib/envelopes/prefill_values.rb spec/lib/envelopes/prefill_values_spec.rb
git commit -m "Add contact-info autofill prefill mapping service"
```

---

## Task 12: Envelope build flow — step 3 (choose parties + send)

**Files:**
- Create: `app/controllers/envelope_send_controller.rb`
- Create: `app/views/envelope_send/show.html.erb`
- Modify: `app/views/envelope_roles/show.html.erb` (point "Next: Choose Parties" at the real route)
- Modify: `config/routes.rb`
- Create: `spec/system/envelope_send_spec.rb`

**Interfaces:**
- Consumes: `Envelopes::Merge` (Task 8), `Envelopes::PrefillValues` (Task 11)
- Produces: on success, a `Submission` created via `Submission.create!` with `submitters` built from the included parties, and the `Envelope` transitions to `sent` with `template_id`/`submission_id` set.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe 'Envelope Build - Choose Parties and Send' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:buyer_role) { create(:role, account:, name: 'Buyer') }
  let!(:seller_role) { create(:role, account:, name: 'Seller') }
  let!(:buyer) { create(:transaction_party, transaction:, role: buyer_role, first_name: 'Jane', last_name: 'Doe', email: 'jane@example.com') }
  let!(:seller) { create(:transaction_party, transaction:, role: seller_role, first_name: 'Sam', last_name: 'Lee', email: 'sam@example.com') }

  let!(:template) do
    t = create(:template, account:, author: user, submitter_count: 2)
    t.submitters[0]['name'] = 'Buyer'
    t.submitters[1]['name'] = 'Seller'
    t.save!
    t
  end

  let!(:envelope) do
    e = create(:envelope, transaction:, name: 'Move-In Packet')
    e.envelope_source_templates.create!(source_template: template, position: 0)
    e
  end

  before { sign_in(user) }

  it 'defaults to including every resolved party' do
    visit transaction_envelope_send_path(transaction, envelope)

    expect(page).to have_field('party_ids[]', checked: true, count: 2)
  end

  it 'sends the envelope to the checked parties, creating a merged template and submission' do
    visit transaction_envelope_send_path(transaction, envelope)
    uncheck "party_ids_#{seller.id}"

    expect do
      click_button 'Send'
    end.to change(Submission, :count).by(1).and change(Template, :count).by(1)

    envelope.reload

    expect(envelope).to be_sent
    expect(envelope.transaction_parties).to eq([buyer])
    expect(envelope.submission.submitters.count).to eq(1)
    expect(envelope.submission.submitters.first.email).to eq('jane@example.com')
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
```

Save as `spec/system/envelope_send_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/envelope_send_spec.rb`
Expected: FAIL — `undefined method 'transaction_envelope_send_path'`

- [ ] **Step 3: Add the route**

In `config/routes.rb`, change:

```ruby
    resources :envelopes, only: %i[new create show] do
      resource :roles, only: %i[show], controller: 'envelope_roles'
    end
```

to:

```ruby
    resources :envelopes, only: %i[new create show] do
      resource :roles, only: %i[show], controller: 'envelope_roles'
      resource :send, only: %i[show create], controller: 'envelope_send'
    end
```

- [ ] **Step 4: Fix the Task 10 "Next: Choose Parties" link**

In `app/views/envelope_roles/show.html.erb`, change:

```erb
  <%= link_to 'Next: Choose Parties', '#', class: 'btn btn-neutral' %>
```

to:

```erb
  <%= link_to 'Next: Choose Parties', transaction_envelope_send_path(@transaction, @envelope), class: 'btn btn-neutral' %>
```

- [ ] **Step 5: Write the controller**

```ruby
# frozen_string_literal: true

class EnvelopeSendController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def show
    @role_names = @envelope.source_templates.flat_map { |t| t.submitters.pluck('name') }.uniq
    @candidate_parties = @transaction.transaction_parties.includes(:role)
                                    .select { |p| @role_names.include?(p.role.name) }
  end

  def create
    party_ids = Array(params[:party_ids]).reject(&:blank?)

    if party_ids.blank?
      flash.now[:alert] = 'Select at least one party.'
      @role_names = @envelope.source_templates.flat_map { |t| t.submitters.pluck('name') }.uniq
      @candidate_parties = @transaction.transaction_parties.includes(:role)
                                       .select { |p| @role_names.include?(p.role.name) }
      return render :show, status: :unprocessable_content
    end

    parties = TransactionParty.where(id: party_ids)

    ActiveRecord::Base.transaction do
      parties.each { |party| @envelope.envelope_parts.create!(transaction_party: party) }

      merged_template = Envelopes::Merge.call(envelope: @envelope, author: current_user)

      submission = Submission.create!(
        account: current_account,
        template: merged_template,
        created_by_user: current_user,
        submitters_order: 'preserved'
      )

      merged_template.submitters.each do |template_submitter|
        party = parties.detect { |p| p.role.name == template_submitter['name'] }

        next unless party

        field_names = merged_template.fields.select { |f| f['submitter_uuid'] == template_submitter['uuid'] }
                                     .filter_map { |f| f['name'] }

        submission.submitters.create!(
          uuid: template_submitter['uuid'],
          email: party.email,
          name: party.signer_name,
          values: Envelopes::PrefillValues.call(party:, field_names:)
        )
      end

      @envelope.update!(template: merged_template, submission:, status: :sent)
    end

    redirect_to transaction_envelope_path(@transaction, @envelope), notice: 'Envelope has been sent.'
  end
end
```

- [ ] **Step 6: Write the view**

```erb
<h1 class="text-2xl font-bold mb-4">Choose Parties for <%= @envelope.name %></h1>

<%= form_for :envelope, url: transaction_envelope_send_path(@transaction, @envelope), method: :post do %>
  <div class="space-y-2 mb-4">
    <% @candidate_parties.each do |party| %>
      <label class="flex items-center gap-2">
        <%= check_box_tag 'party_ids[]', party.id, true, id: "party_ids_#{party.id}" %>
        <%= party.display_name %> (<%= party.role.name %>)
      </label>
    <% end %>
  </div>

  <%= submit_tag 'Send', class: 'btn btn-neutral' %>
<% end %>
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bundle exec rspec spec/system/envelope_send_spec.rb`
Expected: PASS (3 examples)

Also re-run Task 10's suite since its view was modified:

Run: `bundle exec rspec spec/system/envelope_role_resolution_spec.rb`
Expected: PASS (4 examples)

- [ ] **Step 8: Commit**

```bash
git add app/controllers/envelope_send_controller.rb app/views/envelope_send app/views/envelope_roles/show.html.erb config/routes.rb spec/system/envelope_send_spec.rb
git commit -m "Add envelope build flow step 3: choose parties and send"
```

---

## Task 13: Transaction detail page — envelope tracking

**Files:**
- Modify: `app/views/transactions/show.html.erb`
- Modify: `app/controllers/transactions_controller.rb`
- Create: `spec/system/transaction_envelope_tracking_spec.rb`

**Interfaces:**
- Consumes: `Envelope` (Task 7), `Submission` (existing)

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe 'Transaction Envelope Tracking' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:, name: '123 E Main St Unit A') }

  before { sign_in(user) }

  it 'lists draft and sent envelopes with status and a link to the submission when sent' do
    draft_envelope = create(:envelope, transaction:, name: 'Draft Packet')
    template = create(:template, account:, author: user)
    submission = create(:submission, template:, account:, created_by_user: user)
    sent_envelope = create(:envelope, transaction:, name: 'Sent Packet', status: :sent,
                                      template:, submission:)

    visit transaction_path(transaction)

    expect(page).to have_content('Draft Packet')
    expect(page).to have_content('draft')
    expect(page).to have_content('Sent Packet')
    expect(page).to have_content('sent')
    expect(page).to have_link('View Submission', href: submission_path(sent_envelope.submission))
  end
end
```

Save as `spec/system/transaction_envelope_tracking_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/transaction_envelope_tracking_spec.rb`
Expected: FAIL — page does not have content 'Draft Packet' (envelopes aren't listed on the show page yet)

- [ ] **Step 3: Load envelopes in the controller**

In `app/controllers/transactions_controller.rb`'s `show` action, change:

```ruby
  def show; end
```

to:

```ruby
  def show
    @envelopes = @transaction.envelopes.order(created_at: :desc)
  end
```

- [ ] **Step 4: Render the envelope list**

In `app/views/transactions/show.html.erb`, replace the Task 9 line:

```erb
<%= link_to 'New Envelope', new_transaction_envelope_path(@transaction), class: 'btn btn-neutral btn-sm mb-2' %>
```

with:

```erb
<%= link_to 'New Envelope', new_transaction_envelope_path(@transaction), class: 'btn btn-neutral btn-sm mb-2' %>
<div class="space-y-2">
  <% @envelopes.each do |envelope| %>
    <div class="base-input flex justify-between items-center">
      <span><%= envelope.name %> — <%= envelope.status %></span>
      <% if envelope.submission.present? %>
        <%= link_to 'View Submission', submission_path(envelope.submission) %>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/system/transaction_envelope_tracking_spec.rb`
Expected: PASS (1 example)

- [ ] **Step 6: Commit**

```bash
git add app/controllers/transactions_controller.rb app/views/transactions/show.html.erb spec/system/transaction_envelope_tracking_spec.rb
git commit -m "Show envelope status and submission link on the transaction detail page"
```

---

## Task 14: Void a sent envelope

**Files:**
- Create: `app/controllers/envelope_void_controller.rb`
- Modify: `app/views/transactions/show.html.erb`
- Modify: `config/routes.rb`
- Create: `spec/system/envelope_void_spec.rb`

**Interfaces:**
- Consumes: `Envelope#submission` (Task 7), the same archive semantics `SubmissionsController#destroy` already uses (`archived_at: Time.current` + `'submission.archived'` webhook event) — this task reuses that exact mechanism rather than introducing a second, different one.

- [ ] **Step 1: Write the failing test**

```ruby
# frozen_string_literal: true

RSpec.describe 'Voiding a Sent Envelope' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }
  let!(:transaction) { create(:transaction, account:) }
  let!(:template) { create(:template, account:, author: user) }
  let!(:submission) { create(:submission, template:, account:, created_by_user: user) }
  let!(:envelope) do
    create(:envelope, transaction:, name: 'Move-In Packet', status: :sent, template:, submission:)
  end

  before { sign_in(user) }

  it 'shows a Void button only for sent envelopes' do
    visit transaction_path(transaction)

    expect(page).to have_button('Void')
  end

  it 'does not show a Void button for a draft envelope' do
    create(:envelope, transaction:, name: 'Draft Packet')

    visit transaction_path(transaction)

    within('div', text: 'Draft Packet') do
      expect(page).not_to have_button('Void')
    end
  end

  it 'voids the envelope and archives its submission' do
    visit transaction_path(transaction)

    accept_confirm { click_button 'Void' }

    expect(envelope.reload).to be_voided
    expect(submission.reload.archived_at).to be_present
    expect(page).to have_content('Envelope has been voided.')
  end
end
```

Save as `spec/system/envelope_void_spec.rb`.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/system/envelope_void_spec.rb`
Expected: FAIL — no "Void" button rendered yet

- [ ] **Step 3: Add the route**

In `config/routes.rb`, change:

```ruby
    resources :envelopes, only: %i[new create show] do
      resource :roles, only: %i[show], controller: 'envelope_roles'
      resource :send, only: %i[show create], controller: 'envelope_send'
    end
```

to:

```ruby
    resources :envelopes, only: %i[new create show] do
      resource :roles, only: %i[show], controller: 'envelope_roles'
      resource :send, only: %i[show create], controller: 'envelope_send'
      resource :void, only: %i[create], controller: 'envelope_void'
    end
```

- [ ] **Step 4: Write the controller**

```ruby
# frozen_string_literal: true

class EnvelopeVoidController < ApplicationController
  load_and_authorize_resource :transaction
  load_and_authorize_resource :envelope, through: :transaction

  def create
    @envelope.submission.update!(archived_at: Time.current)

    WebhookUrls.enqueue_events(@envelope.submission, 'submission.archived')

    @envelope.update!(status: :voided)

    redirect_to transaction_path(@transaction), notice: 'Envelope has been voided.'
  end
end
```

- [ ] **Step 5: Add the ability rule check**

`EnvelopeVoidController` relies on the existing `can :manage, Envelope, transaction: { account_id: user.account_id }` rule from Task 7 — no new ability rule needed since `load_and_authorize_resource :envelope` defaults to authorizing the controller's action name (`:create`) against that same rule.

- [ ] **Step 6: Render the Void button**

In `app/views/transactions/show.html.erb`, change the envelope list block from Task 13:

```erb
<div class="space-y-2">
  <% @envelopes.each do |envelope| %>
    <div class="base-input flex justify-between items-center">
      <span><%= envelope.name %> — <%= envelope.status %></span>
      <% if envelope.submission.present? %>
        <%= link_to 'View Submission', submission_path(envelope.submission) %>
      <% end %>
    </div>
  <% end %>
</div>
```

to:

```erb
<div class="space-y-2">
  <% @envelopes.each do |envelope| %>
    <div class="base-input flex justify-between items-center" data-envelope-name="<%= envelope.name %>">
      <span><%= envelope.name %> — <%= envelope.status %></span>
      <div class="flex items-center gap-2">
        <% if envelope.submission.present? %>
          <%= link_to 'View Submission', submission_path(envelope.submission) %>
        <% end %>
        <% if envelope.sent? %>
          <%= button_to 'Void', transaction_envelope_void_path(@transaction, envelope), method: :post, form: { data: { turbo_confirm: 'Are you sure?' } }, class: 'btn btn-outline btn-sm' %>
        <% end %>
      </div>
    </div>
  <% end %>
</div>
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bundle exec rspec spec/system/envelope_void_spec.rb`
Expected: PASS (3 examples)

Also re-run Task 13's suite since its view was modified:

Run: `bundle exec rspec spec/system/transaction_envelope_tracking_spec.rb`
Expected: PASS (1 example)

- [ ] **Step 8: Commit**

```bash
git add app/controllers/envelope_void_controller.rb app/views/transactions/show.html.erb config/routes.rb spec/system/envelope_void_spec.rb
git commit -m "Add ability to void a sent envelope, archiving its submission"
```

---

## Task 15: Full-branch regression pass

**Files:** none created; this task only runs the suite.

- [ ] **Step 1: Run the entire new-feature test suite together**

Run:
```bash
bundle exec rspec spec/lib/roles_model_spec.rb spec/system/roles_settings_spec.rb spec/lib/transaction_model_spec.rb spec/lib/transaction_party_model_spec.rb spec/system/transactions_dashboard_spec.rb spec/system/transaction_parties_spec.rb spec/lib/envelope_model_spec.rb spec/lib/envelopes/merge_spec.rb spec/lib/envelopes/prefill_values_spec.rb spec/system/envelope_build_spec.rb spec/system/envelope_role_resolution_spec.rb spec/system/envelope_send_spec.rb spec/system/transaction_envelope_tracking_spec.rb spec/system/envelope_void_spec.rb
```
Expected: PASS, 0 pending, 0 failures

- [ ] **Step 2: Run the full existing suite to confirm no regressions**

Run: `bundle exec rspec`
Expected: PASS — every pre-existing spec (templates, submissions, webhook settings, etc.) still passes unchanged, confirming the new models/controllers/routes didn't collide with or break anything upstream.

- [ ] **Step 3: Run rubocop**

Run: `bundle exec rubocop app/models/role.rb app/models/transaction.rb app/models/transaction_party.rb app/models/envelope.rb app/models/envelope_source_template.rb app/models/envelope_part.rb app/controllers/roles_controller.rb app/controllers/transactions_controller.rb app/controllers/transactions_dashboard_controller.rb app/controllers/transaction_parties_controller.rb app/controllers/envelopes_controller.rb app/controllers/envelope_roles_controller.rb app/controllers/envelope_send_controller.rb app/controllers/envelope_void_controller.rb lib/roles.rb lib/envelopes/merge.rb lib/envelopes/prefill_values.rb`
Expected: no offenses (fix any this codebase's `.rubocop.yml` flags — frozen_string_literal comments are already included in every file above)

- [ ] **Step 4: Manually verify in a real browser**

Rebuild and redeploy per the established loop (`docker build -t docuseal-own:latest . && docker compose up -d`), then click through: create a transaction → add a Buyer and Seller party → create an envelope from two templates whose roles are "Buyer"/"Seller" → confirm role resolution shows "All roles resolved" → send to both parties → confirm the transaction page shows the envelope as "sent" with a working "View Submission" link, and that submission actually shows both submitters with prefilled name/email.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "Transactions & Envelopes feature complete: full regression pass"
git push origin master
```

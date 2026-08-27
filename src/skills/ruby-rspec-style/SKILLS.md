---
name: ruby-rspec-style
description: >
  Generates RSpec tests in Rails Applications with describe/context/it blocks, matchers,
  let/before hooks, and mocking. Use when user mentions "rspec rails", or "rails spec"
languages:
  - Ruby
category: unit-testing
license: MIT
metadata:
  author: TestMu AI
  version: "1.0"
---

## Ruby Code Style Essentials

### Naming

```ruby
  # good
  user_count = User.count
  MAXIMUM_RETRIES = 3
  class InvoiceProcessor; end
  def valid?; end        # predicate
  def save!; end         # dangerous
  _unused, used = result # prefix unused with _
  
  # bad
  userCount = User.count       # not snake_case
  MaxRetries = 3               # not SCREAMING_SNAKE
  class invoice_processor; end # not CamelCase
  ```

### Layout and Formatting
  
```ruby
  # good — 2 spaces, spaces around operators
  def calculate(price, quantity)
    total = price * quantity
    total * TAX_RATE
  end
  
  # good — spacing rules
  some(arg).other                     # no space after (
  [1, 2, 3].each { |e| puts e }       # spaces around { }
  { one: 1, two: 2 }                  # spaces inside hash braces
  user&.name                          # no spaces around & and no spaces at the end of the line
  
  # good — method chaining (leading dot)
  User.active
    .where(role: :admin)
    .order(:name)
    .limit(10)
```

### Flow Control

```ruby
  # good — .each over for, modifier form for single-line
  users.each { |user| process(user) }
  raise 'Invalid' unless valid?
  return if user.nil?
  
  # good — guard clauses keep happy path at low indentation
  def process(data)
    return if data.empty?
    return unless data.valid?
  
    transform(data)
  end
  
  # good — no explicit return at method end
  def full_name
    "#{first_name} #{last_name}"
  end
  
  # good — ternary for simple, case for multiple
  status = active? ? 'active' : 'inactive'
  
  case role
  when :admin then admin_dashboard_path
  when :user  then user_dashboard_path
  else             root_path
  end
  
  # bad
  for user in users do ... end       # use .each
  unless condition ... else ... end  # use if...else
  result = a ? (b ? x : y) : z      # no nested ternaries
```

### Strings and Collections

```ruby
# good — interpolation, heredocs, percent literals
name = "Hello, #{user.name}"
words = %w[foo bar baz]
symbols = %i[name email role]
message = <<~HEREDOC
  Dear #{user.name},
  Welcome aboard!
HEREDOC

# good — collection methods over manual iteration
users.map(&:name)
users.select(&:active?).map(&:email)
ids.each_with_object({}) { |id, hash| hash[id] = fetch(id) }
scores.flat_map(&:values)       # not .map(...).flatten
users.first                      # not users[0]
hash.transform_values(&:upcase)
```

### Methods and Classes

```ruby
# good — keyword arguments for clarity, max 3-4 params
def create_user(name:, email:, role: :user)
  User.create!(name: name, email: email, role: role)
end

# good — consistent class structure
class User < ApplicationRecord
  include Authenticatable

  ROLES = %i[admin user guest].freeze

  attr_accessor :skip_validation

  enum :role, { admin: 0, user: 1, guest: 2 }

  belongs_to :organization
  has_many :posts, dependent: :destroy
  has_many :comments, through: :posts

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, length: { maximum: 100 }

  before_save :normalize_email

  scope :active, -> { where(active: true) }
  scope :recent, -> { order(created_at: :desc) }

  def full_name
    "#{first_name} #{last_name}".strip
  end

  private

  def normalize_email
    self.email = email&.downcase&.strip
  end
end
```

### Exceptions

```ruby
# good — raise with class+message, rescue specific errors
def process_payment(amount)
  raise ArgumentError, "Amount must be positive: #{amount}" if amount <= 0

  gateway.charge(amount)
rescue Stripe::CardError => e
  logger.warn("Card declined: #{e.message}")
  Result.failure(e.message)
rescue StandardError => e
  logger.error("Payment failed: #{e.message}")
  raise
end

# good — custom errors inherit StandardError
class PaymentError < StandardError; end
class InsufficientFundsError < PaymentError; end

# bad
rescue Exception => e   # catches SyntaxError, SignalException
rescue => e; end        # suppresses all errors silently
```

## Rails Conventions Essentials

### Queries — NEVER Interpolate SQL

```ruby
# good — parameterized queries
User.where(name: name)
User.where('age > :min_age', min_age: 18)
User.where(created_at: 7.days.ago..)
Post.where.missing(:author)  # Rails 6.1+

# good — efficient access
User.pluck(:email)           # single column array
User.pick(:name)             # single value from single record
User.ids                     # instead of pluck(:id)
User.find_each { |u| ... }  # batch processing (1000 at a time)
User.order(created_at: :desc) # symbol args, not strings

# bad — SQL injection risk
User.where("name = '#{name}'")
```

### Controllers and Time

```ruby
# good — symbol status codes, skinny controller
def create
  user = User.new(user_params)
  if user.save
    render json: user, status: :created
  else
    render json: { errors: user.errors }, status: :unprocessable_entity
  end
end

# good — respects config.time_zone
Time.current    # not Time.now
2.days.ago      # not Time.current - 2.days
Date.current    # not Date.today
```

## RSpec Structure and Patterns

Always add `rspec-its` gem to the `Gemfile` and `bundle install`.

Whenever testing multiple properties of the same object, use `rspec-its` with much more compact syntax. Keep in mind it only operates on the "subject" of the spec.

Do not use `should` syntax in specs — always use `expect.to` or `expect.not_to`.

```ruby
describe User do
  subject { User.new(user_params) }

  its(:name) { is_expected.to eq 'John' }
  its(:email) { is_expected.to eq 'john@example.com' }
end
```

### In `describe` and `context` string arguments

- `.method` for class methods, `#method` for instance methods in describe blocks
- Context descriptions must always start with "when", "with", "without" — always test positive AND negative cases
- ALWAYS `expect` syntax, NEVER `should`; no "should" in example descriptions — use present tense
- Declaration order: `subject` then `let!/let` then `before/after` then examples
- `let` for lazy loading, `let!` only when eager evaluation required
- FactoryBot factories with traits, NEVER fixtures or inline `Model.create`
- Mock external boundaries only (APIs, third-party services, clock); test real behavior for internal logic
- Prefer request specs over controller specs; system specs over feature specs
- Use `aggregate_failures` for related assertions; `build_stubbed` when DB not needed

### Describe / Context / It

```ruby
RSpec.describe User do
  describe '.find_active' do  # class method with dot
    let!(:active) { create(:user, active: true) }
    let!(:inactive) { create(:user, active: false) }

    it 'returns only active users' do
      expect(described_class.find_active).to contain_exactly(active)
    end
  end

  describe '#full_name' do  # instance method with hash
    subject(:user) { build(:user, first_name: 'Alice', last_name: 'Smith') }

    it 'combines first and last name' do
      expect(user.full_name).to eq('Alice Smith')
    end

    context 'when last name is blank' do
      subject(:user) { build(:user, first_name: 'Alice', last_name: nil) }

      it 'returns only the first name' do
        expect(user.full_name).to eq('Alice')
      end
    end
  end
end
```

### Declaration Order (MANDATORY)

```ruby
  RSpec.describe Article do
    subject(:article) { create(:article) }    # 1. subject
    let(:user) { create(:user) }              # 2. let / let!
  
    before { sign_in(user) }                  # 3. before / after
  
    describe '#publish' do                     # 4. example groups
      it 'marks the article as published' do   # 5. examples
        expect { article.publish }.to change(article, :published).to(true)
      end
    end
  end
```

### Shared Examples and Shoulda Matchers

```ruby
  # Shared examples for cross-cutting concerns
  RSpec.shared_examples 'an authenticated endpoint' do
    context 'when not authenticated' do
      let(:headers) { {} }
      it 'returns 401' do
        make_request
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  # Shoulda matchers for concise model specs
  RSpec.describe User do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to have_many(:posts).dependent(:destroy) }
    it { is_expected.to belong_to(:organization).optional }
    it { is_expected.to define_enum_for(:role).with_values(admin: 0, user: 1) }
    it { is_expected.to have_db_index(:email).unique }
  end
```

[Full RSpec patterns reference](references/rspec-patterns.md)

## Matchers Quick Reference

```ruby
  # Equality and Truth
  expect(x).to eq(y)                      # value equality
  expect(x).to be true                    # exact boolean
  expect(x).to be_nil                     # nil check
  
  # Collections
  expect(arr).to include(item)            # contains element
  expect(arr).to contain_exactly(a, b)    # exact elements, any order
  expect(arr).to all(be > 0)              # all elements match
  expect(hash).to include(key: val)
  
  # Changes
  expect { action }.to change(obj, :attr).from(old).to(new)
  expect { action }.to change { Model.count }.by(1)
  
  # Errors
  expect { action }.to raise_error(SomeError, /message/)
  
  # Predicates (auto-generated from ? methods)
  expect(user).to be_valid                # calls user.valid?
  expect(user).to be_admin                # calls user.admin?
  
  # HTTP (Rails)
  expect(response).to have_http_status(:ok)
  expect(response).to redirect_to(path)
  
  # Compound
  expect(str).to start_with('foo').and end_with('bar')
```


## Mocking and Stubbing Rules

| Mock | Do Not Mock |
|------|-----------|
| External APIs (HTTP calls) | Your own domain logic |
| Third-party services (Stripe, AWS) | ActiveRecord queries |
| System clock (use `travel_to`) | Simple value objects |
| File system / environment vars | Controller/request flow |

```ruby
  # ALWAYS use verified doubles
  payment = instance_double(PaymentGateway)
  allow(payment).to receive(:charge).with(amount: 100).and_return(true)
  expect(payment).to have_received(:charge).once
  
  # HTTP stubbing with WebMock
  stub_request(:get, 'https://api.example.com/users')
    .to_return(status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' })
  
  # Time-dependent tests
  travel_to(Time.zone.local(2024, 1, 15)) do
    expect(user.trial_days_remaining).to eq(30)
  end
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `should` syntax | `expect().to` or `is_expected.to` |
| Instance variables `@` in `before` | Use `let` / `let!` |
| Testing private methods directly | Test through public interface |
| Over-mocking internal logic | Mock only external boundaries |
| `Model.create(...)` in specs | Use FactoryBot: `create(:model)` |
| "should" in descriptions | Present tense: "returns", "creates", "raises" |
| Controller specs (deprecated) | Use request specs |
| Feature specs (deprecated) | Use system specs |
| `Time.now` | `Time.current` (respects timezone) |
| SQL string interpolation | Parameterized: `where(name: name)` |
| `for x in collection` | `collection.each` |
| `rescue Exception` | `rescue StandardError` |
| `unless condition else` | `if condition ... else` |
| Explicit `return` at method end | Implicit return (last expression) |
| `create` when DB not needed | `build` or `build_stubbed` |
| Missing `let!` for queries | `let!` when records must pre-exist |

## Quick Reference

```bash
# Running specs
bundle exec rspec                              # all specs
bundle exec rspec spec/models/user_spec.rb     # single file
bundle exec rspec spec/models/user_spec.rb:42  # single line
bundle exec rspec --tag focus                  # focused only
bundle exec rspec --tag ~slow                  # exclude slow
bundle exec rspec --format documentation       # verbose output
bundle exec rspec --profile 10                 # 10 slowest specs
bundle exec rspec --fail-fast                  # stop on first failure
bundle exec rspec --only-failures              # re-run failures
bundle exec rspec --bisect                     # find minimal failure set

# Code quality
bundle exec rubocop                            # lint Ruby + Rails
bundle exec rubocop -a                         # auto-fix safe cops
bundle exec rubocop -A                         # auto-fix all cops
```

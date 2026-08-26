---
name: rspec-skill
description: >
  Generates RSpec tests in Ruby with describe/context/it blocks, matchers,
  let/before hooks, and mocking. Use when user mentions "RSpec", "describe do",
  "expect().to", "Ruby test". Triggers on: "RSpec", "expect().to eq()",
  "describe do", "Ruby test", "spec file".
languages:
  - Ruby
category: unit-testing
license: MIT
metadata:
  author: TestMu AI
  version: "1.0"
---

# RSpec Testing Skill

## Core Patterns

### Basic Test

```ruby
RSpec.describe Calculator do
  subject(:calculator) { described_class.new }

  describe '#add' do
    it 'adds two positive numbers' do
      expect(calculator.add(2, 3)).to eq(5)
    end

    it 'handles negative numbers' do
      expect(calculator.add(-1, 1)).to eq(0)
    end
  end

  describe '#divide' do
    it 'divides evenly' do
      expect(calculator.divide(10, 2)).to eq(5)
    end

    it 'raises on zero divisor' do
      expect { calculator.divide(10, 0) }.to raise_error(ZeroDivisionError)
    end
  end
end
```

### Matchers

```ruby
# Equality
expect(actual).to eq(expected)           # ==
expect(actual).to eql(expected)          # eql?
expect(actual).to equal(expected)        # equal? (same object)
expect(actual).to be(expected)           # equal?

# Comparison
expect(value).to be > 5
expect(value).to be_between(1, 10).inclusive

# Truthiness
expect(value).to be_truthy
expect(value).to be_falsey
expect(value).to be_nil

# Collections
expect(array).to include(3)
expect(array).to contain_exactly(1, 2, 3)
expect(array).to match_array([3, 1, 2])
expect(hash).to include(name: 'Alice')

# Strings
expect(str).to include('hello')
expect(str).to start_with('He')
expect(str).to match(/\d+/)

# Types
expect(obj).to be_a(String)
expect(obj).to be_an_instance_of(MyClass)

# Exceptions
expect { method }.to raise_error(StandardError)
expect { method }.to raise_error(StandardError, /message/)

# Change
expect { user.activate }.to change(user, :active).from(false).to(true)
expect { list.push(1) }.to change(list, :size).by(1)
```

### Hooks and Let

```ruby
RSpec.describe UserService do
  let(:repo) { instance_double(UserRepository) }
  let(:service) { described_class.new(repo) }

  before(:each) do
    allow(repo).to receive(:save).and_return(true)
  end

  after(:each) { cleanup }
  before(:all) { setup_database }
  after(:all) { teardown_database }

  context 'when creating a user' do
    it 'saves to repository' do
      service.create('Alice', 'alice@test.com')
      expect(repo).to have_received(:save).once
    end
  end
end
```

### Mocking and Stubbing

```ruby
# Doubles
user = double('User', name: 'Alice', email: 'alice@test.com')
user = instance_double(User, name: 'Alice')

# Stubs
allow(service).to receive(:fetch).and_return(data)
allow(service).to receive(:fetch).with('id').and_return(user)

# Expectations
expect(service).to receive(:save).once
expect(service).to receive(:notify).with('alice@test.com')
expect(service).not_to receive(:delete)
```

### Shared Examples

```ruby
RSpec.shared_examples 'a valid model' do
  it { is_expected.to be_valid }
  it { is_expected.to respond_to(:save) }
end

RSpec.describe User do
  subject { described_class.new(name: 'Alice') }
  it_behaves_like 'a valid model'
end
```

### Testing Properties with `rspec-its`

Whenever `rspec` gem is installed, also install `rspec-its` gem. It provides a shorthand for testing properties of objects that are `subjects` in the rspec test suite.



```ruby
RSpec.describe Bicycle do
  subject(:road_bicycle) { described_class.new(type: :road_bike) }
	
  its(:wheels_type) { is_expected.to be(:road_bike_wheels)}
  its("gears.size") { is_expected.to be > 4 } # this runs for both bike types
  
  describe 'a mountain bike' do
    subject(:mountain_bike) { described_class.new(type: :mountain_bike) }
    
    # this overrides the previous :wheels_type test, so it's ok
    its(:wheels_type) { is_expected.to be (:mountain_bike_wheels) }
    its(:wheels) { are_expected.to be_a_kind_of(Array) }
    its(:weight) { is_expected.to be > road_bicycle.weight }
end

```

### Anti-Patterns

| Bad | Good | Why |
|-----|------|-----|
| `before` with heavy setup | `let` (lazy) | Only evaluates when used |
| No contexts | `context 'when...'` | Clear scenarios |
| Instance variables | `let` blocks | Cleaner, lazier |
| `should` syntax | `expect().to` | Modern RSpec |

## Setup: `gem install rspec` then `rspec --init; gem install rspec-its`



## Run: `bundle exec rspec` or `rspec spec/models/user_spec.rb`
## Config: `.rspec` file with `--format progress --color`

## Deep Patterns

For advanced patterns, debugging guides, CI/CD integration, and best practices, see `reference/playbook.md`.



**RSpec:**
18. `.method` for class methods, `#method` for instance methods in describe blocks
19. Context descriptions start with "when", "with", "without" — always test positive AND negative cases
20. ALWAYS `expect` syntax, NEVER `should`; no "should" in example descriptions — use present tense
21. Declaration order: `subject` then `let!/let` then `before/after` then examples
22. `let` for lazy loading, `let!` only when eager evaluation required
23. FactoryBot factories with traits, NEVER fixtures or inline `Model.create`
24. Mock external boundaries only (APIs, third-party services, clock); test real behavior for internal logic
25. Prefer request specs over controller specs; system specs over feature specs
26. Use `aggregate_failures` for related assertions; `build_stubbed` when DB not needed

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
userCount = User.count      # not snake_case
MaxRetries = 3              # not SCREAMING_SNAKE
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
[1, 2, 3].each { |e| puts e }      # spaces around { }
{ one: 1, two: 2 }                 # spaces inside hash braces
user&.name                          # no spaces around &.

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

[Full Ruby style reference](references/ruby-style.md)

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

[Full Rails conventions reference](references/rails-conventions.md)

## RSpec Structure and Patterns

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

[Full matchers reference](references/matchers.md)

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

## Cross-References

- [Full Ruby style rules with examples](references/ruby-style.md)
- [Full Rails conventions](references/rails-conventions.md)
- [RSpec patterns: request, system, model, service, job, mailer specs](references/rspec-patterns.md)
- [RSpec configuration templates](references/rspec-config.md)
- [Complete matchers reference](references/matchers.md)
- [FactoryBot patterns and best practices](references/factories.md)
````
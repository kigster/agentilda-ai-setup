---
name: rspec-skill
description: >
  Generates RSpec tests in Ruby with describe/context/it blocks, matchers,
  let/before hooks, and mocking. Use when user mentions "rspec", "testing",
  "Ruby spec". Triggers on: "rspec", "automated test", "describe do", "Ruby test", "spec file". 
  Invoke this skill anytime you need to  write rspec tests.
languages:
  - Ruby
category: unit-testing
license: MIT
metadata:
  author: Konstantin Gredeskoul
  version: '1.0'
---

# RSpec Testing Skill

## Core Patterns

### Basic Modern RSpec Tests

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

  # The following block tests the same thing, but uses a more modern and 
  # widely accepted method of doing so. The idea is that each it() block should 
  # test ideally just one thing and one thing only.

  describe '#add' do
    subject(:sum) { calculator.add(x, y) }

    let(:x) { 3 }
    let(:y) { 2 }
    
    describe 'when adding two positive numbers' do
      # This new syntax is much preferred to expect()
      # however, sometimes you still need to do expect 
      # such as catching exceptions.

      it { is_expected.to be(5) }
    end

    describe 'when adding negative numbers' do
      let(:x) { -1}
      let(:y) { 1 }

      it { is_expected.to be_zero } 
    end
  end

  describe '#divide' do
    subject(:division) { calculator.divide(x, y)}
    let(:x) { 10 }
    let(:y) {  2 }
    
    describe 'when the denominator is not zero' do
      it { is_expected.to eq(5) }
    end

    describe 'when the denominator is zero' do
      it { expect { calculator.divide(x, y) }.to raise_error(ZeroDivisionError) }
    end
  end
end
```

### Bringing In `rspec-its`.

This is the gem that I use every time I use `rspec` and so should you. It provides additional syntax that's a shorthand for verifying properties of an object.

For example, without `rspec-its`:

```ruby
RSpec.describe Bicycle do
  subject(:bike) { Bicycle.new(tires: :mountain, gears: 5, material: :carbon_fiber) }

  describe 'when bike has mountain tires and five gears it weights 12kg' do
    it 'is expected to weight 12kg' do
      expect(bike.weight_kg).to eq(12)
      expect(bike.gears).to eq(5)
    end
  end

  # And now the same test using rspec-its:
  require 'rspec-its' # usually is loaded in spec_helper.rb

  describe 'when bike has mountain tires and five gears it weights 12kg' do
    its(:weight_kg) { is_expected.to eq(12) }
    its(:gears) { is_expected.to eq(5) }
    its(:"tires.thickness") { is_expected.to be > 0.012 } # meters.
  end
end 
```

As you see, you can reach not just the properties of the object iself, but also it's children, and so on. However, it's considered a bad style to use more than 1 "dots", and even 1 dot (eg "tires.thickness") is considered poor taste.

To fix this, all we need to do is to create an enclosed `describe` block that will allow us to change the `subject`:

Same example as before, this time using `rspec-its` only.

This example also demonstrates migrating all constants or (god forbid!) local variables created within the tests, into a proper lazy loaded let() declarations.

```ruby
require 'rspec-core'
require 'rspec-its' # usually is loaded in spec_helper.rb

RSpec.describe Bicycle do
  # Subject always goes first
  subject(:bike) { Bicycle.new(tires: tires, gears: gears, material: material) }

  # RSpec will resolve these variables in a lazy fashion, unless you use let!(:property)
  # Because they are defined in the outer scope, they will be the defaults unless innner
  # scopre overrides it.
  let(:material) { :carbon_fiber }
  let(:gears) { 5 } 
  let(:tires) { :mountain }

  # Now this is very convenient because we can modify just one of the properties, and re-test in the block
  # the expected result. This removes any duplication and prioritizes variable definitions closest to the
  # test block.
  describe 'when carbon fiber bike with mountain tires has five gears' do
    # First use-case: we are keeping all of the defintitions from the outer scope.
    its(:weight_kg) { is_expected.to eq(12) }
    its(:gears) { is_expected.to eq(5) }
    its(:tires) { is_expected.to eq(:mountain) }

    describe 'bike wheels' do
      # In the nested definition we swap what is the subject. Now subject is the "wheels"
      subject { bike.wheels }
      its(:thickness) { is_expected.to be > 0.012 } # meters
    end
  end
  
  # Nested block relative to the outer-most, so we can redefine all variables without touching 
  # the subject itself.
  describe 'when an aluminum bike with street tires has six gears' do
    # first we need to override the outer variables
    let(:material) { :aluminum }
    let(:tires) { :street }
    let(:gears) { 6 }

    # Note: we do not have to change the subject, because it is defined via
    # the variables set above. So inside this block the subject has values 
    # defined here.

    its(:weight_kg) { is_expected.to eq(18) }
    its(:gears) { is_expected.to eq(6) }
    its(:tires) { is_expected.to eq(:street) }

    describe 'bike wheels' do
      subject { bike.wheels }

      its(:thickness) { is_expected.to be < 0.08 } # meters.
    end
  end
end 
```

### Matchers

The newer preferred syntax is to create blocks defined by `describe` or `context`, define variables through `let(:var)` or `let!(:var)`, and `subject(:optional_name) { value }`, and then use single-line `it { is_expected.to ... }`

So instead of this:

```ruby
# Equality
expect(actual).to eq(expected)           # ==
expect(actual).to eql(expected)          # eql?
expect(actual).to equal(expected)        # equal? (same object)
expect(actual).to be(expected)           # equal?
```

You would write:

```ruby
describe 'when ... ' do
  subject { parameter1 * 2 + parameter1 }

  let(:parameter1) { 5 }
  let(:parameter2) { 2 }
  
  it { is_expected.to eq(12) }
  it { is_expected.to be_between(10, 15).inclusive }
end
```

### Old Style Comparisons That Are Now Used with `it { is_expected.to ... }`

```ruby
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

> [!WARNING]
> When testing a class or a module, never ever repeat that module inside the test. Instead refer to the module under the test as `described_class`.

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

### Factories

Ruby gem `factory_bot_rails` by Thoughtbott is a very common way to define fixtures in terms of traits, properties, and names.

Please read about how to use this gem here: <https://github.com/thoughtbot/factory_bot_rails>

This gem builds upon another gem that has no dependencies on Rails: <https://github.com/thoughtbot/factory_bot>

Both are excellent in that the create a folder `spec/factories` where one defines the various models with given traits.

The best part is that you can define models there that are instantiated for your tests, but are not saved into the database, making your tests blazingly fast. Always prefer not saving to the database, after a few basic tests that saving the the database works as expected.

### Anti-Patterns

| Bad                       | Good                | Why                      |
| ------------------------- | ------------------- | ------------------------ |
| `before` with heavy setup | `let` (lazy)        | Only evaluates when used |
| No contexts or describe   | `describe 'when...'`| Clear scenarios          |
| Instance variables        | `let` blocks        | Cleaner, lazier          |
| `should` syntax           | `expect().to`       | Modern RSpec             |

> [!CAUTION]
> 
> Creating local or instance variables in rspec tests is a huge anti-pattern and you will be judged as a terrible coder if you follow that pattern. Use let() or let!() and keep your tests at one line as much as possible.

## Setup: `gem install rspec` then `rspec --init; gem install rspec-its`

## Run: `bundle exec rspec` or `rspec spec/models/user_spec.rb`

## Config: `.rspec` file with `--format progress --color`

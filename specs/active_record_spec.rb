require "#{File.dirname(__FILE__)}/bootstrap"

require 'rubygems'
require 'activerecord'

# on initialize, we have to make sure we've either:
#
#   a) reconsisited a instance if the state is set
#   b) created a new instance if the state is not set
#
# before_save, we serialise the state to the state field
#
describe "Active Record Workflow" do
  before :each do
    @database = './test.sqlite3'
    File.delete(@database) if File.exist?(@database)
    ActiveRecord::Base.establish_connection(:adapter  => 'sqlite3',
                                            :database => @database)
    ActiveRecord::Migration.verbose = false

    ActiveRecord::Schema.define(:version => 1) do
      create_table 'items', :force => true do |t|
        t.string 'workflow_state'
        t.string 'name'
        t.string 'type'
        t.integer 'user_id'
      end

      create_table 'users', :force => true do |t|
        t.string 'username'
      end
    end

    if not defined?(Item)
      require "#{File.dirname(__FILE__)}/../init"
      class User < ActiveRecord::Base
        has_many :items
        has_one  :special_item, :class_name => "Item", :foreign_key =>"user_id"
      end

      class Item < ActiveRecord::Base
        attr_accessor :before_save_called

        belongs_to :user

        workflow do
          state :first  do event :next, :transitions_to => :second; end
          state :second do event :next, :transitions_to => :third;  end
          state :third
        end

        before_save :register_before_save

        def register_before_save
          @before_save_called = true
        end
      end

      class SubItem < Item
      end
    end

    @item = Item.new
  end

  after do
    @database = './test.sqlite3'
    File.delete(@database) if File.exist?(@database)
  end

  it 'default_values_are_what_we_expect' do
    @item.workflow.should be_kind_of(Workflow::Instance)
    @item.state.should == :first
  end

  it 'serializes current state to a field on ' do
    @item.should_receive(:before_save)
    @item.save
    @item.workflow_state.should == 'first'
  end

  it 'correctly reconsitutes a workflow after find' do
    @item.save
    # heh, futz it baby!
    @item.connection.execute("update items set workflow_state = 'second' where id = #{@item.id}")
    @item = Item.find(@item.id)
    @item.state.should == :second
  end

  it 'default to first state if workflow_state is nil in the database' do
    @item.next # go to second
    @item.save
    @item.connection.execute("update items set workflow_state = null where id = #{@item.id}")
    @item = Item.find(@item.id)
    @item.workflow.state.should == :first
  end

  it 'behaves well with the override of initialize'
  it 'can use a custom field for serializing the current state to'

  # it 'should save to a field called state by default'
  # [:state, :workflow_state, :something_random].each do |field|
  #   it "should initialize in default state if #{field} is null"
  #   it "should reconstitute in state if #{field} is not null"
  #   it "should raise exception if value in #{field} is not a valid state"
  #   it "should serialize out to #{field} before save"
  # end

  it "should recognise subclasses as ActiveRecord Objects" do
    sub_item = SubItem.create!({:name => "subitem"})
    standard_tests(sub_item)
  end

  describe "associations" do
    before :each do
      @mark = User.create!({:username => "mark"})
      chocolate = Item.create!({:name => "chocolate", :user => @mark})
      candy = Item.create!({:name => "candy", :user => @mark})
    end

    it "should add workflow when loaded via a has_many relationship" do
      loaded_item = @mark.items.first
      standard_tests(loaded_item)
      loaded_item.workflow_state.should == "first"
      loaded_item.state.should == :first
      loaded_item.state.should == :first
      loaded_item.next
      loaded_item.before_save_called.should be_nil
      loaded_item.save!
      loaded_item.before_save_called.should be_true
      loaded_item.should be_valid
    end
  end

  def standard_tests(ar_object)
    ar_object.workflow.should be_kind_of(Workflow::Instance)
    ar_object.state(ar_object.state).events.should_not be_empty
    ar_object.should respond_to(:workflow_before_save)
    ar_object.should respond_to(:after_find)
  end
end

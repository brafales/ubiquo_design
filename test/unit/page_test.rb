require File.dirname(__FILE__) + "/../../../../../test/test_helper.rb"

class PageTest < ActiveSupport::TestCase
  use_ubiquo_fixtures

  # Page.publish is a transaction
  self.use_transactional_fixtures = false

  def test_should_create_page
    assert_difference "Page.count" do
      page = create_page
      assert !page.new_record?, "#{page.errors.full_messages.to_sentence}"
    end
  end

  def test_should_create_page_with_empty_url
    Page.delete_all("url_name IS NULL")
    Page.delete_all({:url_name =>  ""})
    assert_difference "Page.count" do
      page = create_page :url_name => ""
      assert !page.new_record?, "#{page.errors.full_messages.to_sentence}"
    end
  end

  def test_should_require_name
    assert_no_difference "Page.count" do
      page = create_page :name => ""
      assert page.errors.on(:name)
    end
  end

  def test_should_require_page_template
    assert_no_difference "Page.count" do
      page = create_page :page_template => nil
      assert page.errors.on(:page_template)
    end
  end

  def test_should_require_valid_url_name
    assert_no_difference "Page.count" do
      ["no spaces", "Lower_Case_only", "no:wrong*symbols", nil].each do |url|
        page = create_page :url_name => url
        assert page.errors.on(:url_name), "Url name should be wrong: '#{url}'"
      end
    end
  end

  def test_should_validate_uniqueness_of_url_name
    Page.delete_all
    assert_difference "Page.count" do
      page = create_page :url_name => ""
      assert !page.new_record?, "#{page.errors.full_messages.to_sentence}"
    end
    assert_no_difference "Page.count" do
      page = create_page :url_name => ""
      assert page.new_record?, "#{page.errors.full_messages.to_sentence}"
    end
  end

  
  def test_should_require_unique_url_name_on_a_published_page
    Page.delete_all
    page_1 = create_page :url_name => ""
    page_1.publish

    page_2 = create_page :url_name => "test"
    page_2.publish

    page_2.url_name = ""
    assert_equal false, page_2.save
  end

  def test_should_create_page_with_is_modified_true
    assert create_page.is_modified
  end

  def test_published_method
    assert !pages(:one).published?
    assert pages(:one_design).published?
  end

  def test_publish_named_scope
    assert_nothing_raised do
      Page.published.all
    end
  end

  def test_drafts_named_scope
    assert_nothing_raised do
      Page.drafts.all
    end
  end

  def test_should_get_widgets_for_block_type
    page = pages(:one)
    block = page.blocks.first(:conditions => { :block_type => "sidebar" })
    assert block.widgets.size > 0 #needs something to test.
    block.widgets.each do |widget|
      assert widget.block.block_type == "sidebar"
    end
  end

  def test_publish_pages
    page = create_page
    page.blocks << pages(:one).blocks
    assert !page.published?
    assert page.is_the_draft?
    assert_nil Page.published.find_by_url_name(page.url_name)
    num_blocks = page.blocks.size
    assert num_blocks > 0
    assert_difference "Page.count" do #New page
      assert_difference "Block.count", num_blocks do # cloned blocks
        assert page.publish
      end
    end
    page.reload
    published = Page.published.find_by_url_name(page.url_name)
    assert_not_nil published
    assert !page.is_modified?
    assert page.published?
  end

  def test_republish_page
    page = create_page
    page.blocks << pages(:one).blocks
    2.times { page.publish }
    assert_not_nil Page.published.find_by_url_name(page.url_name)
  end

  def test_shouldnt_publish_wrong_pages
    page = create_page :page_template => "static"
    page.blocks << pages(:one).blocks
    assert !page.published?
    assert !page.is_the_published?
    assert_nil Page.published.find_by_url_name(page.url_name)

    #creates an error on first widget (Free)
    widget = page.blocks.map(&:widgets).flatten.first
    assert_not_nil widget
    assert_equal widget.class, Free
    widget.content = ""
    widget.save_without_validation
    widget.reload
    assert !widget.valid?

    assert_no_difference "Page.count" do # no new page
      assert_no_difference "Block.count" do # no cloned blocks
        assert_no_difference "Widget.count" do # no cloned widgets
          assert !page.publish
        end
      end
    end
    assert page.is_modified?
  end

  def test_should_destroy_published_page_on_destroy_draft
    page = pages(:one_design)
    assert_difference "Page.count", -2 do
      page.destroy
    end
  end

  def test_shouldnt_destroy_draft_on_destroy_published_page
    page = pages(:one)
    assert_difference "Page.count", -1 do
      page.destroy
    end
    assert_not_nil Page.drafts.find_by_url_name(page.url_name)
  end

  def test_should_set_is_modified_on_save
    page = pages(:one_design)
    page.update_attributes(:is_modified => false)
    page.save
    assert page.is_modified?
  end

  def test_with_url_name_returns_page
    target_url = pages(:one).url_name
    assert_equal target_url, Page.with_url(target_url).url_name
  end

  def test_with_url_name_raises_recordnotfound
    assert_raise ActiveRecord::RecordNotFound do
      Page.with_url 'not/existent'
    end
  end

  def test_with_url_name_returns_page_when_array
    target_url = pages(:long_url).url_name
    assert_equal target_url, Page.with_url(target_url.split('/')).url_name
  end

  def test_should_assign_blocks_on_create
    page = create_page(:url_name => 'about')
    assert_equal 2, page.blocks.size
    assert_equal ["top", "main"], page.blocks.map(&:block_type)
  end

  def test_should_compose_url_with_parent_url_name
    parent_page = pages(:two)
    page = create_page(:url_name => 'card', :parent_id => parent_page.id)
    parent_long_url = pages(:long_url)
    page2 = create_page(:url_name => "foo/bar", :parent_id => parent_long_url.id)
    assert_equal "article/card", page.url_name
    assert_equal "long/url/foo/bar", page2.url_name
  end

  def test_should_create_block_on_add_widget
    # static template has this structure:
    # page_template :static do
    #   block :top, :main
    # end
    page = create_page
    page.blocks = []
    widget = StaticSection.create(:name => 'Test static', :title => 'Test')    
    assert_difference 'Block.count' do
      page.add_widget(:main, widget)
    end
  end

  def test_should_rollback_if_page_has_error_on_add_widget
    page = Page.new(:url_name => "test", :name => "", :page_template => "static")
    assert_no_difference 'Page.count' do
      assert_no_difference 'Widget.count' do
        assert !page.add_widget(:main, StaticSection.new(:name => 'Test static', :title => 'Test'))
      end
    end
    assert page.errors.on(:name)
  end

  def test_should_rollback_if_widget_has_error_on_add_widget
    page = Page.new(:url_name => "test", :name => "test", :page_template => "static")
    widget = StaticSection.new(:name => '', :title => '')
    assert_no_difference 'Page.count' do
      assert_no_difference 'Widget.count' do
          assert !page.add_widget(:main, widget)
      end
    end
    assert widget.errors.on(:name)
  end
  
  def test_should_use_existing_block_on_add_widget
    page = create_page
    page.blocks.create(:block_type => 'main')
    widget = StaticSection.create(:name => 'Test static', :title => 'Test')
    assert_no_difference 'Block.count' do
      page.add_widget(:main, widget)
    end
  end

  def test_should_return_static_section_widget
    page = create_page
    widget = StaticSection.create(:name => 'Test static', :title => 'Test')
    page.add_widget(:main, widget)
    assert_equal widget, page.static_section_widget
  end

  def test_should_return_layout_from_template_in_structure
    UbiquoDesign::Structure.define do
      page_template :example, :layout => 'test_layout'
    end
    page = create_page(:page_template => 'example')
    assert_equal 'test_layout', page.layout
    assert_equal Page::DEFAULT_LAYOUT, create_page.layout
  end

  def test_should_get_default_layout
    assert_equal 'main', Page::DEFAULT_LAYOUT
  end

  private

  # creates a (draft) page
  def create_page(options = {})
    Page.create({:name => "Custom page",
      :url_name => "custom_page",
      :page_template => "static",
      :published_id => nil,
      :is_modified => true
    }.merge(options))
  end
end

require_relative '../../test_helper'

class Webui::MainControllerTest < ActionDispatch::IntegrationTest
  def fetch_sitemap(url)
    get url
    assert_response :success

    sitemap = Xmlhash.parse(response.body)

    sitemap.elements('sitemap') do |s|
      fetch_sitemap(s['loc'])
    end

    sitemap.elements('url') do |s|
      s = URI.parse(s['loc'])
      next if s.path.blank?
      @urls << s.path
    end
  end

  def test_sitemap
    @urls = []
    # verify we can fetch sitemaps and it contains useful stuff
    fetch_sitemap(main_sitemap_path)
    assert @urls.include? '/project/BaseDistro'
    assert @urls.include? '/project/home:Iggy'
    assert @urls.include? '/project/home:coolo:test'
    assert @urls.include? '/package/show/home:coolo:test/kdelibs_DEVEL_package'
    assert @urls.include? '/package/show/home:Iggy/TestPack'
    assert @urls.include? '/package/show/Apache/apache2'
  end
end

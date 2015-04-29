require 'yaml'
require 'slim'
require 'redcarpet'
require 'liquid'
require 'tilt'
require 'sinatra/base'
require 'sinatra/asset_pipeline'
require 'less'
require 'sass'
require 'uglifier'
require 'cucumber/website/page'
require 'cucumber/website/config'
require 'cucumber/website/calendar'
require 'cucumber/website/events'
require 'cucumber/website/reference'

Slim::Engine.set_options(pretty: ENV['RACK_ENV'] != 'production')
Slim::Engine.disable_option_validator!

# Sinatra app that displays a Jekyll app dynamically.
#
# Why? A couple of reasons:
#
# * We have special requirements for the generated docs. Seemed easier to go the dynamic route.
# * We want to have some dynamic content as well as "static".
#
# Supports several template engines: Markdown, Slim and Erb.
# All templates are pre-processed with Liquid.
#
# Markdown can be used to generate reference documentation. Features include:
#
# * Automatic generation of nested left nav based on Markdown headers
# * Uses Bootstrap scroll spy to collapse/expand nav items
# * Mini-smartypants. --- gets converted to an emdash
# * Use [carousel] to create a carousel of code samples for different languages
# * Use {} in headers to create unique anchors when there are clashes
#
module Cucumber
module Website
  class App < Sinatra::Application
    set :root,  File.dirname(__FILE__)

    # TODO: do we need these? Won't they be inferred from the root anyway?
    set :public_folder, Proc.new { File.join(root, 'public') }
    set :views, Proc.new { File.join(root, 'views') }

    set :assets_precompile, %w(main.js main.css *.png *.jpg *.svg *.eot *.ttf *.woff)
    set :assets_prefix, %w(assets bower_components)
    set :assets_css_compressor, :sass
    set :assets_js_compressor, :uglifier
    register Sinatra::AssetPipeline

    extend Config
    CONFIG = load_config(ENV['RACK_ENV'])

    pages = Page.all(CONFIG, views)

    CONFIG['site']['posts'] = pages.select(&:post?).sort do |a, b|
      b.date <=> a.date
    end

    calendar_logger = Logger.new($stderr)
    calendars = CONFIG['site']['calendars'].map { |url| Cucumber::Website::Calendar.new(url, calendar_logger) }
    events = Cucumber::Website::Events.new(pages.select(&:event?), calendars)
    CONFIG['site']['events'] = events

    configure(:development, :production) do
      events.start(CONFIG['site']['calendar_refresh_interval'])
    end

    pages.each do |page|
      next unless page.primary?

      get page.path do
        headers.merge!(page.headers)

        if page.cacheable?
          timestamps = pages.map(&:timestamp) + [File.mtime(__FILE__)]
          last_modified timestamps.max
        end

        page.render(self)
      end
    end

    before do
      cache_control :public
    end

    before /(.*)\.html/ do
      url = params[:captures][0]
      redirect to(url), 301
    end

    helpers do
      def nav_class(slug, name)
        slug == name ? 'active' : nil
      end

      def edit_url(template_path)
        "#{CONFIG['site']['edit_url']}/#{template_path}"
      end
    end
  end
end
end

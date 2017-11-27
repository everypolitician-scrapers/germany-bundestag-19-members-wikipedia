#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'
require 'wikidata_ids_decorator'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

class MembersPage < Scraped::HTML
  decorator WikidataIdsDecorator::Links

  field :members do
    members_table.xpath('.//tr[td]').map do |tr|
      mem = fragment(tr => MemberRow).to_h
      faction = factions.find { |f| f[:colour] == mem[:faction] } || {}
      mem.merge(faction: faction[:name], faction_wikidata: faction[:wikidata])
    end
  end

  field :factions do
    @factions ||= factions_table.xpath('.//tr[td]').map do |tr|
      fragment(tr => FactionRow).to_h
    end
  end

  private

  def members_table
    noko.xpath(".//table[.//th[contains(.,'Mitglied')]]").first
  end

  def factions_table
    noko.xpath(".//table[.//th[contains(.,'Vorsitzende')]]").first
  end
end

class FactionRow < Scraped::HTML
  field :name do
    tds[0].text
  end

  field :wikidata do
    tds[0].css('a/@wikidata').text
  end

  field :colour do
    tds[1].attr('style')[/#(\h+);/, 1]
  end

  private

  def tds
    noko.css('td')
  end
end

class MemberRow < Scraped::HTML
  field :name do
    tds[1].text
  end

  field :sort_name do
    tds.css('td/@data-sort-value').text
  end

  field :wikidata do
    tds[1].css('a/@wikidata').text
  end

  field :birth_year do
    tds[2].text
  end

  field :party do
    tds[3].text
  end

  field :faction do
    # in this table we only have a colour. Capture that, and replace it later
    tds[3].attr('style')[/#(\h+);/, 1]
  end

  field :area do
    tds[4].text
  end

  field :constituency do
    tds[5].text
  end

  field :constituency_wikidata do
    tds[5].css('a/@wikidata')&.text
  end

  field :term do
    19
  end

  private

  def tds
    noko.css('td')
  end
end

url = 'https://de.wikipedia.org/wiki/Liste_der_Mitglieder_des_Deutschen_Bundestages_(19._Wahlperiode)'
page = MembersPage.new(response: Scraped::Request.new(url: url).response)
data = page.members.map(&:to_h)

data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']
ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
ScraperWiki.save_sqlite(%i[name wikidata], data)

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
    table.xpath('.//tr[td]').map do |tr|
      fragment tr => MemberRow
    end
  end

  private

  def table
    noko.xpath(".//table[.//th[contains(.,'Mitglied')]]").first
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

  field :party_wikidata do
    party_colour_to_wikidata(party_colour)
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

  # TODO: Refactor with common code in PartyColourLookup
  def first_html_colour_in_string(s)
    s.match(/#(.*);/)[1]
  end

  # TODO: Refactor with common code in PartyColourLookup
  def party_colour
    first_html_colour_in_string(tds[3].attribute('style').value)
  end

  def party_colour_to_wikidata(colour)
    PartyColourLookup.new(response: response).colours_to_wikidata[colour]
  end
end

class PartyColourLookup < Scraped::HTML
  field :colours_to_wikidata do
    trs.map do |r|
      [colour(r.css('td')[1]), wikidata(r.css('td')[0])]
    end.to_h
  end

  private

  def table
    noko.xpath(".//table[.//th[contains(.,'Vorsitzende')]]").first
  end

  def trs
    table.xpath('.//tr[td]')
  end

  # TODO: Refactor with common code in MemberRow
  def first_html_colour_in_string(s)
    s.match(/#(.*);/)[1]
  end

  # TODO: Refactor with common code in MemberRow
  def colour(td)
    first_html_colour_in_string(td.attribute('style').value)
  end

  def wikidata(td)
    td.css('a/@wikidata').text
  end
end

url = 'https://de.wikipedia.org/wiki/Liste_der_Mitglieder_des_Deutschen_Bundestages_(19._Wahlperiode)'
page = MembersPage.new(response: Scraped::Request.new(url: url).response)
data = page.members.map(&:to_h).map { |m| m.reject { |_, v| v.to_s.empty? } }

data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']
ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
ScraperWiki.save_sqlite(%i[name wikidata], data)

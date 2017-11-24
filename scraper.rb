#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'
require 'wikidata_ids_decorator'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

class PartyWikidata < Scraped::Response::Decorator
  attr_accessor :doc

  def body
    @doc = Nokogiri::HTML(super)
    doc.tap do |d|
      members_table = d.xpath(".//table[.//th[contains(.,'Mitglied')]]").first
      members_table.xpath('.//tr[td]').each do |tr|
        party_td = tr.css('td')[3]
        party_td[:party_wikidata] = colours_to_wikidata[colour(party_td)]
      end
    end.to_s
  end

  private

  def colours_to_wikidata
    table = doc.xpath(".//table[.//th[contains(.,'Vorsitzende')]]").first
    table.xpath('.//tr[td]').map do |r|
      [colour(r.css('td')[1]), wikidata(r.css('td')[0])]
    end.to_h
  end

  def colour(td)
    first_html_colour_in_string(td.attribute('style').value)
  end

  def first_html_colour_in_string(s)
    s.match(/#(.*);/)[1]
  end

  def wikidata(td)
    td.css('a/@wikidata').text
  end
end

class MembersPage < Scraped::HTML
  decorator WikidataIdsDecorator::Links
  decorator PartyWikidata

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
    noko.css('@party_wikidata').text
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
data = page.members.map(&:to_h).map { |m| m.reject { |_, v| v.to_s.empty? } }

data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']
ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
ScraperWiki.save_sqlite(%i[name wikidata], data)

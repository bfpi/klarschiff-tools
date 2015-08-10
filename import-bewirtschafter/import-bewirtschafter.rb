#!/usr/bin/env ruby

require 'yaml'
require 'open-uri'
require 'rexml/document'
require 'pg'

def config(scope = nil)
  @config ||= YAML.load(File.open("config.yml"))
  scope ? @config[scope] : @config
end

class Object
  def blank?
    respond_to?(:empty?) ? !!empty? : !self
  end
end

def load_from_wfs
  conf = config('wfs')
  url = conf["url"]
  raise "wfs:url missing" if url.blank?
  max = conf["max"]
  raise "wfs:max missing" if max.nil? || !max.is_a?(Numeric)
  zugehoerig = conf["zugehoerig"]
  raise "wfs:zugehoerig missing" if zugehoerig.blank?
  raise "wfs:zugehoerig incorrect" if !zugehoerig.is_a?(Array) || zugehoerig.length < 1
  filter = "<Filter>"
  filter << "<OR>" if zugehoerig.length > 1 
  filter << zugehoerig.map do |s|
    "<PropertyIsEqualTo><PropertyName>zugehoerig</PropertyName><Literal>#{ s }</Literal></PropertyIsEqualTo>"
  end.join
  filter << "</OR>" if zugehoerig.length > 1 
  filter << "</Filter>"
  url_with_filter = "#{ url }?SERVICE=WFS&VERSION=1.1.0&SRSNAME=EPSG:25833&REQUEST=GetFeature" \
    "&TYPENAME=dvg:aemter&maxFeatures=#{ max }&filter=#{ URI::encode(filter) }"
  open(url_with_filter) { |f| f.read }
end

def check_for_exception(xml)
  if ex = REXML::XPath.first(xml, "//ows:Exception")
    raise "Fehler beim WFS-Request: #{ ex }"
  end
end

def gml(xml)
  '<gml:MultiSurface srsName="EPSG:25833"><gml:surfaceMembers>' +
    REXML::XPath.match(xml, ".//gml:Polygon").map { |g| g.to_s }.join +
    '</gml:surfaceMembers></gml:MultiSurface>'.gsub(/'/, "\"")
end

def key(xml)
  (xml.text('dvg:zugehoerig') + "%04d" % xml.text('dvg:schluessel').to_s.to_i).to_i
end

def name(xml)
  "#{ xml.text('dvg:kennung') } #{ xml.text('dvg:gen') }"
end

def db
  PG.connect(config('db')["connection"]).tap do |conn|
    def conn.set_bewirtschaftung(key, name, gml)
      conf = config('db')
      table = conf["table"]
      raise "db:table config missing" if table.blank?
      geom_column = conf["columns"]["geom"]
      raise "db:geom column config missing" if geom_column.blank?
      name_column = conf["columns"]["name"]
      raise "db:name column config missing" if name_column.blank?
      key_column = conf["columns"]["key"]
      raise "db:key column config missing" if key_column.blank?
      if res = exec_params(<<-SQL, [key, name]).first
          SELECT id
          FROM #{ table }
          WHERE #{ key_column } = $1 OR TRIM(#{ name_column }) ILIKE $2
        SQL
        puts "Updating... #{ name }"
        exec_params(<<-SQL, [res['id'], key, name, gml])
          UPDATE #{ table }
          SET #{ key_column } = $2, #{ name_column } = $3, 
        #{ geom_column } = ST_GeomFromGML($4)
          WHERE id = $1
        SQL
      else
        puts "Creating... #{ name }"
        exec_params(<<-SQL, [key, name, gml])
          INSERT INTO #{ table } (#{ key_column }, #{ name_column }, #{ geom_column })
          VALUES ($1, $2, ST_GeomFromGML($3))
        SQL
      end
    end
  end
end

doc = REXML::Document.new(load_from_wfs)
check_for_exception(doc)
REXML::XPath.each(doc, "//dvg:aemter") do |amt|
  db.set_bewirtschaftung key(amt), name(amt), gml(amt)
end
